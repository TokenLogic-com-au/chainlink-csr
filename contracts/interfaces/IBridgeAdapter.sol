// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

interface IBridgeAdapter {
    /// @dev The function was not delegate called by the delegator contract.
    error BridgeAdapterOnlyDelegatedByDelegator();

    /// @dev One or more of the constructor parameters is invalid.
    error BridgeAdapterInvalidParameters();

    /**
     * Emitted when a message is sent from L1 to L2 through the Base bridge.
     */
    event BaseL1toL2MessageSent();

    /**
     * Emitted when a message is sent from L1 to L2 through the Optimism bridge.
     */
    event OptimismL1toL2MessageSent();

    /**
     * Emitted when a message is sent from L1 to L2 through the Frax Ferry bridge.
     */
    event FraxFerryL1toL2MessageSent();

    /**
     * Emitted when a message is sent from L1 to L2 through the Arbitrum bridge.
     * @param messageId The identifier of the message returned by the Arbitrum bridge.
     */
    event ArbitrumL1toL2MessageSent(bytes32 messageId);

    /**
     * Emitted when a message is sent through CCIP.
     * @param messageId The identifier of the message returned by the CCIP router.
     */
    event CCIPMessageSent(bytes32 messageId);

    /**
     * Emitted when a message is sent from L1 to L2 through the Linea bridge.
     */
    event LineaL1toL2MessageSent();

    /**
     * @dev Sends `amount` of tokens to `recipient` on the destination chain with `feeData`.
     * The function is meant to be delegate called by the delegator contract, which forwards the
     * tokens through the bridge implemented by the concrete adapter.
     *
     * Requirements:
     *
     * - The function must be delegate called by the delegator contract.
     *
     * Emits a bridge-specific message event (for example {ArbitrumL1toL2MessageSent} or {CCIPMessageSent}).
     *
     * @param destChainSelector The selector of the destination chain.
     * @param recipient The address that will receive the tokens on the destination chain.
     * @param amount The amount of tokens to be sent.
     * @param feeData The encoded fee data used by the bridge.
     */
    function sendToken(uint64 destChainSelector, address recipient, uint256 amount, bytes calldata feeData) external;
}
