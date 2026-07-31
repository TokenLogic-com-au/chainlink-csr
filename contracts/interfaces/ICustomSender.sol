// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import {ICCIPTrustedSenderUpgradeable} from "./ICCIPTrustedSenderUpgradeable.sol";

interface ICustomSender is ICCIPTrustedSenderUpgradeable {
    error CustomSenderInvalidToken();
    error CustomSenderOraclePoolNotSet();
    error CustomSenderZeroAddress();
    error CustomSenderZeroAmount();
    error CustomSenderInvalidParameters();

    event OraclePoolSet(address oldOracle, address oraclePool);

    /**
     * Emitted when the oracle pool is refunded from the SwapHandler.
     * @param oraclePool The address of oracle pool where the token was transferred.
     * @param token The address of the token that was transferred.
     * @param amount The amount of token that was transferred.
     */
    event OraclePoolRefunded(address oraclePool, address token, uint256 amount);
    event Deposit(
        address indexed user,
        address indexed token,
        uint256 amountIn,
        uint256 amountOut
    );
    event Redeem(
        address indexed user,
        address indexed token,
        uint256 amountIn,
        uint256 amountOut
    );
    event Sync(
        address indexed user,
        uint64 indexed destChainSelector,
        bytes32 messageId,
        address token,
        uint256 amount
    );
    event VaultSet(address vault);

    function deposit(
        uint256 exactAmountIn,
        uint256 minAmountOut
    ) external returns (uint256);

    function redeem(
        uint256 amount,
        uint256 minAmountOut
    ) external returns (uint256);

    function sync(
        address token,
        uint256 amount,
        uint256 minAmountOut,
        bytes calldata feeData,
        bytes calldata extraArgs
    ) external payable returns (bytes32);

    /**
     * @dev Reimburses the OraclePool in case of a failed L2 <> L1 Sync of `GHO` or `SGHO`.
     * The initiator of the `sync` is the one refunded in case of failure, which would be this
     * contract and the token needs to be manually refunded to the OraclePool.
     *
     * Requirements:
     *
     * - `msg.sender` must have the `DEFAULT_ADMIN_ROLE`.
     * - `amount` must be greater than 0.
     * - `token` must be either `GHO` or `SGHO`.
     * - The oracle pool must be set.
     *
     * Emits a {Sync} event.
     *
     * @param token The address of the token to be transferred (`GHO` or `SGHO`).
     * @param amount The amount of `token` to be transferred.
     */
    function refundOraclePool(address token, uint256 amount) external;

    function setOraclePool(address oraclePool) external;

    function setVault(address vault) external;

    function GHO() external view returns (address);

    function SGHO() external view returns (address);

    function SYNC_ROLE() external view returns (bytes32);

    function getOraclePool() external view returns (address);

    function getVault() external view returns (address);
}
