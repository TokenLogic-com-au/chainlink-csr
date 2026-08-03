// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IWNative is IERC20 {
    /**
     * @dev Wraps the native token sent with the call into the wrapped ERC20 token.
     * Mints `msg.value` of the wrapped token to `msg.sender`.
     */
    function deposit() external payable;

    /**
     * @dev Unwraps the given amount of the wrapped ERC20 token back into the native token.
     * Burns the amount from `msg.sender` and sends the equivalent native token to `msg.sender`.
     *
     * Requirements:
     *
     * - `msg.sender` must hold at least the amount of the wrapped token to unwrap.
     *
     * @param amount The amount of the wrapped token to unwrap into the native token.
     */
    function withdraw(uint256 amount) external;
}
