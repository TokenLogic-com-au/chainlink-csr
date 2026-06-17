// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title TokenHelper Library
 * @dev A library for handling token transfers and native transfers.
 */
library TokenHelper {
    /// @dev Error thrown when a native token transfer fails.
    error TokenHelperNativeTransferFailed();

    /**
     * @dev Transfers `amount` of `token` to `to`.
     * If `amount` is zero, it does nothing.
     * If `token` is the zero address, it transfers `amount` of native tokens to `to` instead.
     * @param token The address of the token to transfer, or the zero address for the native token.
     * @param to The address to receive the tokens.
     * @param amount The amount of tokens to transfer.
     */
    function transfer(address token, address to, uint256 amount) internal {
        if (amount == 0) return;

        if (token == address(0)) {
            transferNative(to, amount);
        } else {
            SafeERC20.safeTransfer(IERC20(token), to, amount);
        }
    }

    /**
     * @dev Refunds the entire native token balance held by the contract to `to`, but only when the
     * current call carried native value (`msg.value` > 0).
     * This function should only be used in a contract that is not expected to hold any native tokens
     * after the call has been executed.
     * @param to The address to receive the refunded native tokens.
     */
    function refundExcessNative(address to) internal {
        if (msg.value > 0) {
            uint256 balance = address(this).balance;
            if (balance > 0) transferNative(to, balance);
        }
    }

    /**
     * @dev Transfers `amount` of native tokens to `to` via a low-level call.
     * If `amount` is zero, it does nothing.
     *
     * Requirements:
     *
     * - The native token transfer must not fail, otherwise it reverts with {TokenHelperNativeTransferFailed}.
     *
     * @param to The address to receive the native tokens.
     * @param amount The amount of native tokens to transfer.
     */
    function transferNative(address to, uint256 amount) internal {
        if (amount == 0) return;

        (bool success,) = to.call{value: amount}(new bytes(0));
        if (!success) revert TokenHelperNativeTransferFailed();
    }
}
