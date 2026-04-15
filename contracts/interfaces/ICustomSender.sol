// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import {ICCIPTrustedSenderUpgradeable} from "./ICCIPTrustedSenderUpgradeable.sol";

interface ICustomSender is ICCIPTrustedSenderUpgradeable {
    error CustomSenderInvalidToken();
    error CustomSenderOraclePoolNotSet();
    error CustomSenderZeroAmount();
    error CustomSenderInvalidParameters();
    error CustomSenderInsufficientGas();

    event OraclePoolSet(address oraclePool);
    event FastStake(
        address indexed user,
        address indexed token,
        uint256 amountIn,
        uint256 amountOut
    );
    event Sync(
        address indexed user,
        uint64 indexed destChainSelector,
        bytes32 messageId,
        uint256 amount
    );
    event VaultSet(address vault);

    function TOKEN() external view returns (address);

    function SYNC_ROLE() external view returns (bytes32);

    function MIN_PROCESS_MESSAGE_GAS() external view returns (uint32);

    function getOraclePool() external view returns (address);

    function setOraclePool(address oraclePool) external;

    function getVault() external view returns (address);

    function setVault(address vault) external;

    function fastStake(
        address token,
        uint256 amount,
        uint256 minAmountOut
    ) external returns (uint256 amountOut);

    function sync(
        uint64 destChainSelector,
        uint256 amount,
        bytes calldata feeOtoD
    ) external returns (bytes32 messageId);
}
