// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import {CustomSender} from "./CustomSender.sol";
import {ICustomSenderReferral, ICustomSender} from "../interfaces/ICustomSenderReferral.sol";

/**
 * @title CustomSenderReferral Contract
 * @dev The contract extends the CustomSender contract and adds the referral functionality to the fastStake function
 * by emitting a Referral event that can be used for tracking purposes off-chain.
 */
contract CustomSenderReferral is CustomSender, ICustomSenderReferral {
    /**
     * @dev Sets the immutable values for {SGHO_TOKEN}, {GHO_TOKEN}, and {CCIP_ROUTER} and the initial values for
     * the oracle pool and the admin role.
     */
    constructor(
        address sghoToken,
        address ghoToken,
        address ccipRouter,
        address oraclePool,
        address vault,
        address initialAdmin
    )
        CustomSender(
            sghoToken,
            ghoToken,
            ccipRouter,
            oraclePool,
            vault,
            initialAdmin
        )
    {}

    /**
     * @dev Allows users to swap GHO for sGHO using an oracle pool, while emitting a {Referral} event
     * that can be used for tracking purposes off-chain.
     *
     * Requirements:
     *
     * - The amount sent must be greater than 0.
     * - The token sent must be GHO.
     *
     * Emits a {Deposit} and {Referral} event.
     */
    function depositReferral(
        uint256 exactAmountIn,
        uint256 minAmountOut,
        address referral
    ) public override returns (uint256 amountOut) {
        amountOut = CustomSender.deposit(exactAmountIn, minAmountOut);
        emit Referral(msg.sender, referral, amountOut);
    }
}
