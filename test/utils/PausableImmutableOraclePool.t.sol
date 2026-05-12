// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import "forge-std/Test.sol";

import "../../contracts/utils/PausableImmutableOraclePool.sol";
import "../../contracts/utils/OraclePool.sol";
import "../../contracts/utils/PriceOracle.sol";
import "../mocks/MockDataFeed.sol";
import "../mocks/MockERC20.sol";

contract PausableImmutableoraclePoolTest is Test {
    PausableImmutableOraclePool public oraclePool;
    PriceOracle public priceOracle;
    MockDataFeed public dataFeed;
    MockERC20 public tokenOut;
    MockERC20 public tokenIn;

    uint256 private constant MAX_BPS = 10_000;

    address public sender = makeAddr("sender");
    uint96 fee = 500;

    address public alice = makeAddr("alice");
    address public bob = makeAddr("bob");

    function setUp() public {
        dataFeed = new MockDataFeed(18);
        priceOracle = new PriceOracle(address(dataFeed), false, 1 hours);
        tokenIn = new MockERC20("TokenIn", "TI", 18);
        tokenOut = new MockERC20("TokenOut", "TO", 18);
        oraclePool = new PausableImmutableOraclePool(
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
        oraclePool = new PausableImmutableOraclePool(
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
        oraclePool = new PausableImmutableOraclePool(
            address(0),
            address(tokenIn),
            address(tokenOut),
            address(priceOracle),
            fee,
            address(this)
        );

        vm.expectRevert(IOraclePool.OraclePoolInvalidParameters.selector);
        oraclePool = new PausableImmutableOraclePool(
            sender,
            address(0),
            address(tokenOut),
            address(priceOracle),
            fee,
            address(this)
        );

        vm.expectRevert(IOraclePool.OraclePoolInvalidParameters.selector);
        oraclePool = new PausableImmutableOraclePool(
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
        oraclePool = new PausableImmutableOraclePool(
            sender,
            address(tokenIn),
            address(tokenOut),
            address(priceOracle),
            fee,
            address(0)
        );

        vm.expectRevert(
            PausableImmutableOraclePool
                .PausableImmutableOraclePoolInvalidParameters
                .selector
        );
        oraclePool = new PausableImmutableOraclePool(
            sender,
            address(tokenIn),
            address(tokenOut),
            address(0),
            fee,
            address(this)
        );
    }

    function test_Fuzz_Revert_SetOracle(address oracleB) public {
        assertEq(
            oraclePool.getOracle(),
            address(priceOracle),
            "test_Fuzz_Revert_SetOracle::1"
        );

        vm.expectRevert(
            PausableImmutableOraclePool
                .PausableImmutableOraclePoolImmutable
                .selector
        );
        oraclePool.setOracle(oracleB);

        assertEq(
            oraclePool.getOracle(),
            address(priceOracle),
            "test_Fuzz_Revert_SetOracle::2"
        );
    }

    function test_Fuzz_Revert_SetFee(uint96 newFee) public {
        assertEq(oraclePool.getFee(), fee, "test_Fuzz_Revert_SetFee::1");

        vm.expectRevert(
            PausableImmutableOraclePool
                .PausableImmutableOraclePoolImmutable
                .selector
        );
        oraclePool.setFee(newFee);

        assertEq(oraclePool.getFee(), fee, "test_Fuzz_Revert_SetFee::2");
    }

    function test_Fuzz_Deposit(
        uint256 price,
        uint256 amountA,
        uint256 amountB
    ) public {
        price = bound(price, 0.01e18, 100e18);
        amountA = bound(amountA, 0.01e18, 100e18);
        amountB = bound(amountB, 0.01e18, 100e18);

        uint256 feeA = (amountA * fee) / MAX_BPS;
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

        uint256 feeB = (amountB * fee) / MAX_BPS;
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

        uint256 feeAmount = (amountIn * oraclePool.getFee()) / MAX_BPS;
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
            "test_Fuzz_Revert_Deposit::1"
        );

        price = bound(price, price + 1, 200e18);
        dataFeed.set(int256(price), 1, 0, block.timestamp, 1);

        feeAmount = (amountIn * oraclePool.getFee()) / MAX_BPS;
        amountOut = ((amountIn - feeAmount) * 1e18) / price;

        oraclePool.deposit(bob, amountIn, amountOut);

        assertEq(
            tokenOut.balanceOf(bob),
            amountOut,
            "test_Fuzz_Revert_Deposit::2"
        );
        vm.stopPrank();
    }

    function test_Revert_Swap() public {
        vm.expectRevert(IOraclePool.OraclePoolZeroAmountIn.selector);
        vm.prank(sender);
        oraclePool.deposit(address(0), 0, 0);

        oraclePool.pause();

        vm.expectRevert(Pausable.EnforcedPause.selector);
        vm.prank(sender);
        oraclePool.deposit(address(0), 1, 0);
    }

    function test_Fuzz_Redeem(
        uint256 price,
        uint256 amountA,
        uint256 amountB
    ) public {
        price = bound(price, 0.01e18, 100e18);
        amountA = bound(amountA, 0.01e18, 100e18);
        amountB = bound(amountB, 0.01e18, 100e18);

        uint256 exchangeRateAmountA = (amountA * price) / 1e18;
        uint256 feeA = (exchangeRateAmountA * fee) / MAX_BPS;
        uint256 expectedOutA = exchangeRateAmountA - feeA;

        tokenIn.mint(
            address(oraclePool),
            ((amountA + amountB) * price) / 1e18
        );

        dataFeed.set(int256(price), 1, 0, block.timestamp, 1);

        tokenOut.mint(alice, amountA);
        tokenOut.mint(bob, amountB);

        vm.prank(alice);
        tokenOut.transfer(address(sender), amountA);

        vm.startPrank(sender);
        tokenOut.approve(address(oraclePool), amountA);
        oraclePool.redeem(alice, amountA, expectedOutA);
        vm.stopPrank();

        assertEq(
            tokenOut.balanceOf(address(oraclePool)),
            amountA,
            "test_Fuzz_Redeem::1"
        );
        assertGe(
            tokenIn.balanceOf(alice),
            expectedOutA,
            "test_Fuzz_Redeem::2"
        );

        uint256 exchangeRateAmountB = (amountB * price) / 1e18;
        uint256 feeB = (exchangeRateAmountB * fee) / MAX_BPS;
        uint256 expectedOutB = exchangeRateAmountB - feeB;

        vm.prank(bob);
        tokenOut.transfer(address(sender), amountB);

        vm.startPrank(sender);
        tokenOut.approve(address(oraclePool), amountB);
        oraclePool.redeem(bob, amountB, expectedOutB);
        vm.stopPrank();

        assertEq(
            tokenOut.balanceOf(address(oraclePool)),
            amountA + amountB,
            "test_Fuzz_Redeem::3"
        );
        assertGe(
            tokenIn.balanceOf(bob),
            expectedOutB,
            "test_Fuzz_Redeem::4"
        );
    }

    function test_Fuzz_Revert_Redeem(
        address msgSender,
        uint256 price,
        uint256 amountIn
    ) public {
        vm.assume(msgSender != sender);

        price = bound(price, 0.01e18, 100e18);
        amountIn = bound(amountIn, 0.01e18, 100e18);

        dataFeed.set(int256(price), 1, 0, block.timestamp, 1);

        uint256 exchangeRateAmount = (amountIn * price) / 1e18;
        uint256 feeAmount = (exchangeRateAmount * oraclePool.getFee()) /
            MAX_BPS;
        uint256 amountOut = exchangeRateAmount - feeAmount;

        vm.prank(msgSender);
        vm.expectRevert(
            abi.encodeWithSelector(
                IOraclePool.OraclePoolUnauthorizedAccount.selector,
                msgSender
            )
        );
        oraclePool.redeem(address(0), 0, 0);

        vm.startPrank(sender);
        vm.expectRevert(
            abi.encodeWithSelector(
                IOraclePool.OraclePoolInsufficientAmountOut.selector,
                amountOut,
                amountOut + 1
            )
        );
        oraclePool.redeem(alice, amountIn, amountOut + 1);

        vm.expectRevert(
            abi.encodeWithSelector(
                IOraclePool.OraclePoolInsufficientTokenOut.selector,
                amountOut,
                0
            )
        );
        oraclePool.redeem(alice, amountIn, amountOut);

        tokenOut.mint(sender, 3 * amountIn);
        tokenIn.mint(address(oraclePool), 3 * amountOut);

        tokenOut.approve(address(oraclePool), 3 * amountIn);
        oraclePool.redeem(alice, amountIn, amountOut);

        dataFeed.set(int256(price - 1), 1, 0, block.timestamp, 1);

        vm.expectRevert(
            abi.encodeWithSelector(
                IOraclePool.OraclePoolInvalidPrice.selector,
                price - 1,
                price
            )
        );
        oraclePool.redeem(alice, amountIn, amountOut);

        assertEq(
            tokenIn.balanceOf(alice),
            amountOut,
            "test_Fuzz_Revert_Redeem::1"
        );

        price = bound(price, price + 1, 200e18);
        dataFeed.set(int256(price), 1, 0, block.timestamp, 1);

        exchangeRateAmount = (amountIn * price) / 1e18;
        feeAmount = (exchangeRateAmount * oraclePool.getFee()) / MAX_BPS;
        amountOut = exchangeRateAmount - feeAmount;

        tokenIn.mint(address(oraclePool), amountOut);

        oraclePool.redeem(bob, amountIn, amountOut);

        assertEq(
            tokenIn.balanceOf(bob),
            amountOut,
            "test_Fuzz_Revert_Redeem::2"
        );
        vm.stopPrank();
    }

    function test_Revert_Redeem() public {
        vm.expectRevert(IOraclePool.OraclePoolZeroAmountIn.selector);
        vm.prank(sender);
        oraclePool.redeem(address(0), 0, 0);

        oraclePool.pause();

        vm.expectRevert(Pausable.EnforcedPause.selector);
        vm.prank(sender);
        oraclePool.redeem(address(0), 1, 0);
    }

    function test_Fuzz_Pull(uint256 amount) public {
        amount = bound(amount, 0.01e18, 100e18);

        oraclePool = new PausableImmutableOraclePool(
            sender,
            address(tokenIn),
            address(tokenOut),
            address(priceOracle),
            0,
            address(this)
        );

        tokenIn.mint(address(sender), amount);

        tokenOut.mint(address(oraclePool), amount);

        dataFeed.set(1e18, 1, 0, block.timestamp, 1);

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

        address invalidToken = makeAddr("invalid-token");
        vm.prank(sender);
        vm.expectRevert(
            abi.encodeWithSelector(
                IOraclePool.OraclePoolPullNotAllowed.selector,
                invalidToken
            )
        );
        oraclePool.pull(invalidToken, amount);

        vm.prank(msgSender);
        vm.expectRevert(
            abi.encodeWithSelector(
                IOraclePool.OraclePoolUnauthorizedAccount.selector,
                msgSender
            )
        );
        oraclePool.pull(address(0), 0);

        oraclePool.pause();

        vm.expectRevert(Pausable.EnforcedPause.selector);
        oraclePool.pull(address(tokenIn), amount);
    }

    function test_Sweep() public {
        oraclePool = new PausableImmutableOraclePool(
            sender,
            address(tokenIn),
            address(tokenOut),
            address(priceOracle),
            0,
            address(this)
        );

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

    function test_Pause() public {
        oraclePool.pause();

        vm.expectRevert(Pausable.EnforcedPause.selector);
        oraclePool.pause();

        oraclePool.unpause();

        vm.expectRevert(Pausable.ExpectedPause.selector);
        oraclePool.unpause();
    }
}
