// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {IOracle} from "../interfaces/IOracle.sol";
import {IOraclePool} from "../interfaces/IOraclePool.sol";

/**
 * @title OraclePool Contract
 * @dev A contract that allows to swap `GHO` for `sGHO` and `sGHO` to `GHO` using the exchange rate provided by an oracle.
 * This contract is not compatible with transfer tax tokens.
 * The `SENDER` account is the only account allowed to call the swap and pull functions.
 * It is expected that it takes care of rebalancing the tokens in the contract.
 */
contract OraclePool is Ownable, IOraclePool {
    using SafeERC20 for IERC20;

    address public immutable override SENDER;
    address public immutable override GHO;
    address public immutable override SGHO;

    uint256 private constant PRECISION = 1e18;

    /// @dev Precision multiplier applied to the per-second growth budget so it doesn't round to zero.
    uint256 private constant SCALING_FACTOR = 1e6;

    /// @dev Basis points denominator (10_000 = 100%).
    uint256 private constant BPS = 1e4;

    /// @dev Seconds in a calendar year, used to convert a yearly growth rate into a per-second budget.
    uint256 private constant SECONDS_PER_YEAR = 365 days;

    /// @dev Minimum age a snapshot timestamp must have when passed to `setCapParameters`.
    uint48 private constant MINIMUM_SNAPSHOT_DELAY = 1 days;

    /// @dev Maximum age a snapshot timestamp may have when passed to `setCapParameters`.
    uint48 private constant MAXIMUM_SNAPSHOT_TERM = 180 days;

    IOracle private _oracle;
    uint96 private _fee;

    uint256 private _lastPrice;

    /// @dev The reference price the cap grows from (1e18 scale).
    uint256 private _snapshotPrice;

    /// @dev The timestamp at which `_snapshotPrice` was set.
    uint48 private _snapshotTimestamp;

    /// @dev The maximum yearly growth allowed for the cap (in basis points).
    uint16 private _maxYearlyGrowthBps;

    /// @dev The derived per-second growth budget, scaled by `SCALING_FACTOR`.
    uint256 private _maxPriceGrowthPerSecondScaled;

    /**
     * @dev Modifier to check if the sender is the expected account.
     */
    modifier onlySender() {
        _checkSender();
        _;
    }

    /**
     * @dev Sets the immutable values for {SENDER}, {GHO}, {SGHO} and the initial values for the oracle, the swap fee,
     * the owner, and the maximum yearly growth of the price cap.
     * @param sender The address allowed to call the swap and pull functions.
     * @param gho The address of the GHO token.
     * @param sgho The address of the sGHO token.
     * @param oracle The address of the oracle contract.
     * @param fee The fee to be applied to each swap (in 1e18 scale).
     * @param initialOwner The address of the initial owner.
     * @param maxYearlyGrowthBps The maximum yearly growth of the price cap (in basis points).
     */
    constructor(
        address sender,
        address gho,
        address sgho,
        address oracle,
        uint96 fee,
        address initialOwner,
        uint16 maxYearlyGrowthBps
    ) Ownable(initialOwner) {
        require(
            sender != address(0) && gho != address(0) && sgho != address(0),
            OraclePoolInvalidParameters()
        );

        SENDER = sender;
        GHO = gho;
        SGHO = sgho;

        _maxYearlyGrowthBps = maxYearlyGrowthBps;
        _setOracle(IOracle(oracle));
        _setFee(fee);
    }

    /**
     * @dev Swaps `amountIn` of `GHO` for at least `minAmountOut` of `SGHO` and sends them to `recipient`.
     * It uses the oracle to get the price of `GHO` in `SGHO`. A fee is applied to the amount of tokens to be swapped.
     * The fee is kept in this contract and will be used to pay for the gas price and the potential exchange rate deviation when the
     * `GHO` is exchanged for `SGHO` by the sender.
     *
     * Requirements:
     *
     * - `msg.sender` must be the `SENDER` account.
     * - `oracle` must be set.
     * - The amount of `SGHO` to be received must be greater than or equal to `minAmountOut`.
     * - The amount of `SGHO` available in the contract must be greater than or equal to the amount of `SGHO` to be received.
     * - The `msg.sender` must have approved the contract to spend at least `amountIn` of `GHO`.
     *
     * Emits a {Deposit} event.
     */
    function deposit(
        address recipient,
        uint256 exactAmountIn,
        uint256 minAmountOut
    ) public virtual override onlySender returns (uint256) {
        _validateInputs(recipient, exactAmountIn, address(_oracle));

        uint256 feeAmount = Math.mulDiv(
            exactAmountIn,
            _fee,
            PRECISION,
            Math.Rounding.Ceil
        );

        uint256 amountOut = Math.mulDiv(
            exactAmountIn - feeAmount,
            PRECISION,
            _getLatestPrice(),
            Math.Rounding.Floor
        );

        _validateOutputs(SGHO, amountOut, minAmountOut);

        IERC20(GHO).safeTransferFrom(msg.sender, address(this), exactAmountIn);
        IERC20(SGHO).safeTransfer(recipient, amountOut);

        emit Deposit(recipient, exactAmountIn, amountOut);

        return amountOut;
    }

    /**
     * @dev Swaps `amountIn` of `sGHO` for at least `minAmountOut` of `GHO` and sends them to `recipient`.
     * It uses the oracle to get the price of `sGHO` in `GHO`. A fee is applied to the amount of tokens to be swapped.
     * The fee is kept in this contract and will be used to pay for the gas price and the potential exchange rate deviation when the
     * `SGHO` is exchanged for `GHO` by the sender.
     *
     * Requirements:
     *
     * - `msg.sender` must be the `SENDER` account.
     * - `oracle` must be set.
     * - The amount of `GHO` to be received must be greater than or equal to `minAmountOut`.
     * - The amount of `GHO` available in the contract must be greater than or equal to the amount of `GHO` to be received.
     * - The `msg.sender` must have approved the contract to spend at least `amountIn` of `sGHO`.
     *
     * Emits a {Redeem} event.
     */
    function redeem(
        address recipient,
        uint256 exactAmountIn,
        uint256 minAmountOut
    ) public virtual override onlySender returns (uint256) {
        _validateInputs(recipient, exactAmountIn, address(_oracle));

        uint256 exchangeRateAmount = Math.mulDiv(
            exactAmountIn,
            _getLatestPrice(),
            PRECISION,
            Math.Rounding.Floor
        );

        uint256 feeAmount = Math.mulDiv(
            exchangeRateAmount,
            _fee,
            PRECISION,
            Math.Rounding.Ceil
        );
        uint256 amountOut = exchangeRateAmount - feeAmount;

        _validateOutputs(GHO, amountOut, minAmountOut);

        IERC20(SGHO).safeTransferFrom(msg.sender, address(this), exactAmountIn);
        IERC20(GHO).safeTransfer(recipient, amountOut);

        emit Redeem(recipient, exactAmountIn, amountOut);

        return amountOut;
    }

    /**
     * @dev Pulls `amount` of `token` from the contract and sends them to `msg.sender`.
     *
     * Requirements:
     *
     * - `token` must be equal one of `GHO` or `sGHO`.
     * - The `amount` of `token` to be pulled must be less than or equal to the amount of `token` available in the contract.
     *
     * Emits a {Pull} event.
     */
    function pull(
        address token,
        uint256 amount
    ) public virtual override onlySender {
        require(token == GHO || token == SGHO, OraclePoolPullNotAllowed(token));

        uint256 available = IERC20(token).balanceOf(address(this));
        require(
            available >= amount,
            OraclePoolInsufficientToken(token, amount, available)
        );

        IERC20(token).safeTransfer(msg.sender, amount);

        emit Pull(token, msg.sender, amount);
    }

    /**
     * @dev Sweeps `amount` of `token` from the contract and sends them to `recipient`.
     *
     * Requirements:
     *
     * - `msg.sender` must be the owner.
     *
     * Emits a {Sweep} event.
     */
    function sweep(
        address token,
        address recipient,
        uint256 amount
    ) public virtual override onlyOwner {
        IERC20(token).safeTransfer(recipient, amount);

        emit Sweep(token, recipient, amount);
    }

    /**
     * @dev Sets the oracle contract address.
     */
    function setOracle(address oracle) public virtual override onlyOwner {
        _setOracle(IOracle(oracle));
    }

    /**
     * @dev Sets the fee to be applied to each swap (in 1e18 scale).
     *
     * Requirements:
     *
     * - `fee` must be less than or equal to 1e18.
     */
    function setFee(uint96 fee) public virtual override onlyOwner {
        _setFee(fee);
    }

    /**
     * @dev Re-snapshots the price cap and updates the maximum yearly growth in one call. `_lastPrice` is reset to
     * `snapshotPrice` so a stuck-high reading from before the re-snapshot does not brick swaps.
     *
     * Requirements:
     *
     * - `msg.sender` must be the owner.
     * - `snapshotPrice` must be non-zero.
     * - `snapshotTimestamp` must be strictly newer than the stored one, older than
     *   `block.timestamp - MINIMUM_SNAPSHOT_DELAY`, and not older than `block.timestamp - MAXIMUM_SNAPSHOT_TERM`.
     *
     * Emits a {CapParametersUpdated} event.
     * @param snapshotPrice The new snapshot price (1e18 scale).
     * @param snapshotTimestamp The new snapshot timestamp.
     * @param maxYearlyGrowthBps The new maximum yearly growth (in basis points).
     */
    function setCapParameters(
        uint256 snapshotPrice,
        uint48 snapshotTimestamp,
        uint16 maxYearlyGrowthBps
    ) public virtual override onlyOwner {
        require(snapshotPrice != 0, OraclePoolSnapshotPriceIsZero());
        require(
            _snapshotTimestamp < snapshotTimestamp &&
                snapshotTimestamp <= block.timestamp - MINIMUM_SNAPSHOT_DELAY &&
                snapshotTimestamp >= block.timestamp - MAXIMUM_SNAPSHOT_TERM,
            OraclePoolInvalidSnapshotTimestamp(snapshotTimestamp)
        );

        _maxYearlyGrowthBps = maxYearlyGrowthBps;
        _setSnapshot(snapshotPrice, snapshotTimestamp);
        _lastPrice = snapshotPrice;
    }

    /**
     * @dev Adjusts only the maximum yearly growth. Snapshot and `_lastPrice` are not touched. Lowering this
     * value when `_lastPrice` already exceeds the resulting cap will brick swaps until the next re-snapshot.
     *
     * Requirements:
     *
     * - `msg.sender` must be the owner.
     *
     * Emits a {MaxYearlyGrowthBpsUpdated} event.
     * @param maxYearlyGrowthBps The new maximum yearly growth (in basis points).
     */
    function setMaxYearlyGrowthBps(
        uint16 maxYearlyGrowthBps
    ) public virtual override onlyOwner {
        _maxYearlyGrowthBps = maxYearlyGrowthBps;
        _recomputeMaxGrowthPerSecond();

        emit MaxYearlyGrowthBpsUpdated(
            maxYearlyGrowthBps,
            _maxPriceGrowthPerSecondScaled
        );
    }

    /**
     * @dev Returns the address of the oracle contract.
     */
    function getOracle() public view virtual override returns (address) {
        return address(_oracle);
    }

    /**
     * @dev Returns the fee to be applied to each swap (in 1e18 scale).
     */
    function getFee() public view virtual override returns (uint96) {
        return _fee;
    }

    /**
     * @notice Returns the current price-cap parameters and the derived per-second growth budget.
     * @return snapshotPrice The current snapshot price (1e18 scale).
     * @return snapshotTimestamp The current snapshot timestamp.
     * @return maxYearlyGrowthBps The current maximum yearly growth (in basis points).
     * @return maxPriceGrowthPerSecondScaled The derived per-second growth budget (scaled by 1e6).
     */
    function getCapParameters()
        public
        view
        virtual
        override
        returns (
            uint256 snapshotPrice,
            uint48 snapshotTimestamp,
            uint16 maxYearlyGrowthBps,
            uint256 maxPriceGrowthPerSecondScaled
        )
    {
        return (
            _snapshotPrice,
            _snapshotTimestamp,
            _maxYearlyGrowthBps,
            _maxPriceGrowthPerSecondScaled
        );
    }

    /**
     * @dev Reverts if the sender is not the expected account.
     */
    function _checkSender() internal view virtual {
        require(
            msg.sender == SENDER,
            OraclePoolUnauthorizedAccount(msg.sender)
        );
    }

    /**
     * @dev Reads the latest oracle price, clips it to the current cap (`snapshot + perSecondGrowth * elapsed`),
     * and enforces monotonic increase against `_lastPrice`.
     * @return The clipped price used for the next swap (1e18 scale).
     */
    function _getLatestPrice() internal returns (uint256) {
        uint256 price = _oracle.getLatestAnswer();

        uint256 maxPrice = _snapshotPrice +
            (_maxPriceGrowthPerSecondScaled *
                (block.timestamp - _snapshotTimestamp)) /
            SCALING_FACTOR;
        if (price > maxPrice) price = maxPrice;

        uint256 lastPrice = _lastPrice;

        if (lastPrice != price) {
            require(
                price > lastPrice,
                OraclePoolInvalidPrice(price, lastPrice)
            );

            _lastPrice = price;
        }

        return price;
    }

    /**
     * @dev Sets the oracle contract. Can be set to the zero address to prevent the deposit and redeem functions
     * from being called. On first activation (no snapshot exists yet) the snapshot is seeded from the oracle's
     * current reading. On replacement (snapshot already exists) the snapshot is anchored to the current cap value,
     * so the growth budget already accrued isn't lost — admin can't pump the cap by deploying a new oracle with a
     * higher reading; any reading above the inherited cap is clipped until the cap re-accrues. `_lastPrice` is not
     * touched.
     *
     * Emits an {OracleUpdated} event. Also emits a {CapParametersUpdated} event when a snapshot is written.
     * @param oracle The address of the oracle contract.
     */
    function _setOracle(IOracle oracle) internal virtual {
        _oracle = oracle;

        if (address(oracle) != address(0)) {
            uint256 reading = oracle.getLatestAnswer();
            require(reading != 0, OraclePoolSnapshotPriceIsZero());

            uint256 newSnapshot;
            if (_snapshotPrice == 0) {
                newSnapshot = reading;
            } else {
                newSnapshot =
                    _snapshotPrice +
                    (_maxPriceGrowthPerSecondScaled *
                        (block.timestamp - _snapshotTimestamp)) /
                    SCALING_FACTOR;
            }

            _setSnapshot(newSnapshot, uint48(block.timestamp));
        }

        emit OracleUpdated(address(oracle));
    }

    /**
     * @dev Sets the fee to be applied to each swap (in 1e18 scale).
     */
    function _setFee(uint96 fee) internal virtual {
        require(fee <= PRECISION, OraclePoolFeeTooHigh());

        _fee = fee;

        emit FeeUpdated(fee);
    }

    /**
     * @dev Writes a new snapshot and recomputes the growth budget. Does NOT touch `_lastPrice`: callers that
     * want to unbrick a stuck-high monotonic invariant must reset it themselves.
     *
     * Emits a {CapParametersUpdated} event.
     * @param snapshotPrice The new snapshot price (1e18 scale).
     * @param snapshotTimestamp The new snapshot timestamp.
     */
    function _setSnapshot(
        uint256 snapshotPrice,
        uint48 snapshotTimestamp
    ) internal {
        _snapshotPrice = snapshotPrice;
        _snapshotTimestamp = snapshotTimestamp;
        _recomputeMaxGrowthPerSecond();

        emit CapParametersUpdated(
            snapshotPrice,
            snapshotTimestamp,
            _maxYearlyGrowthBps,
            _maxPriceGrowthPerSecondScaled
        );
    }

    /**
     * @dev Recomputes the per-second growth budget from the current `_snapshotPrice` and `_maxYearlyGrowthBps`.
     * The result is stored scaled by `SCALING_FACTOR` to preserve precision against a per-year-to-per-second division.
     */
    function _recomputeMaxGrowthPerSecond() internal {
        _maxPriceGrowthPerSecondScaled =
            (_snapshotPrice * _maxYearlyGrowthBps * SCALING_FACTOR) /
            BPS /
            SECONDS_PER_YEAR;
    }

    function _validateInputs(
        address recipient,
        uint256 exactAmountIn,
        address oracle
    ) internal pure {
        require(exactAmountIn > 0, OraclePoolZeroAmountIn());
        require(recipient != address(0), OraclePoolInvalidRecipient());
        require(oracle != address(0), OraclePoolOracleNotSet());
    }

    function _validateOutputs(
        address token,
        uint256 amountOut,
        uint256 minAmountOut
    ) internal view {
        require(
            amountOut >= minAmountOut,
            OraclePoolInsufficientAmountOut(amountOut, minAmountOut)
        );

        uint256 availableOut = IERC20(token).balanceOf(address(this));
        require(
            availableOut >= amountOut,
            OraclePoolInsufficientTokenOut(amountOut, availableOut)
        );
    }
}
