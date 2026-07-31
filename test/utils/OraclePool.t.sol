// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import "forge-std/Test.sol";

import "../../contracts/utils/OraclePool.sol";
import "../../contracts/utils/PriceOracle.sol";
import "../mocks/MockDataFeed.sol";
import "../mocks/MockERC20.sol";

contract OraclePoolTest is Test {
    OraclePool public oraclePool;
    PriceOracle public priceOracle;
    MockDataFeed public dataFeed;
    MockERC20 public tokenOut;
    MockERC20 public tokenIn;

    uint256 private constant PRECISION = 1e18;

    address public sender = makeAddr("sender");
    uint96 fee = 0.01e18;

    address public alice = makeAddr("alice");
    address public bob = makeAddr("bob");

    function setUp() public {
        dataFeed = new MockDataFeed(18);
        priceOracle = new PriceOracle(address(dataFeed), false, 1 hours);
        tokenIn = new MockERC20("TokenIn", "TI", 18);
        tokenOut = new MockERC20("TokenOut", "TO", 18);
        oraclePool = new OraclePool(
            sender,
            address(tokenIn),
            address(tokenOut),
            address(priceOracle),
            fee,
            address(this)
        );

        vm.label(address(dataFeed), "dataFeed");
        vm.label(address(priceOracle), "priceOracle");
        vm.label(address(tokenOut), "tokenOut");
        vm.label(address(tokenIn), "tokenIn");
        vm.label(address(oraclePool), "oraclePool");
    }

    function test_Constructor() public {
        oraclePool = new OraclePool(
            sender,
            address(tokenIn),
            address(tokenOut),
            address(priceOracle),
            fee,
            address(this)
        ); // to fix coverage

        assertEq(oraclePool.SENDER(), sender, "test_Constructor::1");
        assertEq(oraclePool.GHO(), address(tokenIn), "test_Constructor::2");
        assertEq(oraclePool.SGHO(), address(tokenOut), "test_Constructor::3");
        assertEq(
            oraclePool.getOracle(),
            address(priceOracle),
            "test_Constructor::4"
        );
        assertEq(oraclePool.getFee(), fee, "test_Constructor::5");
    }

    function test_Revert_Constructor() public {
        vm.expectRevert(IOraclePool.OraclePoolInvalidParameters.selector);
        oraclePool = new OraclePool(
            address(0),
            address(tokenIn),
            address(tokenOut),
            address(priceOracle),
            fee,
            address(this)
        );

        vm.expectRevert(IOraclePool.OraclePoolInvalidParameters.selector);
        oraclePool = new OraclePool(
            sender,
            address(0),
            address(tokenOut),
            address(priceOracle),
            fee,
            address(this)
        );

        vm.expectRevert(IOraclePool.OraclePoolInvalidParameters.selector);
        oraclePool = new OraclePool(
            sender,
            address(tokenIn),
            address(0),
            address(priceOracle),
            fee,
            address(this)
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                Ownable.OwnableInvalidOwner.selector,
                address(0)
            )
        );
        oraclePool = new OraclePool(
            sender,
            address(tokenIn),
            address(tokenOut),
            address(priceOracle),
            fee,
            address(0)
        );
    }

    function test_Fuzz_GetOracle(address oracleB) public {
        assertEq(
            oraclePool.getOracle(),
            address(priceOracle),
            "test_Fuzz_GetOracle::1"
        );

        oraclePool.setOracle(oracleB);

        assertEq(oraclePool.getOracle(), oracleB, "test_Fuzz_GetOracle::2");

        oraclePool.setOracle(address(0));

        assertEq(oraclePool.getOracle(), address(0), "test_Fuzz_GetOracle::3");

        oraclePool.setOracle(address(priceOracle));

        assertEq(
            oraclePool.getOracle(),
            address(priceOracle),
            "test_Fuzz_GetOracle::4"
        );
    }

    function test_Fuzz_GetFee(uint96 newFee) public {
        newFee = uint96(bound(newFee, 0, PRECISION));

        assertEq(oraclePool.getFee(), fee, "test_Fuzz_GetFee::1");

        oraclePool.setFee(newFee);

        assertEq(oraclePool.getFee(), newFee, "test_Fuzz_GetFee::2");

        oraclePool.setFee(0);

        assertEq(oraclePool.getFee(), 0, "test_Fuzz_GetFee::3");

        oraclePool.setFee(fee);

        assertEq(oraclePool.getFee(), fee, "test_Fuzz_GetFee::4");
    }

    function test_Fuzz_Revert_GetFee(uint96 newFee) public {
        newFee = uint96(bound(newFee, 1e18 + 1, type(uint96).max));

        vm.expectRevert(IOraclePool.OraclePoolFeeTooHigh.selector);
        oraclePool.setFee(newFee);
    }

    function test_Fuzz_Deposit(
        uint256 price,
        uint256 amountA,
        uint256 amountB
    ) public {
        price = bound(price, 0.01e18, 100e18);
        amountA = bound(amountA, 0.01e18, 100e18);
        amountB = bound(amountB, 0.01e18, 100e18);

        // Fee rounds up (in the pool's favour), matching OraclePool.
        uint256 feeA = (amountA * fee + PRECISION - 1) / PRECISION;
        uint256 expectedOutA = ((amountA - feeA) * 1e18) / price;

        tokenOut.mint(
            address(oraclePool),
            ((amountA + amountB) * 1e18) / price
        );

        dataFeed.set(int256(price), 1, 0, block.timestamp, 1);

        tokenIn.mint(alice, amountA);
        tokenIn.mint(bob, amountB);

        vm.prank(alice);
        tokenIn.transfer(address(sender), amountA);

        vm.startPrank(sender);
        tokenIn.approve(address(oraclePool), amountA);
        oraclePool.deposit(alice, amountA, expectedOutA);
        vm.stopPrank();

        assertEq(
            tokenIn.balanceOf(address(oraclePool)),
            amountA,
            "test_Fuzz_Deposit::1"
        );
        assertGe(
            tokenOut.balanceOf(alice),
            expectedOutA,
            "test_Fuzz_Deposit::2"
        );

        uint256 feeB = (amountB * fee + PRECISION - 1) / PRECISION;
        uint256 expectedOutB = ((amountB - feeB) * 1e18) / price;

        vm.prank(bob);
        tokenIn.transfer(address(sender), amountB);

        vm.startPrank(sender);
        tokenIn.approve(address(oraclePool), amountB);
        oraclePool.deposit(bob, amountB, expectedOutB);
        vm.stopPrank();

        assertEq(
            tokenIn.balanceOf(address(oraclePool)),
            amountA + amountB,
            "test_Fuzz_Deposit::3"
        );
        assertGe(tokenOut.balanceOf(bob), expectedOutB, "test_Fuzz_Deposit::4");
    }

    function test_Fuzz_Revert_Deposit(
        address msgSender,
        uint256 price,
        uint256 amountIn
    ) public {
        vm.assume(msgSender != sender);

        price = bound(price, 0.01e18, 100e18);
        amountIn = bound(amountIn, 0.01e18, 100e18);

        dataFeed.set(int256(price), 1, 0, block.timestamp, 1);

        uint256 feeAmount = (amountIn * oraclePool.getFee() + PRECISION - 1) /
            PRECISION;
        uint256 amountOut = ((amountIn - feeAmount) * 1e18) / price;

        vm.prank(msgSender);
        vm.expectRevert(
            abi.encodeWithSelector(
                IOraclePool.OraclePoolUnauthorizedAccount.selector,
                msgSender
            )
        );
        oraclePool.deposit(address(0), 0, 0);

        vm.startPrank(sender);
        vm.expectRevert(
            abi.encodeWithSelector(
                IOraclePool.OraclePoolInsufficientAmountOut.selector,
                amountOut,
                amountOut + 1
            )
        );
        oraclePool.deposit(alice, amountIn, amountOut + 1);

        vm.expectRevert(
            abi.encodeWithSelector(
                IOraclePool.OraclePoolInsufficientTokenOut.selector,
                amountOut,
                0
            )
        );
        oraclePool.deposit(alice, amountIn, amountOut);

        tokenIn.mint(sender, 3 * amountIn);
        tokenOut.mint(address(oraclePool), 3 * amountOut);

        tokenIn.approve(address(oraclePool), 3 * amountIn);
        oraclePool.deposit(alice, amountIn, amountOut);

        dataFeed.set(int256(price - 1), 1, 0, block.timestamp, 1);

        vm.expectRevert(
            abi.encodeWithSelector(
                IOraclePool.OraclePoolInvalidPrice.selector,
                price - 1,
                price
            )
        );
        oraclePool.deposit(alice, amountIn, amountOut);

        assertEq(
            tokenOut.balanceOf(alice),
            amountOut,
            "test_Fuzz_Revert_Swap::1"
        );

        price = bound(price, price + 1, 200e18);
        dataFeed.set(int256(price), 1, 0, block.timestamp, 1);

        feeAmount = (amountIn * oraclePool.getFee() + PRECISION - 1) / PRECISION;
        amountOut = ((amountIn - feeAmount) * 1e18) / price;

        oraclePool.deposit(bob, amountIn, amountOut);

        assertEq(
            tokenOut.balanceOf(bob),
            amountOut,
            "test_Fuzz_Revert_Swap::2"
        );
        vm.stopPrank();
    }

    function test_Revert_Deposit() public {
        oraclePool.setOracle(address(0));

        vm.expectRevert(IOraclePool.OraclePoolZeroAmountIn.selector);
        vm.prank(sender);
        oraclePool.deposit(address(0), 0, 0);

        vm.expectRevert(IOraclePool.OraclePoolInvalidRecipient.selector);
        vm.prank(sender);
        oraclePool.deposit(address(0), 1, 0);

        vm.expectRevert(IOraclePool.OraclePoolOracleNotSet.selector);
        vm.prank(sender);
        oraclePool.deposit(alice, 1, 0);
    }

    function test_Fuzz_Pull(uint256 amount) public {
        amount = bound(amount, 0.01e18, 100e18);

        tokenIn.mint(address(sender), amount);

        tokenOut.mint(address(oraclePool), amount);

        dataFeed.set(1e18, 1, 0, block.timestamp, 1);
        oraclePool.setFee(0);

        vm.startPrank(sender);
        tokenIn.approve(address(oraclePool), amount);
        oraclePool.deposit(alice, amount, amount);

        assertEq(
            tokenIn.balanceOf(address(oraclePool)),
            amount,
            "test_Fuzz_Pull::1"
        );

        oraclePool.pull(address(tokenIn), amount);
        vm.stopPrank();

        assertEq(
            tokenIn.balanceOf(address(oraclePool)),
            0,
            "test_Fuzz_Pull::2"
        );
        assertEq(tokenIn.balanceOf(sender), amount, "test_Fuzz_Pull::3");
    }

    function test_Fuzz_Revert_Pull(address msgSender, uint256 amount) public {
        vm.assume(msgSender != sender);

        amount = bound(amount, 0, type(uint256).max - 1);

        tokenIn.mint(address(oraclePool), amount);

        vm.prank(sender);
        vm.expectRevert(
            abi.encodeWithSelector(
                IOraclePool.OraclePoolInsufficientToken.selector,
                tokenIn,
                amount + 1,
                amount
            )
        );
        oraclePool.pull(address(tokenIn), amount + 1);

        address invalidToken = makeAddr("invalidToken");

        vm.prank(sender);
        vm.expectRevert(
            abi.encodeWithSelector(
                IOraclePool.OraclePoolPullNotAllowed.selector,
                invalidToken
            )
        );
        oraclePool.pull(invalidToken, amount + 1);

        vm.prank(msgSender);
        vm.expectRevert(
            abi.encodeWithSelector(
                IOraclePool.OraclePoolUnauthorizedAccount.selector,
                msgSender
            )
        );
        oraclePool.pull(address(0), 0);
    }

    function test_Sweep() public {
        tokenOut.mint(address(oraclePool), 1e18);

        assertEq(
            tokenOut.balanceOf(address(oraclePool)),
            1e18,
            "test_Sweep::1"
        );
        assertEq(tokenOut.balanceOf(address(this)), 0, "test_Sweep::2");

        oraclePool.sweep(address(tokenOut), address(this), 1e18);

        assertEq(tokenOut.balanceOf(address(oraclePool)), 0, "test_Sweep::3");
        assertEq(tokenOut.balanceOf(address(this)), 1e18, "test_Sweep::4");

        tokenIn.mint(address(sender), 1e18);
        tokenOut.mint(address(oraclePool), 1e18);

        dataFeed.set(1e18, 1, 0, block.timestamp, 1);
        oraclePool.setFee(0);

        vm.startPrank(sender);
        tokenIn.approve(address(oraclePool), 1e18);
        oraclePool.deposit(alice, 1e18, 1e18);
        vm.stopPrank();

        assertEq(tokenIn.balanceOf(address(oraclePool)), 1e18, "test_Sweep::5");
        assertEq(tokenIn.balanceOf(address(this)), 0, "test_Sweep::6");

        oraclePool.sweep(address(tokenIn), address(this), 1e18);

        assertEq(tokenIn.balanceOf(address(oraclePool)), 0, "test_Sweep::7");
        assertEq(tokenIn.balanceOf(address(this)), 1e18, "test_Sweep::8");

        oraclePool.sweep(address(tokenOut), address(this), 0);
        oraclePool.sweep(address(tokenIn), address(this), 0);
    }

    /// @dev deposit: the fee must round UP so the pool never gives out more
    /// `SGHO` than intended. 101 wei in at a 1% fee and 1:1 price yields a
    /// fractional fee (1.01), which must round to 2 rather than 1.
    function test_Deposit_RoundsFeeUp() public {
        oraclePool.setFee(0.01e18);
        dataFeed.set(1e18, 1, 0, block.timestamp, 1);

        uint256 amountIn = 101;

        uint256 feeFloor = (amountIn * 0.01e18) / PRECISION; // 1
        uint256 feeCeil = (amountIn * 0.01e18 + PRECISION - 1) / PRECISION; // 2
        assertEq(feeFloor, 1, "test_Deposit_RoundsFeeUp::1");
        assertEq(feeCeil, 2, "test_Deposit_RoundsFeeUp::2");

        uint256 naiveOut = ((amountIn - feeFloor) * 1e18) / 1e18; // 100 (user-favourable)
        uint256 expectedOut = ((amountIn - feeCeil) * 1e18) / 1e18; // 99 (pool-favourable)

        tokenOut.mint(address(oraclePool), 1e18);
        tokenIn.mint(sender, amountIn);

        vm.startPrank(sender);
        tokenIn.approve(address(oraclePool), amountIn);
        uint256 amountOut = oraclePool.deposit(alice, amountIn, expectedOut);
        vm.stopPrank();

        assertEq(amountOut, expectedOut, "test_Deposit_RoundsFeeUp::3");
        assertLt(amountOut, naiveOut, "test_Deposit_RoundsFeeUp::4");
    }

    /// @dev redeem: the fee must round UP so the pool never gives out more
    /// `GHO` than intended.
    function test_Redeem_RoundsFeeUp() public {
        oraclePool.setFee(0.01e18);
        dataFeed.set(1e18, 1, 0, block.timestamp, 1);

        uint256 amountIn = 101;

        uint256 exchangeRateAmount = (amountIn * 1e18) / PRECISION; // 101
        uint256 feeFloor = (exchangeRateAmount * 0.01e18) / PRECISION; // 1
        uint256 feeCeil = (exchangeRateAmount * 0.01e18 + PRECISION - 1) /
            PRECISION; // 2
        assertEq(feeCeil, feeFloor + 1, "test_Redeem_RoundsFeeUp::1");

        uint256 naiveOut = exchangeRateAmount - feeFloor; // 100 (user-favourable)
        uint256 expectedOut = exchangeRateAmount - feeCeil; // 99 (pool-favourable)

        tokenIn.mint(address(oraclePool), 1e18);
        tokenOut.mint(sender, amountIn);

        vm.startPrank(sender);
        tokenOut.approve(address(oraclePool), amountIn);
        uint256 amountOut = oraclePool.redeem(alice, amountIn, expectedOut);
        vm.stopPrank();

        assertEq(amountOut, expectedOut, "test_Redeem_RoundsFeeUp::2");
        assertEq(
            tokenIn.balanceOf(alice),
            expectedOut,
            "test_Redeem_RoundsFeeUp::3"
        );
        assertLt(amountOut, naiveOut, "test_Redeem_RoundsFeeUp::4");
    }

    /// @dev Invariant: for any price/amount/fee, deposit must never return more
    /// than the user-favourable (floor-fee) computation. Rounding only ever
    /// benefits the pool.
    function test_Fuzz_Deposit_RoundingFavorsPool(
        uint256 price,
        uint256 amountIn,
        uint96 newFee
    ) public {
        price = bound(price, 0.01e18, 100e18);
        amountIn = bound(amountIn, 0.01e18, 100e18);
        oraclePool.setFee(uint96(bound(newFee, 0, uint96(PRECISION))));

        dataFeed.set(int256(price), 1, 0, block.timestamp, 1);

        uint256 feeFloor = (amountIn * oraclePool.getFee()) / PRECISION;
        uint256 naiveOut = ((amountIn - feeFloor) * 1e18) / price;

        tokenOut.mint(address(oraclePool), (amountIn * 1e18) / price + 1);
        tokenIn.mint(sender, amountIn);

        vm.startPrank(sender);
        tokenIn.approve(address(oraclePool), amountIn);
        uint256 amountOut = oraclePool.deposit(alice, amountIn, 0);
        vm.stopPrank();

        assertLe(
            amountOut,
            naiveOut,
            "test_Fuzz_Deposit_RoundingFavorsPool::1"
        );
    }

    /// @dev Invariant: for any price/amount/fee, redeem must never return more
    /// than the user-favourable (floor-fee) computation.
    function test_Fuzz_Redeem_RoundingFavorsPool(
        uint256 price,
        uint256 amountIn,
        uint96 newFee
    ) public {
        price = bound(price, 0.01e18, 100e18);
        amountIn = bound(amountIn, 0.01e18, 100e18);
        oraclePool.setFee(uint96(bound(newFee, 0, uint96(PRECISION))));

        dataFeed.set(int256(price), 1, 0, block.timestamp, 1);

        uint256 exchangeRateAmount = (amountIn * price) / PRECISION;
        uint256 feeFloor = (exchangeRateAmount * oraclePool.getFee()) /
            PRECISION;
        uint256 naiveOut = exchangeRateAmount - feeFloor;

        tokenIn.mint(address(oraclePool), exchangeRateAmount + 1);
        tokenOut.mint(sender, amountIn);

        vm.startPrank(sender);
        tokenOut.approve(address(oraclePool), amountIn);
        uint256 amountOut = oraclePool.redeem(alice, amountIn, 0);
        vm.stopPrank();

        assertLe(amountOut, naiveOut, "test_Fuzz_Redeem_RoundingFavorsPool::1");
    }
}
