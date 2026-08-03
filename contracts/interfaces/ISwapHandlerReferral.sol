// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import {ISwapHandler} from "./ISwapHandler.sol";

interface ISwapHandlerReferral is ISwapHandler {
    /**
     * Emitted when a deposit is performed with a referral attached, for off-chain tracking purposes.
     * @param user The address of the user that performed the deposit.
     * @param referral The address of the referral associated with the deposit.
     * @param amountOut The amount of `SGHO` received by the user.
     */
    event Referral(
        address indexed user,
        address indexed referral,
        uint256 amountOut
    );

    /**
     * @dev Swaps `amount` of `GHO` for at least `minAmountOut` of `SGHO` using the oracle pool, while emitting
     * a {Referral} event that can be used for off-chain tracking. Behaves like {ISwapHandler-deposit}.
     *
     * Requirements:
     *
     * - `amount` must be greater than 0.
     * - The oracle pool must be set.
     * - `msg.sender` must have approved this contract to spend at least `amount` of `GHO`.
     *
     * Emits a {Deposit} and a {Referral} event.
     *
     * @param amount The exact amount of `GHO` to be swapped.
     * @param minAmountOut The minimum amount of `SGHO` to be received.
     * @param referral The address of the referral to associate with the deposit.
     * @return amountOut The amount of `SGHO` received by the user.
     */
    function depositReferral(
        uint256 amount,
        uint256 minAmountOut,
        address referral
    ) external returns (uint256 amountOut);
}
