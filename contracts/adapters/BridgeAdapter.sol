// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import {FeeCodec} from "../libraries/FeeCodec.sol";
import {IBridgeAdapter} from "../interfaces/IBridgeAdapter.sol";

/**
 * @title BridgeAdapter Contract
 * @dev Abstract contract for bridge adapters.
 * Bridge adapters are contracts that are used to send tokens from one chain to another.
 * They are delegate called by the delegator contract to send tokens.
 * They must not use storage variables to prevent any storage collisions with the delegator contract.
 */
abstract contract BridgeAdapter is IBridgeAdapter {
    /// @dev The address of the delegator contract that is allowed to delegate call this adapter.
    address public immutable DELEGATOR;

    /**
     * @dev Modifier to check that the function is delegate called by the delegator contract.
     * Reverts with {BridgeAdapterOnlyDelegatedByDelegator} if the current context address is not the delegator.
     */
    modifier onlyDelegatedByDelegator() {
        if (address(this) != DELEGATOR) revert BridgeAdapterOnlyDelegatedByDelegator();
        _;
    }

    /**
     * @dev Initializes the contract with the delegator address.
     * @param delegator The address of the delegator contract.
     */
    constructor(address delegator) {
        if (delegator == address(0) || delegator == address(this)) revert BridgeAdapterInvalidParameters();

        DELEGATOR = delegator;
    }

    /// @inheritdoc IBridgeAdapter
    function sendToken(uint64 destChainSelector, address recipient, uint256 amount, bytes calldata feeData)
        external
        override
        onlyDelegatedByDelegator
    {
        _sendToken(destChainSelector, recipient, amount, feeData);
    }

    /**
     * @dev Internal function implemented by each concrete adapter to send `amount` of tokens to `recipient`
     * on the destination chain through the bridge-specific mechanism.
     * @param destChainSelector The selector of the destination chain.
     * @param recipient The address that will receive the tokens on the destination chain.
     * @param amount The amount of tokens to be sent.
     * @param feeData The encoded fee data used by the bridge.
     */
    function _sendToken(uint64 destChainSelector, address recipient, uint256 amount, bytes calldata feeData)
        internal
        virtual;
}
