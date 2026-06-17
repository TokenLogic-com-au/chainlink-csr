// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

interface IOraclePool {
    /// @dev Invalid caller.
    /// @param sender The address that attempted the unauthorized call.
    error OraclePoolUnauthorizedAccount(address sender);

    /// @dev The amount of token out to be sent exceeds the contract's balance.
    /// @param amountOut The amount of token out requested.
    /// @param availableOut The amount of token out available in the contract.
    error OraclePoolInsufficientTokenOut(
        uint256 amountOut,
        uint256 availableOut
    );

    /// @dev The amount of `token` to be pulled exceeds the contract's balance.
    /// @param token The address of the token being pulled.
    /// @param amountOut The amount of `token` requested.
    /// @param availableOut The amount of `token` available in the contract.
    error OraclePoolInsufficientToken(
        address token,
        uint256 amountOut,
        uint256 availableOut
    );

    /// @dev The amount out resulting from the swap is below the caller's minimum.
    /// @param amountOut The amount out resulting from the swap.
    /// @param minAmountOut The minimum amount out expected by the caller.
    error OraclePoolInsufficientAmountOut(
        uint256 amountOut,
        uint256 minAmountOut
    );

    /// @dev The recipient is the zero address.
    error OraclePoolInvalidRecipient();

    /// @dev The token cannot be pulled because it is neither `GHO` nor `sGHO`.
    /// @param token The address of the token that was attempted to be pulled.
    error OraclePoolPullNotAllowed(address token);

    /// @dev The oracle has not been set.
    error OraclePoolOracleNotSet();

    /// @dev The fee exceeds the maximum allowed value (1e18).
    error OraclePoolFeeTooHigh();

    /// @dev The amount in is zero.
    error OraclePoolZeroAmountIn();

    /// @dev One or more of the constructor parameters is invalid.
    error OraclePoolInvalidParameters();

    /// @dev The oracle returned a price lower than the last recorded price.
    /// @param price The price returned by the oracle.
    /// @param lastPrice The last recorded price.
    error OraclePoolInvalidPrice(uint256 price, uint256 lastPrice);

    /**
     * Emitted when a deposit transaction is executed.
     * @param recipient The address that is receiving the tokens.
     * @param amountIn The amount in of the GHO token.
     * @param amountOut The amount out of the sGHO token.
     */
    event Deposit(address recipient, uint256 amountIn, uint256 amountOut);

    /**
     * Emitted when a redeem transaction is executed.
     * @param recipient The address that is receiving the tokens.
     * @param amountIn The amount in of the sGHO token.
     * @param amountOut The amount out of the GHO token.
     */
    event Redeem(address recipient, uint256 amountIn, uint256 amountOut);

    /**
     * Emitted when tokens are pulled from the contract.
     * @param token The address of the token that was pulled.
     * @param recipient The address that is receiving the tokens.
     * @param amount The amount of `token` that was pulled.
     */
    event Pull(address token, address recipient, uint256 amount);

    /**
     * Emitted when tokens are swept from the contract.
     * @param token The address of the token that was swept.
     * @param recipient The address that is receiving the tokens.
     * @param amount The amount of `token` that was swept.
     */
    event Sweep(address token, address recipient, uint256 amount);

    /**
     * Emitted when the oracle contract is updated.
     * @param oracle The address of the new oracle contract.
     */
    event OracleUpdated(address oracle);

    /**
     * Emitted when the swap fee is updated.
     * @param fee The new fee % to be applied to each swap (in 1e18 scale).
     */
    event FeeUpdated(uint96 fee);

