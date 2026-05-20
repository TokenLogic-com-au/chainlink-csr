// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {IOracle} from "../interfaces/IOracle.sol";
import {IOraclePool} from "../interfaces/IOraclePool.sol";

/**
 * @title OraclePool Contract
 * @dev A contract that allows to swap `TOKEN_IN` for `TOKEN_OUT` using the exchange rate provided by an oracle.
 * This contract is not compatible with transfer tax tokens.
 * The `SENDER` account is the only account allowed to call the swap and pull functions.
 * It is expected that it takes care of rebalancing the tokens in the contract as this contract only allows to swap `TOKEN_IN` for `TOKEN_OUT`.
 */
contract OraclePool is Ownable, IOraclePool {
    using SafeERC20 for IERC20;

    address public immutable override SENDER;
    address public immutable override GHO;
    address public immutable override SGHO;

    uint256 private constant PRECISION = 1e18;

    IOracle private _oracle;
    uint96 private _fee;

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

        uint256 feeAmount = (exactAmountIn * _fee) / PRECISION;
        uint256 amountOut = ((exactAmountIn - feeAmount) * PRECISION) /
            _getLatestPrice();

        _validateOutputs(SGHO, amountOut, minAmountOut);

        IERC20(GHO).safeTransferFrom(msg.sender, address(this), exactAmountIn);
        IERC20(SGHO).safeTransfer(recipient, amountOut);

        emit Deposit(recipient, exactAmountIn, amountOut);

        return amountOut;
    }

    /**
     * @dev Swaps `amountIn` of `sGHO` for at least `minAmountOut` of `GHO` and sends them to `recipient`.
     * It uses the oracle to get the price of `SGHO` in `GHO`. A fee is applied to the amount of tokens to be swapped.
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

    /**
     * @dev Pulls `amount` of `token` from the contract and sends them to `msg.sender`.
     *
     * Requirements:
     *
     * - `token` must be equal to `TOKEN_IN`.
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
     * @dev Returns the address of the oracle contract.
     */
    function getOracle() public view virtual override returns (address) {
        return address(_oracle);
    }

    /**
     * @dev Returns the fee to be applied to each swap (in BPS).
     */
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
     * @dev Sets the oracle contract. Can be set to the zero address to prevent the swap function from being called.
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
