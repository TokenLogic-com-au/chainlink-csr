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
        // sGHO/GHO ratio starts at 1.0 and grows with staking yield.
        dataFeed.set(int256(1e18), 1, block.timestamp, block.timestamp, 1);
        priceOracle = new PriceOracle(address(dataFeed), false, 1 hours);
        tokenIn = new MockERC20("TokenIn", "TI", 18);
        tokenOut = new MockERC20("TokenOut", "TO", 18);
        // Cap parameters: 20% / yr (realistic DeFi peak rate), so after 6 years the linear cap
        // accumulates to ~2.2e18 — just above the fuzz price ceiling of 2e18 below.
        oraclePool = new OraclePool(
            sender,
            address(tokenIn),
            address(tokenOut),
            address(priceOracle),
            fee,
            address(this),
            2000
        );
        vm.warp(block.timestamp + 6 * 365 days);
        // Refresh the feed timestamp so subsequent reads pass the heartbeat staleness check.
        dataFeed.set(int256(1e18), 1, block.timestamp, block.timestamp, 1);

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
            address(this),
            type(uint16).max
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
            address(this),
            type(uint16).max
        );

        vm.expectRevert(IOraclePool.OraclePoolInvalidParameters.selector);
        oraclePool = new OraclePool(
            sender,
            address(0),
            address(tokenOut),
            address(priceOracle),
            fee,
            address(this),
            type(uint16).max
        );

        vm.expectRevert(IOraclePool.OraclePoolInvalidParameters.selector);
        oraclePool = new OraclePool(
            sender,
            address(tokenIn),
            address(0),
            address(priceOracle),
            fee,
            address(this),
            type(uint16).max
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
            address(0),
            type(uint16).max
        );
    }

    function test_SetOracle() public {
        // Auto-seeding the snapshot on _setOracle requires a real, live oracle, so we use a second PriceOracle
        // wired to the same data feed instead of a fuzzed address.
        PriceOracle priceOracle2 = new PriceOracle(
            address(dataFeed),
            false,
            1 hours
        );

        assertEq(
            oraclePool.getOracle(),
            address(priceOracle),
            "test_SetOracle::1"
        );

        oraclePool.setOracle(address(priceOracle2));

        assertEq(
            oraclePool.getOracle(),
            address(priceOracle2),
            "test_SetOracle::2"
        );

        oraclePool.setOracle(address(0));

        assertEq(oraclePool.getOracle(), address(0), "test_SetOracle::3");

        oraclePool.setOracle(address(priceOracle));

        assertEq(
            oraclePool.getOracle(),
            address(priceOracle),
            "test_SetOracle::4"
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
        price = bound(price, 1e18, 1.8e18);
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

        price = bound(price, 1e18, 1.8e18);
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

        price = bound(price, price + 1, 2e18);
        dataFeed.set(int256(price), 1, 0, block.timestamp, 1);

        feeAmount =
            (amountIn * oraclePool.getFee() + PRECISION - 1) /
            PRECISION;
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

    function test_AutoSeedOnDeploy() public {
        // setUp() warped forward after deploying its pool, so test against a fresh deployment to verify
        // snapshotTimestamp matches the current block.
        dataFeed.set(int256(1e18), 1, block.timestamp, block.timestamp, 1);
        OraclePool freshPool = new OraclePool(
            sender,
            address(tokenIn),
            address(tokenOut),
            address(priceOracle),
            0,
            address(this),
            1000
        );

        (
            uint256 snapshotPrice,
            uint48 snapshotTimestamp,
            uint16 maxYearlyGrowthBps,
            uint256 maxPriceGrowthPerSecondScaled
        ) = freshPool.getCapParameters();

        assertEq(snapshotPrice, 1e18, "test_AutoSeedOnDeploy::1");
        assertEq(
            snapshotTimestamp,
            block.timestamp,
            "test_AutoSeedOnDeploy::2"
        );
        assertEq(maxYearlyGrowthBps, 1000, "test_AutoSeedOnDeploy::3");

        uint256 expected = (uint256(1e18) * 1000 * 1e6) / 1e4 / 365 days;
        assertEq(
            maxPriceGrowthPerSecondScaled,
            expected,
            "test_AutoSeedOnDeploy::4"
        );
    }

    function test_CapClipsHighReading() public {
        // Deploy a pool with zero growth so the cap stays pinned at the snapshot value.
        dataFeed.set(int256(1e18), 1, block.timestamp, block.timestamp, 1);
        OraclePool cappedPool = new OraclePool(
            sender,
            address(tokenIn),
            address(tokenOut),
            address(priceOracle),
            0,
            address(this),
            0
        );

        // Oracle spikes to 1.5e18 but the cap is 1e18; the deposit should use the clipped price.
        dataFeed.set(int256(1.5e18), 1, block.timestamp, block.timestamp, 1);

        uint256 amountIn = 1e18;
        uint256 expectedOutAtCap = (amountIn * 1e18) / 1e18;

        tokenOut.mint(address(cappedPool), expectedOutAtCap);
        tokenIn.mint(sender, amountIn);

        vm.startPrank(sender);
        tokenIn.approve(address(cappedPool), amountIn);
        uint256 actualOut = cappedPool.deposit(
            alice,
            amountIn,
            expectedOutAtCap
        );
        vm.stopPrank();

        assertEq(actualOut, expectedOutAtCap, "test_CapClipsHighReading::1");
    }

    function test_CapGrowsOverTime() public {
        // 10% / year growth on a snapshot of 1.0.
        dataFeed.set(int256(1e18), 1, block.timestamp, block.timestamp, 1);
        OraclePool growthPool = new OraclePool(
            sender,
            address(tokenIn),
            address(tokenOut),
            address(priceOracle),
            0,
            address(this),
            1000
        );

        // Warp 5 years forward; the cap should accrue to ~1.5e18 (linear).
        vm.warp(block.timestamp + 5 * 365 days);
        dataFeed.set(int256(2e18), 1, block.timestamp, block.timestamp, 1);

        uint256 perSecScaled = (uint256(1e18) * 1000 * 1e6) / 1e4 / 365 days;
        uint256 expectedCap = 1e18 + (perSecScaled * 5 * 365 days) / 1e6;

        uint256 amountIn = 1e18;
        uint256 expectedOutAtCap = (amountIn * 1e18) / expectedCap;

        tokenOut.mint(address(growthPool), expectedOutAtCap);
        tokenIn.mint(sender, amountIn);

        vm.startPrank(sender);
        tokenIn.approve(address(growthPool), amountIn);
        uint256 actualOut = growthPool.deposit(alice, amountIn, 0);
        vm.stopPrank();

        assertEq(actualOut, expectedOutAtCap, "test_CapGrowsOverTime::1");
    }

    function test_SetCapParameters() public {
        // setUp() already warped well past MAXIMUM_SNAPSHOT_TERM, so we can pick any timestamp in Aave's window.
        uint48 newTs = uint48(block.timestamp - 2 days);
        oraclePool.setCapParameters(1.2e18, newTs, 500);

        (
            uint256 snapshotPrice,
            uint48 snapshotTimestamp,
            uint16 maxYearlyGrowthBps,

        ) = oraclePool.getCapParameters();

        assertEq(snapshotPrice, 1.2e18, "test_SetCapParameters::1");
        assertEq(snapshotTimestamp, newTs, "test_SetCapParameters::2");
        assertEq(maxYearlyGrowthBps, 500, "test_SetCapParameters::3");
    }

    function test_Revert_SetCapParameters() public {
        // Non-owner reverts via Ownable.
        address notOwner = makeAddr("notOwner");
        vm.expectRevert(
            abi.encodeWithSelector(
                Ownable.OwnableUnauthorizedAccount.selector,
                notOwner
            )
        );
        vm.prank(notOwner);
        oraclePool.setCapParameters(
            1.2e18,
            uint48(block.timestamp - 2 days),
            0
        );

        // Zero snapshot price reverts.
        vm.expectRevert(IOraclePool.OraclePoolSnapshotPriceIsZero.selector);
        oraclePool.setCapParameters(0, uint48(block.timestamp - 2 days), 0);

        // Timestamp inside the MIN_DELAY window reverts.
        uint48 tooRecent = uint48(block.timestamp - 1 hours);
        vm.expectRevert(
            abi.encodeWithSelector(
                IOraclePool.OraclePoolInvalidSnapshotTimestamp.selector,
                tooRecent
            )
        );
        oraclePool.setCapParameters(1.2e18, tooRecent, 0);

        // Timestamp older than MAX_TERM reverts.
        uint48 tooOld = uint48(block.timestamp - 181 days);
        vm.expectRevert(
            abi.encodeWithSelector(
                IOraclePool.OraclePoolInvalidSnapshotTimestamp.selector,
                tooOld
            )
        );
        oraclePool.setCapParameters(1.2e18, tooOld, 0);

        // Timestamp not strictly newer than stored reverts. Use the current stored snapshotTimestamp.
        (, uint48 storedTs, , ) = oraclePool.getCapParameters();
        vm.expectRevert(
            abi.encodeWithSelector(
                IOraclePool.OraclePoolInvalidSnapshotTimestamp.selector,
                storedTs
            )
        );
        oraclePool.setCapParameters(1.2e18, storedTs, 0);
    }

    function test_SetMaxYearlyGrowthBps() public {
        oraclePool.setMaxYearlyGrowthBps(1234);

        (
            ,
            ,
            uint16 maxYearlyGrowthBps,
            uint256 maxPriceGrowthPerSecondScaled
        ) = oraclePool.getCapParameters();

        assertEq(maxYearlyGrowthBps, 1234, "test_SetMaxYearlyGrowthBps::1");

        uint256 expected = (uint256(1e18) * 1234 * 1e6) / 1e4 / 365 days;
        assertEq(
            maxPriceGrowthPerSecondScaled,
            expected,
            "test_SetMaxYearlyGrowthBps::2"
        );
    }

    function test_Revert_SetMaxYearlyGrowthBps_NonOwner() public {
        address notOwner = makeAddr("notOwner");
        vm.expectRevert(
            abi.encodeWithSelector(
                Ownable.OwnableUnauthorizedAccount.selector,
                notOwner
            )
        );
        vm.prank(notOwner);
        oraclePool.setMaxYearlyGrowthBps(1234);
    }

    // -------------------------------------------------------------------------
    // Integration tests: scenario-driven verification of cap + monotonic
    // invariants across realistic sequences (spikes, corrections, oracle
    // maintenance). Each test uses a fresh pool with deterministic state.
    // -------------------------------------------------------------------------

    function _freshPool(
        uint16 maxYearlyGrowthBps
    ) internal returns (OraclePool pool) {
        dataFeed.set(int256(1e18), 1, block.timestamp, block.timestamp, 1);
        pool = new OraclePool(
            sender,
            address(tokenIn),
            address(tokenOut),
            address(priceOracle),
            0,
            address(this),
            maxYearlyGrowthBps
        );
        tokenIn.mint(sender, 1_000e18);
        tokenOut.mint(address(pool), 1_000e18);
        vm.prank(sender);
        tokenIn.approve(address(pool), type(uint256).max);
    }

    function _currentCap(OraclePool pool) internal view returns (uint256) {
        (
            uint256 snapshotPrice,
            uint48 snapshotTimestamp,
            ,
            uint256 perSecScaled
        ) = pool.getCapParameters();
        return
            snapshotPrice +
            (perSecScaled * (block.timestamp - snapshotTimestamp)) /
            1e6;
    }

    function test_Integration_AnomalousSpikeIsClipped() public {
        OraclePool pool = _freshPool(1000); // 10% / yr
        vm.warp(block.timestamp + 365 days);

        // Oracle reports a 5× spike. Cap should clip it.
        dataFeed.set(int256(5e18), 1, block.timestamp, block.timestamp, 1);

        uint256 cap = _currentCap(pool);
        uint256 amountIn = 1e18;
        uint256 expectedOut = (amountIn * 1e18) / cap;

        vm.prank(sender);
        uint256 actualOut = pool.deposit(alice, amountIn, 0);

        assertEq(
            actualOut,
            expectedOut,
            "test_Integration_AnomalousSpikeIsClipped::1"
        );
    }

    function test_Integration_PostSpikeStuckUntilRescue() public {
        OraclePool pool = _freshPool(1000); // 10% / yr
        vm.warp(block.timestamp + 365 days);

        // Spike to 5e18 → clipped to cap (~1.1e18) → lastPrice = clipped value.
        dataFeed.set(int256(5e18), 1, block.timestamp, block.timestamp, 1);
        uint256 clippedPrice = _currentCap(pool);

        vm.prank(sender);
        pool.deposit(alice, 1e18, 0);

        // Oracle "corrects" to 1.05e18, which is BELOW the clipped lastPrice. Monotonic reverts.
        dataFeed.set(int256(1.05e18), 1, block.timestamp, block.timestamp, 1);
        vm.expectRevert(
            abi.encodeWithSelector(
                IOraclePool.OraclePoolInvalidPrice.selector,
                uint256(1.05e18),
                clippedPrice
            )
        );
        vm.prank(sender);
        pool.deposit(alice, 1e18, 0);

        // Admin re-snapshots at the corrected value with a valid past timestamp. lastPrice resets.
        uint48 newTs = uint48(block.timestamp - 2 days);
        pool.setCapParameters(1.05e18, newTs, 500);

        // Deposit at 1.05e18 now succeeds.
        vm.prank(sender);
        uint256 amountOut = pool.deposit(alice, 1e18, 0);
        uint256 expectedOut = (uint256(1e18) * 1e18) / 1.05e18;
        assertEq(
            amountOut,
            expectedOut,
            "test_Integration_PostSpikeStuckUntilRescue::1"
        );
    }

    function test_Integration_SmallDownwardReverts() public {
        OraclePool pool = _freshPool(2000); // 20% / yr, cap will be permissive
        vm.warp(block.timestamp + 365 days);

        // First deposit at 1.1e18 sets lastPrice.
        dataFeed.set(int256(1.1e18), 1, block.timestamp, block.timestamp, 1);
        vm.prank(sender);
        pool.deposit(alice, 1e18, 0);

        // Oracle dips 1 wei below lastPrice. Cap doesn't help (upper bound only). Monotonic reverts.
        dataFeed.set(
            int256(1.1e18 - 1),
            1,
            block.timestamp,
            block.timestamp,
            1
        );
        vm.expectRevert(
            abi.encodeWithSelector(
                IOraclePool.OraclePoolInvalidPrice.selector,
                uint256(1.1e18 - 1),
                uint256(1.1e18)
            )
        );
        vm.prank(sender);
        pool.deposit(alice, 1e18, 0);
    }

    function test_Integration_OracleReplacement_PoolKeepsWorking() public {
        OraclePool pool = _freshPool(2000); // 20% / yr
        vm.warp(block.timestamp + 365 days);

        // Establish a lastPrice via one deposit.
        dataFeed.set(int256(1.1e18), 1, block.timestamp, block.timestamp, 1);
        vm.prank(sender);
        pool.deposit(alice, 1e18, 0);

        // Admin maintenance: deploy a refreshed PriceOracle wired to the same data feed.
        PriceOracle newOracle = new PriceOracle(
            address(dataFeed),
            false,
            1 hours
        );
        pool.setOracle(address(newOracle));

        // After replacement, the snapshot is anchored to the cap value accrued under the old oracle
        // (~1.2e18 after 1 year at 20% / yr), so the growth budget already earned isn't lost.
        // A reading of 1.15e18 — which is above the prior lastPrice but below the inherited cap —
        // flows through normally with no clip.
        dataFeed.set(int256(1.15e18), 1, block.timestamp, block.timestamp, 1);
        vm.prank(sender);
        uint256 amountOut = pool.deposit(alice, 1e18, 0);
        assertEq(
            amountOut,
            (uint256(1e18) * 1e18) / 1.15e18,
            "test_Integration_OracleReplacement_PoolKeepsWorking::1"
        );
    }

    function test_Integration_DisableAndReEnableViaSetOracleZero() public {
        OraclePool pool = _freshPool(2000);
        vm.warp(block.timestamp + 365 days);

        // Disable: deposits revert with OraclePoolOracleNotSet.
        pool.setOracle(address(0));

        vm.expectRevert(IOraclePool.OraclePoolOracleNotSet.selector);
        vm.prank(sender);
        pool.deposit(alice, 1e18, 0);

        // Re-enable: setOracle to a fresh oracle. Snapshot auto-seeds at deploy reading.
        dataFeed.set(int256(1.05e18), 1, block.timestamp, block.timestamp, 1);
        PriceOracle newOracle = new PriceOracle(
            address(dataFeed),
            false,
            1 hours
        );
        pool.setOracle(address(newOracle));

        // Deposits resume.
        vm.prank(sender);
        uint256 amountOut = pool.deposit(alice, 1e18, 0);
        uint256 expectedOut = (uint256(1e18) * 1e18) / 1.05e18;
        assertEq(
            amountOut,
            expectedOut,
            "test_Integration_DisableAndReEnableViaSetOracleZero::1"
        );
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
