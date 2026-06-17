// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

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

    /// @inheritdoc IOraclePool
    address public immutable SENDER;

    /// @inheritdoc IOraclePool
    address public immutable GHO;

    /// @inheritdoc IOraclePool
    address public immutable SGHO;

    /// @dev The precision used for fee calculations
    uint256 private constant PRECISION = 1e18;

    /// @dev The oracle that returns the latest exchange rate.
    IOracle private _oracle;

    /// @dev The current fee % (in 1e18 scale)
    uint96 private _fee;

    /// @dev The last price returned from the oracle.
    uint256 private _lastPrice;

    /**
     * @dev Modifier to check if the sender is the expected account.
     */
    modifier onlySender() {
        _checkSender();
        _;
    }

    /**
     * @dev Sets the immutable values for {SENDER}, {GHO}, {SGHO} and the initial values for the oracle, the swap fee and the owner.
     *
     * The `SENDER` account is the only account allowed to call the swap and pull functions.
     * The `GHO` and `SGHO` addresses are the addresses of the tokens to be swapped.
     * The `oracle` address is the address of the oracle contract.
     * The `fee` is the fee to be applied to each swap (in 1e18 scale).
     * The `initialOwner` is the address of the initial owner.
     */
    constructor(
        address sender,
        address gho,
        address sgho,
        address oracle,
        uint96 fee,
        address initialOwner
    ) Ownable(initialOwner) {
        require(
            sender != address(0) && gho != address(0) && sgho != address(0),
            OraclePoolInvalidParameters()
        );

        SENDER = sender;
        GHO = gho;
        SGHO = sgho;

        _setOracle(IOracle(oracle));
        _setFee(fee);
    }

    /// @inheritdoc IOraclePool
    function deposit(
        address recipient,
        uint256 exactAmountIn,
        uint256 minAmountOut
    ) public virtual override onlySender returns (uint256) {
        _validateInputs(recipient, exactAmountIn, address(_oracle));

        uint256 feeAmount = (exactAmountIn * _fee) / PRECISION;
        uint256 amountOut = ((exactAmountIn - feeAmount) * PRECISION) /
            _getLatestPrice();

        _validateOutputs(SGHO, amountOut, minAmountOut);

        IERC20(GHO).safeTransferFrom(msg.sender, address(this), exactAmountIn);
        IERC20(SGHO).safeTransfer(recipient, amountOut);

        emit Deposit(recipient, exactAmountIn, amountOut);

        return amountOut;
    }

    /// @inheritdoc IOraclePool
    function redeem(
        address recipient,
        uint256 exactAmountIn,
        uint256 minAmountOut
    ) public virtual override onlySender returns (uint256) {
        _validateInputs(recipient, exactAmountIn, address(_oracle));

        uint256 exchangeRateAmount = (exactAmountIn * _getLatestPrice()) /
            PRECISION;
        uint256 feeAmount = (exchangeRateAmount * _fee) / PRECISION;
        uint256 amountOut = exchangeRateAmount - feeAmount;

        _validateOutputs(GHO, amountOut, minAmountOut);

        IERC20(SGHO).safeTransferFrom(msg.sender, address(this), exactAmountIn);
        IERC20(GHO).safeTransfer(recipient, amountOut);

        emit Redeem(recipient, exactAmountIn, amountOut);

        return amountOut;
    }

    /// @inheritdoc IOraclePool
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

    /// @inheritdoc IOraclePool
    function sweep(
        address token,
        address recipient,
        uint256 amount
    ) public virtual override onlyOwner {
        IERC20(token).safeTransfer(recipient, amount);

        emit Sweep(token, recipient, amount);
    }

    /// @inheritdoc IOraclePool
    function setOracle(address oracle) public virtual override onlyOwner {
        _setOracle(IOracle(oracle));
    }

    /// @inheritdoc IOraclePool
    function setFee(uint96 fee) public virtual override onlyOwner {
        _setFee(fee);
    }

    /// @inheritdoc IOraclePool
    function getOracle() public view virtual override returns (address) {
        return address(_oracle);
    }

    /// @inheritdoc IOraclePool
    function getFee() public view virtual override returns (uint96) {
        return _fee;
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
     * @dev Returns the latest oracle price.
     */
    function _getLatestPrice() internal returns (uint256) {
        uint256 price = _oracle.getLatestAnswer();
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
     * @dev Sets the oracle contract. Can be set to the zero address to prevent the deposit and redeem functions from being called.
     */
    function _setOracle(IOracle oracle) internal virtual {
        _oracle = oracle;

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
     * @dev Validates the inputs passed for a token swap.
     * @param recipient The address to receive the swapped tokens.
     * @param exactAmountIn The exact amount in that caller is swapping.
     * @param oracle The address of the oracle contract to check the price.
     */
    function _validateInputs(
        address recipient,
        uint256 exactAmountIn,
        address oracle
    ) internal pure {
        require(exactAmountIn > 0, OraclePoolZeroAmountIn());
        require(recipient != address(0), OraclePoolInvalidRecipient());
        require(oracle != address(0), OraclePoolOracleNotSet());
    }

    /**
     * @dev Validates the outputs of the swaps.
     * @param token The address of the token to swap to.
     * @param amountOut The amount out that the pool is returning.
     * @param minAmountOut The minimum amount out expected by the caller.
     */
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
