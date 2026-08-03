// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import {IOracle} from "./IOracle.sol";

interface IPriceConverterOracle is IOracle {
    /// @dev One or more of the constructor parameters is invalid (e.g. a price oracle is the zero address).
    error PriceConverterOracleInvalidParameters();

    /// @dev The price derived from composing the base and quote oracles is invalid (e.g. zero).
    error PriceConverterOracleInvalidPrice();

    /**
     * @notice Returns the address of the base price oracle, which provides the price of the base asset.
     */
    function BASE_PRICE_ORACLE() external view returns (address);

    /**
     * @notice Returns the address of the quote price oracle, which provides the price of the quote asset.
     */
    function QUOTE_PRICE_ORACLE() external view returns (address);
}
