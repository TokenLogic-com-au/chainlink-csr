// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";

import {IOraclePool} from "../interfaces/IOraclePool.sol";
import {OraclePool} from "./OraclePool.sol";

/**
 * @title PausableOraclePool Contract
 * @dev An OraclePool contract that is pausable.
 * The owner can pause and unpause the contract, which will prevent the `deposit`,
 * `redeem`, and `pull` functions from being called.
 */
contract PausableOraclePool is OraclePool, Pausable {
    /// @dev One or more of the constructor parameters is invalid (e.g. the oracle is the zero address).
    error PausableOraclePoolInvalidParameters();

    /**
     * @dev Sets the immutable values for {SENDER}, {GHO}, {SGHO} and the initial values for the oracle, the swap fee,
     * the owner, and the maximum yearly growth of the price cap.
     * @param sender The address allowed to call the swap and pull functions.
     * @param gho The address of the GHO token.
     * @param sgho The address of the sGHO token.
     * @param oracle The address of the oracle contract. Must be non-zero.
     * @param fee The fee to be applied to each swap (in 1e18 scale).
     * @param initialOwner The address of the initial owner.
     * @param maxYearlyGrowthBps The maximum yearly growth of the price cap (in basis points).
     */
    constructor(
        address sender,
        address gho,
        address sgho,
        address oracle,
        uint96 fee,
        address initialOwner,
        uint16 maxYearlyGrowthBps
    )
        OraclePool(
            sender,
            gho,
            sgho,
            oracle,
            fee,
            initialOwner,
            maxYearlyGrowthBps
        )
    {
        require(oracle != address(0), PausableOraclePoolInvalidParameters());
    }

    /// @inheritdoc IOraclePool
    /// @dev Reverts if the contract is paused.
    function deposit(
        address recipient,
        uint256 exactAmountIn,
        uint256 minAmountOut
    ) public override whenNotPaused returns (uint256) {
        return super.deposit(recipient, exactAmountIn, minAmountOut);
    }

    /// @inheritdoc IOraclePool
    /// @dev Reverts if the contract is paused.
    function redeem(
        address recipient,
        uint256 exactAmountIn,
        uint256 minAmountOut
    ) public override whenNotPaused returns (uint256) {
        return super.redeem(recipient, exactAmountIn, minAmountOut);
    }

    /// @inheritdoc IOraclePool
    /// @dev Reverts if the contract is paused.
    function pull(address token, uint256 amount) public override whenNotPaused {
        super.pull(token, amount);
    }

    /**
     * @dev Pauses the contract, preventing the `deposit`, `redeem` and `pull` functions from being called.
     * Only callable by the owner when the contract is not already paused.
     *
     * Emits a {Paused} event.
     */
    function pause() public onlyOwner whenNotPaused {
        _pause();
    }

    /**
     * @dev Unpauses the contract, re-enabling the `deposit`, `redeem` and `pull` functions.
     * Only callable by the owner when the contract is paused.
     *
     * Emits an {Unpaused} event.
     */
    function unpause() public onlyOwner whenPaused {
        _unpause();
    }
}
