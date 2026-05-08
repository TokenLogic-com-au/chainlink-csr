// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";

import {OraclePool} from "./OraclePool.sol";

/**
 * @title PausableImmutableOraclePool Contract
 * @dev An OraclePool contract that is pausable and immutable.
 * The oracle and the fee cannot be changed after deployment.
 * The owner can pause and unpause the contract, which will prevent the `swap` and
 * `pull` functions from being called.
 */
contract PausableImmutableOraclePool is OraclePool, Pausable {
    error PausableImmutableOraclePoolImmutable();
    error PausableImmutableOraclePoolInvalidParameters();

    /**
     * @dev Sets the immutable values for {SENDER}, {GHO}, {SGHO} and the initial values for the oracle, the swap fee and the owner.
     *
     * The `SENDER` account is the only account allowed to call the swap and pull functions.
     * The `GHO` and `SGHO` addresses are the addresses of the tokens to be swapped.
     * The `oracle` address is the address of the oracle contract.
     * The `fee` is the fee to be applied to each swap (in 1e18 scale).
     * The `initialOwner` is the address of the initial owner.
     */
    constructor(
        address sender,
        address gho,
        address sgho,
        address oracle,
        uint96 fee,
        address initialOwner
    ) OraclePool(sender, gho, sgho, oracle, fee, initialOwner) {
        if (oracle == address(0))
            revert PausableImmutableOraclePoolInvalidParameters();
    }

    /**
     * @dev Deposits `amountIn` of GHO token to receive sGHO
     * Can only be called when the contract is not paused.
     *
     * Emits a {Deposit} event.
     */
    function deposit(
        address recipient,
        uint256 amountIn,
        uint256 minAmountOut
    ) public override whenNotPaused returns (uint256) {
        return super.deposit(recipient, amountIn, minAmountOut);
    }

    /**
     * @dev Redeems `amountIn` of sGHO token to receive GHO
     * Can only be called when the contract is not paused.
     *
     * Emits a {Redeem} event.
     */
    function redeem(
        address recipient,
        uint256 amountIn,
        uint256 minAmountOut
    ) public override whenNotPaused returns (uint256) {
        return super.redeem(recipient, amountIn, minAmountOut);
    }

    /**
     * @dev Pulls `amount` of `token` from the contract and sends them to `msg.sender`.
     * Can only be called when the contract is not paused.
     *
     * Requirements:
     *
     * - `token` must be equal to `TOKEN_IN`.
     * - The `amount` of `token` to be pulled must be less than or equal to the amount of `token` available in the contract.
     *
     * Emits a {Pull} event.
     */
    function pull(address token, uint256 amount) public override whenNotPaused {
        super.pull(token, amount);
    }

    /**
     * @dev Pauses the contract.
     * Only callable when the contract is not already paused.
     */
    function pause() public onlyOwner whenNotPaused {
        _pause();
    }

    /**
     * @dev Unpauses the contract.
     * Only callable when the contract is paused.
     */
    function unpause() public onlyOwner whenPaused {
        _unpause();
    }

    /**
     * @dev Prevents the oracle from being changed.
     */
    function setOracle(address) public pure override {
        revert PausableImmutableOraclePoolImmutable();
    }

    /**
     * @dev Prevents the fee from being changed.
     */
    function setFee(uint96) public pure override {
        revert PausableImmutableOraclePoolImmutable();
    }
}
