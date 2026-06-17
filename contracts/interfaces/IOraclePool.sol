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

    event Deposit(address recipient, uint256 amountIn, uint256 amountOut);
    event Redeem(address recipient, uint256 amountIn, uint256 amountOut);
    event Pull(address token, address recipient, uint256 amount);
    event Sweep(address token, address recipient, uint256 amount);
    event OracleUpdated(address oracle);
    event FeeUpdated(uint96 fee);

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

    function SENDER() external view returns (address);

    function GHO() external view returns (address);

    function SGHO() external view returns (address);

    function getOracle() external view returns (address);

    function getFee() external view returns (uint96);
}
