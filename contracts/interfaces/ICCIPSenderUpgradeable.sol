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

    /**
     * @notice Returns the address of the GHO token used to pay CCIP fees.
     */
    function GHO_TOKEN() external view returns (address);
}
