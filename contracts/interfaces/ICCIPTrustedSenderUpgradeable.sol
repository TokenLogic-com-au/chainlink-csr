// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import {ICCIPSenderUpgradeable} from "./ICCIPSenderUpgradeable.sol";

interface ICCIPTrustedSenderUpgradeable is ICCIPSenderUpgradeable {
    /// @dev No receiver has been set for the destination chain selector.
    /// @param destChainSelector The CCIP selector of the unsupported destination chain.
    error CCIPTrustedSenderUnsupportedChain(uint64 destChainSelector);

    /// @dev The list of token amounts is empty.
    error CCIPTrustedSenderZeroTokenAmounts();

    /// @dev One or more of the provided amounts is zero.
    error CCIPTrustedSenderZeroAmounts();

    /// @dev A provided address is the zero address.
    error CCIPTrustedSenderZeroAddress();

    /**
     * Emitted when the receiver for a destination chain selector is set.
     * @param destChainSelector The CCIP selector of the destination chain.
     * @param receiver The encoded receiver address on the destination chain.
     */
    event ReceiverSet(uint64 indexed destChainSelector, bytes receiver);

    /**
     * @notice Returns the receiver for the destination chain selector.
     * @param destChainSelector The CCIP selector of the destination chain.
     * @return The encoded receiver address on the destination chain, or empty bytes if none is set.
     */
    function getReceiver(uint64 destChainSelector) external view returns (bytes memory);

    /**
     * @dev Sets the receiver for the destination chain selector.
     * If the destination chain is an EVM chain, the receiver should be encoded using `abi.encode(address)`.
     *
     * Requirements:
     *
     * - `msg.sender` must have the `DEFAULT_ADMIN_ROLE`.
     *
     * Emits a {ReceiverSet} event.
     *
     * @param destChainSelector The CCIP selector of the destination chain.
     * @param receiver The encoded receiver address on the destination chain.
     */
    function setReceiver(uint64 destChainSelector, bytes memory receiver) external;
}
