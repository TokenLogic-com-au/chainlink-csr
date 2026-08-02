// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import {ICCIPBaseUpgradeable} from "./ICCIPBaseUpgradeable.sol";

interface ICCIPSenderUpgradeable is ICCIPBaseUpgradeable {
    /// @dev The receiver of the message is empty.
    error CCIPSenderEmptyReceiver();

    /// @dev A token amount in the message has a zero amount or a zero token address.
    error CCIPSenderInvalidTokenAmount();

    /// @dev The fee required for the message exceeds the maximum fee allowed by the caller.
    /// @param fee The fee required for the message.
    /// @param maxFee The maximum fee allowed by the caller.
    error CCIPSenderExceedsMaxFee(uint256 fee, uint256 maxFee);

    /// @dev The provided GHO token address is the zero address.
    error CCIPSenderInvalidParameters();

    error CCIPSenderInsufficientGas();

    /// @dev The gas limit passed to `setMinProcessMessageGas` is zero, which would disable the guard.
    error CCIPSenderInvalidGasLimit();

    /// @dev The first 4 bytes of `extraArgs` do not match `ExtraArgsCodec.GENERIC_EXTRA_ARGS_V3_TAG`.
    /// @param tag The rejected 4-byte tag actually found at the start of `extraArgs`.
    error CCIPSenderInvalidExtraArgsTag(bytes4 tag);

    /**
     * Emitted when the minimum gas required to process the message on the destination chain is updated.
     * @param oldGasLimit The previous minimum gas limit.
     * @param newGasLimit The new minimum gas limit.
     */
    event MinProcessMessageGasSet(uint32 oldGasLimit, uint32 newGasLimit);

    /**
     * @notice Returns the address of the GHO token used to pay CCIP fees.
     */
    function GHO_TOKEN() external view returns (address);

    function minProcessMessageGas() external view returns (uint32);

    function setMinProcessMessageGas(uint32 gasLimit) external;
}
