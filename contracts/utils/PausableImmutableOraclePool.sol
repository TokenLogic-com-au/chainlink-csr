// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";

import {IOraclePool} from "../interfaces/IOraclePool.sol";
import {OraclePool} from "./OraclePool.sol";

/**
 * @title PausableImmutableOraclePool Contract
 * @dev An OraclePool contract that is pausable and immutable.
 * The oracle and the fee cannot be changed after deployment.
 * The owner can pause and unpause the contract, which will prevent the `deposit`,
 * `redeem`, and `pull` functions from being called.
 */
contract PausableImmutableOraclePool is OraclePool, Pausable {
    /// @dev The oracle or fee cannot be changed because they are immutable in this contract.
    error PausableImmutableOraclePoolImmutable();

    /// @dev One or more of the constructor parameters is invalid (e.g. the oracle is the zero address).
    error PausableImmutableOraclePoolInvalidParameters();

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
        require(
            oracle != address(0),
            PausableImmutableOraclePoolInvalidParameters()
        );
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

    /// @inheritdoc IOraclePool
    /// @dev Always reverts: the oracle is immutable in this contract.
    function setOracle(address) public pure override {
        revert PausableImmutableOraclePoolImmutable();
    }

    /// @inheritdoc IOraclePool
    /// @dev Always reverts: the fee is immutable in this contract.
    function setFee(uint96) public pure override {
        revert PausableImmutableOraclePoolImmutable();
    }

    /**
     * @dev Prevents the price-cap parameters from being changed.
     */
    function setCapParameters(uint256, uint48, uint16) public pure override {
        revert PausableImmutableOraclePoolImmutable();
    }

    /**
     * @dev Prevents the maximum yearly growth bps from being changed.
     */
    function setMaxYearlyGrowthBps(uint16) public pure override {
        revert PausableImmutableOraclePoolImmutable();
    }
}
