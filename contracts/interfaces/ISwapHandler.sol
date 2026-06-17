// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import {ICCIPTrustedSenderUpgradeable} from "./ICCIPTrustedSenderUpgradeable.sol";

interface ISwapHandler is ICCIPTrustedSenderUpgradeable {
    /// @dev The token provided is neither `GHO` nor `SGHO`.
    error SwapHandlerInvalidToken();

    /// @dev The oracle pool has not been set.
    error SwapHandlerOraclePoolNotSet();

    /// @dev A required address parameter is the zero address.
    error SwapHandlerZeroAddress();

    /// @dev The amount provided is zero.
    error SwapHandlerZeroAmount();

    /// @dev One or more of the constructor parameters is invalid.
    error SwapHandlerInvalidParameters();

    /// @dev The gas limit encoded in the fee data is below `MIN_PROCESS_MESSAGE_GAS`.
    error SwapHandlerInsufficientGas();

    /**
     * Emitted when the oracle pool is updated.
     * @param oldOracle The address of the previous oracle pool.
     * @param oraclePool The address of the new oracle pool.
     */
    event OraclePoolSet(address oldOracle, address oraclePool);

    /**
     * Emitted when a user swaps `GHO` for `SGHO` through the oracle pool.
     * @param user The address of the user that performed the deposit.
     * @param token The address of the token sent in (`GHO`).
     * @param amountIn The amount of `GHO` swapped in.
     * @param amountOut The amount of `SGHO` received.
     */
    event Deposit(
        address indexed user,
        address indexed token,
        uint256 amountIn,
        uint256 amountOut
    );

    /**
     * Emitted when a user swaps `SGHO` for `GHO` through the oracle pool.
     * @param user The address of the user that performed the redeem.
     * @param token The address of the token sent in (`SGHO`).
     * @param amountIn The amount of `SGHO` swapped in.
     * @param amountOut The amount of `GHO` received.
     */
    event Redeem(
        address indexed user,
        address indexed token,
        uint256 amountIn,
        uint256 amountOut
    );

    /**
     * Emitted when the oracle pool is rebalanced by sending tokens to the mainnet vault via CCIP.
     * @param user The address of the operator that triggered the sync.
     * @param destChainSelector The CCIP chain selector of the destination chain.
     * @param messageId The identifier of the CCIP message sent.
     * @param token The address of the token sent (`GHO` or `SGHO`).
     * @param amount The amount of `token` sent.
     */
    event Sync(
        address indexed user,
        uint64 indexed destChainSelector,
        bytes32 messageId,
        address token,
        uint256 amount
    );

    /**
     * Emitted when the mainnet vault is updated.
     * @param vault The address of the new mainnet vault.
     */
    event VaultSet(address vault);

    /**
     * @dev Swaps `exactAmountIn` of `GHO` for at least `minAmountOut` of `SGHO` using the oracle pool.
     * The user's `GHO` is pulled into this contract, forwarded to the oracle pool, and the resulting
     * `SGHO` is sent directly to the user.
     *
     * Requirements:
     *
     * - `exactAmountIn` must be greater than 0.
     * - The oracle pool must be set.
     * - `msg.sender` must have approved this contract to spend at least `exactAmountIn` of `GHO`.
     *
     * Emits a {Deposit} event.
     *
     * @param exactAmountIn The exact amount of `GHO` to be swapped.
     * @param minAmountOut The minimum amount of `SGHO` to be received.
     * @return The amount of `SGHO` received by the user.
     */
    function deposit(
        uint256 exactAmountIn,
        uint256 minAmountOut
    ) external returns (uint256);

    /**
     * @dev Swaps `amount` of `SGHO` for at least `minAmountOut` of `GHO` using the oracle pool.
     * The user's `SGHO` is pulled into this contract, forwarded to the oracle pool, and the resulting
     * `GHO` is sent directly to the user.
     *
     * Requirements:
     *
     * - `amount` must be greater than 0.
     * - The oracle pool must be set.
     * - `msg.sender` must have approved this contract to spend at least `amount` of `SGHO`.
     *
     * Emits a {Redeem} event.
     *
     * @param amount The exact amount of `SGHO` to be swapped.
     * @param minAmountOut The minimum amount of `GHO` to be received.
     * @return The amount of `GHO` received by the user.
     */
    function redeem(
        uint256 amount,
        uint256 minAmountOut
    ) external returns (uint256);

    /**
     * @dev Rebalances the oracle pool by pulling `amount` of `token` from it and sending the tokens to
     * the mainnet vault via CCIP. The CCIP fee is paid by `msg.sender` and, as encoded in `feeData`, can
     * be paid in `GHO` or in native token. Any excess native value sent with the call is refunded to `msg.sender`.
     *
     * Requirements:
     *
     * - `msg.sender` must have the `SYNC_ROLE`.
     * - `amount` must be greater than 0.
     * - `token` must be either `GHO` or `SGHO`.
     * - The oracle pool must be set.
     * - The gas limit encoded in `feeData` must be at least `MIN_PROCESS_MESSAGE_GAS`.
     *
     * Emits a {Sync} event.
     *
     * @param token The address of the token to be pulled and sent (`GHO` or `SGHO`).
     * @param amount The amount of `token` to be pulled and sent.
     * @param minAmountOut The minimum amount expected on the destination chain.
     * @param feeData The encoded CCIP fee data (max fee, fee payment token, and gas limit).
     * @param extraArgs The extra arguments forwarded to the CCIP router.
     * @return The identifier of the CCIP message sent.
     */
    function sync(
        address token,
        uint256 amount,
        uint256 minAmountOut,
        bytes calldata feeData,
        bytes calldata extraArgs
    ) external payable returns (bytes32);

    /**
     * @dev Sets the address of the oracle pool.
     * It approves the maximum amount of `GHO` and `SGHO` to the new oracle pool and revokes the
     * approvals from the previous oracle pool.
     *
     * Requirements:
     *
     * - `msg.sender` must have the `DEFAULT_ADMIN_ROLE`.
     *
     * Emits an {OraclePoolSet} event.
     *
     * @param oraclePool The address of the new oracle pool.
     */
    function setOraclePool(address oraclePool) external;

    /**
     * @dev Sets the address of the mainnet vault.
     *
     * Requirements:
     *
     * - `msg.sender` must have the `DEFAULT_ADMIN_ROLE`.
     * - `vault` must not be the zero address.
     *
     * Emits a {VaultSet} event.
     *
     * @param vault The address of the new mainnet vault.
     */
    function setVault(address vault) external;

    /**
     * @notice Returns the address of the `GHO` token on the deployed network.
     */
    function GHO() external view returns (address);

    /**
     * @notice Returns the address of the `SGHO` token on the deployed network.
     */
    function SGHO() external view returns (address);

    /**
     * @notice Returns the role required to call {sync}.
     */
    function SYNC_ROLE() external view returns (bytes32);

    /**
     * @notice Returns the minimum gas required to process the CCIP message on the destination chain.
     */
    function MIN_PROCESS_MESSAGE_GAS() external view returns (uint32);

    /**
     * @notice Returns the address of the oracle pool.
     */
    function getOraclePool() external view returns (address);

    /**
     * @notice Returns the address of the mainnet vault.
     */
    function getVault() external view returns (address);
}
