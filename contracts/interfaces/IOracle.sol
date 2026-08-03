// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

interface IOracle {
    /**
     * @notice Returns the latest exchange rate (price) reported by the oracle, scaled to 1e18 (18 decimals).
     * @return The latest price in 1e18 scale.
     */
    function getLatestAnswer() external view returns (uint256);
}
