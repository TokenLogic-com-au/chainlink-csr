// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import {SwapHandler} from "./SwapHandler.sol";
import {ISwapHandlerReferral, ISwapHandler} from "../interfaces/ISwapHandlerReferral.sol";

/**
 * @title SwapHandlerReferral Contract
 * @dev The contract extends the SwapHandler contract and adds referral functionality to the deposit function
 * by emitting a Referral event that can be used for tracking purposes off-chain.
 */
contract SwapHandlerReferral is SwapHandler, ISwapHandlerReferral {
    /**
     * @dev Sets the immutable values for {SGHO}, {GHO}, and the CCIP router and the initial values for
     * the oracle pool, the mainnet vault and the admin role.
     * @param sghoToken The address of the `SGHO` token on the deployed network.
     * @param ghoToken The address of the `GHO` token on the deployed network.
     * @param ccipRouter The address of the CCIP router.
     * @param oraclePool The address of the oracle pool.
     * @param vault The address of the mainnet vault.
     * @param initialAdmin The address granted the `DEFAULT_ADMIN_ROLE`.
     */
    constructor(
        address sghoToken,
        address ghoToken,
        address ccipRouter,
        address oraclePool,
        address vault,
        address initialAdmin
    )
        SwapHandler(
            sghoToken,
            ghoToken,
            ccipRouter,
            oraclePool,
            vault,
            initialAdmin
        )
    {}

    /// @inheritdoc ISwapHandlerReferral
    function depositReferral(
        uint256 exactAmountIn,
        uint256 minAmountOut,
        address referral
    ) public override returns (uint256 amountOut) {
        amountOut = SwapHandler.deposit(exactAmountIn, minAmountOut);
        emit Referral(msg.sender, referral, amountOut);
    }
}