    /**
     * @dev Swaps `amountIn` of `GHO` for at least `minAmountOut` of `sGHO` and sends them to `recipient`.
     * It uses the oracle to get the price of `sGHO` in `GHO`. A fee can be applied to the amount of tokens to be swapped.
     * The fee is kept in this contract and can be used to pay for the gas price and the potential exchange rate deviation when the
     * `GHO` is exchanged for `sGHO` by the sender.
     *
     * Requirements:
     *
     * - `msg.sender` must be the `SENDER` account.
     * - `oracle` must be set.
     * - The amount of `sGHO` to be received must be greater than or equal to `minAmountOut`.
     * - The amount of `sGHO` available in the contract must be greater than or equal to the amount of `sGHO` to be received.
     * - The `msg.sender` must have approved the contract to spend at least `amountIn` of `GHO`.
     *
     * Emits a {Deposit} event.
     *
     * @param recipient The address that will receive the `sGHO` tokens.
     * @param exactAmountIn The exact amount of `GHO` to be swapped.
     * @param minAmountOut The minimum amount of `sGHO` to be received.
     * @return The amount of `sGHO` sent to `recipient`.
     */
    function deposit(
        address recipient,
        uint256 exactAmountIn,
        uint256 minAmountOut
    ) external returns (uint256);

    /**
     * @dev Swaps `amountIn` of `sGHO` for at least `minAmountOut` of `GHO` and sends them to `recipient`.
     * It uses the oracle to get the price of `sGHO` in `GHO`. A fee can be applied to the amount of tokens to be swapped.
     * The fee is kept in this contract and can be used to pay for the gas price and the potential exchange rate deviation when the
     * `sGHO` is exchanged for `GHO` by the sender.
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
     *
     * @param recipient The address that will receive the `GHO` tokens.
     * @param amountIn The exact amount of `sGHO` to be swapped.
     * @param minAmountOut The minimum amount of `GHO` to be received.
     * @return The amount of `GHO` sent to `recipient`.
     */
    function redeem(
        address recipient,
        uint256 amountIn,
        uint256 minAmountOut
    ) external returns (uint256);

    /**
     * @dev Pulls `amount` of `token` from the contract and sends them to `msg.sender`.
     *
     * Requirements:
     *
     * - `msg.sender` must be the `SENDER` account.
     * - `token` must be equal one of `GHO` or `sGHO`.
     * - The `amount` of `token` to be pulled must be less than or equal to the amount of `token` available in the contract.
     *
     * Emits a {Pull} event.
     *
     * @param token The address of the token to be pulled (`GHO` or `sGHO`).
     * @param amount The amount of `token` to be pulled.
     */
    function pull(address token, uint256 amount) external;

    /**
     * @dev Sweeps `amount` of `token` from the contract and sends them to `recipient`.
     *
     * Requirements:
     *
     * - `msg.sender` must be the owner.
     *
     * Emits a {Sweep} event.
     *
     * @param token The address of the token to be swept.
     * @param recipient The address that will receive the tokens.
     * @param amount The amount of `token` to be swept.
     */
    function sweep(address token, address recipient, uint256 amount) external;

    /**
     * @dev Sets the oracle contract address.
     *
     * Emits an {OracleUpdated} event.
     *
     * @param oracle Address of the oracle contract.
     */
    function setOracle(address oracle) external;

    /**
     * @dev Sets the fee % to be applied to each swap (in 1e18 scale).
     *
     * Requirements:
     *
     * - `fee` must be less than or equal to 1e18.
     *
     * Emits a {FeeUpdated} event.
     *
     * @param fee The new fee % to be applied to each swap (in 1e18 scale).
     */
    function setFee(uint96 fee) external;

    /**
     * @notice Returns the address of the SENDER contract set.
     */
    function SENDER() external view returns (address);

    /**
     * @notice Returns the address of the GHO token on the deployed network.
     */
    function GHO() external view returns (address);

    /**
     * @notice Returns the address of the sGHO token on the deployed network.
     */
    function SGHO() external view returns (address);

    /**
     * @notice Returns the address of the oracle contract.
     */
    function getOracle() external view returns (address);

    /**
     * @notice Returns the fee % to be applied to each swap (in 1e18 scale).
     */
    function getFee() external view returns (uint96);
}
