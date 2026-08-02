// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";

interface ICCIPBaseUpgradeable is IERC165 {
    /// @dev The provided CCIP router address is the zero address.
    error CCIPBaseInvalidParameters();

    /**
     * @notice Returns the address of the CCIP router.
     */
    function CCIP_ROUTER() external view returns (address);
}
