// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import {ICCIPBaseUpgradeable} from "./ICCIPBaseUpgradeable.sol";

interface ICCIPSenderUpgradeable is ICCIPBaseUpgradeable {
    error CCIPSenderEmptyReceiver();
    error CCIPSenderExceedsMaxFee(uint256 fee, uint256 maxFee);
    error CCIPSenderInvalidParameters();
    error CCIPSenderInvalidTokenAmount();
    error CCIPSenderInsufficientGas();

    function GHO_TOKEN() external view returns (address);

    function MIN_PROCESS_MESSAGE_GAS() external view returns (uint32);
}
