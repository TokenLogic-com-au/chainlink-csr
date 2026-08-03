// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import {IOracle} from "./IOracle.sol";

interface IPriceOracle is IOracle {
    /// @dev The price returned by the aggregator is not strictly positive, or the scaled price is zero.
    error PriceOracleInvalidPrice();

    /// @dev The price is stale, i.e. its last update is older than the heartbeat.
    error PriceOracleStalePrice();

    /// @dev One or more of the constructor parameters is invalid (e.g. the aggregator is the zero address).
    error PriceOracleInvalidParameters();

    /**
     * @notice Returns the address of the underlying Chainlink aggregator used as the price source.
     */
    function AGGREGATOR() external view returns (address);

    /**
     * @notice Returns whether the price is inverted before being scaled, i.e. reported as 1 / price.
     */
    function IS_INVERSE() external view returns (bool);

    /**
     * @notice Returns the number of decimals reported by the underlying aggregator.
     */
    function DECIMALS() external view returns (uint8);

    /**
     * @notice Returns the heartbeat, in seconds, after which the aggregator price is considered stale.
     */
    function HEARTBEAT() external view returns (uint32);
}
