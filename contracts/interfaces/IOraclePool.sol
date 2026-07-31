// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

interface IOraclePool {
    error OraclePoolUnauthorizedAccount(address sender);
    error OraclePoolInsufficientTokenOut(
        uint256 amountOut,
        uint256 availableOut
    );
    error OraclePoolInsufficientToken(
        address token,
        uint256 amountOut,
        uint256 availableOut
    );
    error OraclePoolInsufficientAmountOut(
        uint256 amountOut,
        uint256 minAmountOut
    );
    error OraclePoolInvalidRecipient();
    error OraclePoolPullNotAllowed(address token);
    error OraclePoolOracleNotSet();
    error OraclePoolFeeTooHigh();
    error OraclePoolZeroAmountIn();
    error OraclePoolInvalidParameters();
    error OraclePoolInvalidPrice(uint256 price, uint256 lastPrice);

    /// @dev The snapshot price is zero, which would freeze the cap at zero and brick swaps.
    error OraclePoolSnapshotPriceIsZero();

    /// @dev The snapshot timestamp is outside the allowed window.
    /// @param snapshotTimestamp The rejected snapshot timestamp.
    error OraclePoolInvalidSnapshotTimestamp(uint48 snapshotTimestamp);

    event Deposit(address recipient, uint256 amountIn, uint256 amountOut);
    event Redeem(address recipient, uint256 amountIn, uint256 amountOut);
    event Pull(address token, address recipient, uint256 amount);
    event Sweep(address token, address recipient, uint256 amount);
    event OracleUpdated(address oracle);
    event FeeUpdated(uint96 fee);
    /**
     * Emitted when the snapshot, snapshot timestamp, or maximum yearly growth is updated.
     * @param snapshotPrice The new snapshot price (1e18 scale).
     * @param snapshotTimestamp The new snapshot timestamp.
     * @param maxYearlyGrowthBps The new maximum yearly growth (in basis points).
     * @param maxPriceGrowthPerSecondScaled The derived per-second growth budget (scaled by 1e6).
     */
    event CapParametersUpdated(
        uint256 snapshotPrice,
        uint48 snapshotTimestamp,
        uint16 maxYearlyGrowthBps,
        uint256 maxPriceGrowthPerSecondScaled
    );

    /**
     * Emitted when only the maximum yearly growth is updated.
     * @param maxYearlyGrowthBps The new maximum yearly growth (in basis points).
     * @param maxPriceGrowthPerSecondScaled The recomputed per-second growth budget (scaled by 1e6).
     */
    event MaxYearlyGrowthBpsUpdated(
        uint16 maxYearlyGrowthBps,
        uint256 maxPriceGrowthPerSecondScaled
    );

    function deposit(
        address recipient,
        uint256 exactAmountIn,
        uint256 minAmountOut
    ) external returns (uint256);

    function redeem(
        address recipient,
        uint256 amountIn,
        uint256 minAmountOut
    ) external returns (uint256);

    function pull(address token, uint256 amount) external;

    function sweep(address token, address recipient, uint256 amount) external;

    function setOracle(address oracle) external;

    function setFee(uint96 fee) external;

    /**
     * @dev Re-snapshots the price cap and updates the maximum yearly growth in one call. Resets `_lastPrice`
     * to `snapshotPrice` so a stuck-high reading from before the re-snapshot does not brick swaps.
     * @param snapshotPrice The new snapshot price (1e18 scale).
     * @param snapshotTimestamp The new snapshot timestamp. Must be strictly newer than the stored one,
     * older than `block.timestamp - MINIMUM_SNAPSHOT_DELAY`, and not older than `block.timestamp - MAXIMUM_SNAPSHOT_TERM`.
     * @param maxYearlyGrowthBps The new maximum yearly growth (in basis points).
     */
    function setCapParameters(
        uint256 snapshotPrice,
        uint48 snapshotTimestamp,
        uint16 maxYearlyGrowthBps
    ) external;

    /**
     * @dev Adjusts only the maximum yearly growth. Snapshot and `_lastPrice` are not touched. Lowering this
     * value when `_lastPrice` already exceeds the resulting cap will brick swaps until the next re-snapshot.
     * @param maxYearlyGrowthBps The new maximum yearly growth (in basis points).
     */
    function setMaxYearlyGrowthBps(uint16 maxYearlyGrowthBps) external;

    function SENDER() external view returns (address);

    function GHO() external view returns (address);

    function SGHO() external view returns (address);

    function getOracle() external view returns (address);

    function getFee() external view returns (uint96);

    /**
     * @notice Returns the current price-cap parameters and the derived per-second growth budget.
     * @return snapshotPrice The current snapshot price (1e18 scale).
     * @return snapshotTimestamp The current snapshot timestamp.
     * @return maxYearlyGrowthBps The current maximum yearly growth (in basis points).
     * @return maxPriceGrowthPerSecondScaled The derived per-second growth budget (scaled by 1e6).
     */
    function getCapParameters()
        external
        view
        returns (
            uint256 snapshotPrice,
            uint48 snapshotTimestamp,
            uint16 maxYearlyGrowthBps,
            uint256 maxPriceGrowthPerSecondScaled
        );
}
