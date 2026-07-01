// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import {ICCIPBaseUpgradeable} from "./ICCIPBaseUpgradeable.sol";

interface ICCIPSenderUpgradeable is ICCIPBaseUpgradeable {
    error CCIPSenderEmptyReceiver();
    error CCIPSenderExceedsMaxFee(uint256 fee, uint256 maxFee);
    error CCIPSenderInvalidParameters();
    error CCIPSenderInvalidTokenAmount();
    error CCIPSenderInsufficientGas();

    /// @dev The gas limit passed to `setMinProcessMessageGas` is zero, which would disable the guard.
    error CCIPSenderInvalidGasLimit();

    /**
     * Emitted when the minimum gas required to process the message on the destination chain is updated.
     * @param oldGasLimit The previous minimum gas limit.
     * @param newGasLimit The new minimum gas limit.
     */
    event MinProcessMessageGasSet(uint32 oldGasLimit, uint32 newGasLimit);

    function GHO_TOKEN() external view returns (address);

    function minProcessMessageGas() external view returns (uint32);

    function setMinProcessMessageGas(uint32 gasLimit) external;
}
