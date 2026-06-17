// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import "forge-std/Test.sol";

import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";

import "../../contracts/senders/CustomSenderReferral.sol";
import "../../contracts/senders/CustomSender.sol";
import "../../contracts/utils/PriceOracle.sol";
import "../../contracts/utils/OraclePool.sol";
import "../../contracts/ccip/CCIPSenderUpgradeable.sol";
import "../../contracts/ccip/CCIPBaseUpgradeable.sol";
import "../mocks/MockERC20.sol";
import "../mocks/MockWNative.sol";
import "../mocks/MockCCIPRouter.sol";
import "../mocks/MockDataFeed.sol";

contract CustomSenderReferralTest is Test {
    CustomSenderReferral public sender;
    PriceOracle public priceOracle;
    OraclePool public oraclePool;

    MockDataFeed public dataFeed;
    MockCCIPRouter public ccipRouter;
    MockERC20 public gho;
    MockERC20 public token;

    address public vault = makeAddr("vault");

    uint128 public constant GHO_FEE = 1e18;
    uint128 public constant NATIVE_FEE = 0.01e18;
    uint256 private constant PRECISION = 1e18;
    uint64 public constant ETHEREUM_CHAIN_SELECTOR = 5009297550715157269;

    event Referral(
        address indexed user,
        address indexed referral,
        uint256 amountOut
    );

    function setUp() public {
        gho = new MockERC20("GHO", "GHO", 18);
        ccipRouter = new MockCCIPRouter(address(gho), GHO_FEE, NATIVE_FEE);
        dataFeed = new MockDataFeed(18);
        priceOracle = new PriceOracle(address(dataFeed), false, 1 hours);

        token = new MockERC20("Token", "TK", 18);

        oraclePool = new OraclePool(
            _predictContractAddress(1),
            address(gho),
            address(token),
            address(priceOracle),
            500,
            address(this)
        );
        sender = new CustomSenderReferral(
            address(token),
            address(gho),
            address(ccipRouter),
            address(oraclePool),
            vault,
            address(this)
        );
    }

    function test_Constructor() public {
        sender = new CustomSenderReferral(
            address(token),
            address(gho),
            address(ccipRouter),
            address(oraclePool),
            vault,
            address(this)
        ); // to fix coverage

        assertEq(sender.SGHO(), address(token), "test_Constructor::1");
        assertEq(sender.GHO(), address(gho), "test_Constructor::2");
        assertEq(
            sender.CCIP_ROUTER(),
            address(ccipRouter),
            "test_Constructor::3"
        );
        assertEq(
            sender.getOraclePool(),
            address(oraclePool),
            "test_Constructor::4"
        );
        assertEq(
            sender.hasRole(sender.DEFAULT_ADMIN_ROLE(), address(this)),
            true,
            "test_Constructor::5"
        );
    }

    function test_Revert_Constructor() public {
        vm.expectRevert(ICustomSender.CustomSenderInvalidParameters.selector);
        sender = new CustomSenderReferral(
            address(0),
            address(gho),
            address(ccipRouter),
            address(oraclePool),
            vault,
            address(this)
        );

        vm.expectRevert(
            ICCIPSenderUpgradeable.CCIPSenderInvalidParameters.selector
        );
        sender = new CustomSenderReferral(
            address(token),
            address(0),
            address(ccipRouter),
            address(oraclePool),
            vault,
            address(this)
        );

        vm.expectRevert(ICustomSender.CustomSenderInvalidParameters.selector);
        sender = new CustomSenderReferral(
            address(token),
            address(token),
            address(ccipRouter),
            address(oraclePool),
            vault,
            address(this)
        );

        vm.expectRevert(
            ICCIPBaseUpgradeable.CCIPBaseInvalidParameters.selector
        );
        sender = new CustomSenderReferral(
            address(token),
            address(gho),
            address(0),
            address(oraclePool),
            vault,
            address(0)
        );

        // Should not revert, we allow the oracle pool to be set to address(0) to disable fast stake
        sender = new CustomSenderReferral(
            address(token),
            address(gho),
            address(ccipRouter),
            address(0),
            vault,
            address(this)
        );

        vm.expectRevert(ICustomSender.CustomSenderZeroAddress.selector);
        sender = new CustomSenderReferral(
            address(token),
            address(gho),
            address(ccipRouter),
            address(oraclePool),
            address(0),
            address(this)
        );

        vm.expectRevert(ICustomSender.CustomSenderInvalidParameters.selector);
        sender = new CustomSenderReferral(
            address(token),
            address(gho),
            address(ccipRouter),
            address(oraclePool),
            vault,
            address(0)
        );
    }

    function test_Revert_Initialize() public {
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        sender.initialize(address(0), address(0), address(0));
    }

    function test_Fuzz_DepositReferral(uint256 price, uint256 amountIn) public {
        price = bound(price, 0.001e18, 100e18);
        amountIn = bound(amountIn, 1, 100e18);

        dataFeed.set(int256(price), 1, block.timestamp, block.timestamp, 1);

        uint256 feeAmountIn = (amountIn * oraclePool.getFee()) / PRECISION;
        uint256 amountOut = ((amountIn - feeAmountIn) * 1e18) / price;

        token.mint(address(oraclePool), amountOut);
        gho.mint(address(this), amountIn);
        gho.approve(address(sender), amountIn);

        address referral = makeAddr("referral");

        vm.expectEmit(true, true, true, true);
        emit Referral(address(this), referral, amountOut);

        uint256 result = sender.depositReferral(amountIn, amountOut, referral);

        assertEq(result, amountOut, "test_Fuzz_DepositReferral::1");
        assertEq(
            gho.balanceOf(address(this)),
            0,
            "test_Fuzz_DepositReferral::2"
        );
        assertEq(
            gho.balanceOf(address(oraclePool)),
            amountIn,
            "test_Fuzz_DepositReferral::3"
        );
        assertEq(
            token.balanceOf(address(this)),
            amountOut,
            "test_Fuzz_DepositReferral::4"
        );
        assertEq(
            token.balanceOf(address(oraclePool)),
            0,
            "test_Fuzz_DepositReferral::5"
        );
    }

    function test_Fuzz_Revert_DepositReferral(uint256 amountIn) public {
        amountIn = bound(amountIn, 1, type(uint256).max);

        dataFeed.set(1e18, 1, block.timestamp, block.timestamp, 1);
        sender.setOraclePool(address(0));

        vm.expectRevert(ICustomSender.CustomSenderOraclePoolNotSet.selector);
        sender.depositReferral(amountIn, 0, address(0));

        sender.setOraclePool(address(oraclePool));

        address badToken = address(new MockERC20("BadToken", "BAD", 18));

        vm.expectRevert(ICustomSender.CustomSenderZeroAmount.selector);
        sender.depositReferral(0, 0, address(0));

        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientAllowance.selector,
                sender,
                0,
                amountIn
            )
        );
        sender.depositReferral(amountIn, 0, address(0));

        gho.approve(address(sender), amountIn);

        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientBalance.selector,
                address(this),
                0,
                amountIn
            )
        );
        sender.depositReferral(amountIn, 0, address(0));

        sender = new CustomSenderReferral(
            address(badToken),
            address(gho),
            address(ccipRouter),
            address(oraclePool),
            vault,
            address(this)
        );
    }

    function test_Fuzz_Redeem(uint256 price, uint256 amountIn) public {
        price = bound(price, 0.001e18, 100e18);
        amountIn = bound(amountIn, 1, 100e18);

        dataFeed.set(int256(price), 1, block.timestamp, block.timestamp, 1);

        uint256 exchangeRateAmount = (amountIn * price) / 1e18;
        uint256 feeAmount = (exchangeRateAmount * oraclePool.getFee()) /
            PRECISION;
        uint256 amountOut = exchangeRateAmount - feeAmount;

        gho.mint(address(oraclePool), amountOut);
        token.mint(address(this), amountIn);
        token.approve(address(sender), amountIn);

        uint256 balance = address(this).balance;

        sender.redeem(amountIn, amountOut);

        assertEq(token.balanceOf(address(this)), 0, "test_Fuzz_Redeem::1");
        assertEq(
            token.balanceOf(address(oraclePool)),
            amountIn,
            "test_Fuzz_Redeem::2"
        );
        assertEq(
            gho.balanceOf(address(this)),
            amountOut,
            "test_Fuzz_Redeem::3"
        );
        assertEq(gho.balanceOf(address(oraclePool)), 0, "test_Fuzz_Redeem::4");
        assertEq(address(this).balance, balance, "test_Fuzz_Redeem::5");
    }

    function test_Fuzz_Revert_Redeem(uint256 amountIn) public {
        amountIn = bound(amountIn, 1, type(uint256).max);

        dataFeed.set(1e18, 1, block.timestamp, block.timestamp, 1);
        sender.setOraclePool(address(0));

        vm.expectRevert(ICustomSender.CustomSenderOraclePoolNotSet.selector);
        sender.redeem(amountIn, 0);

        sender.setOraclePool(address(oraclePool));

        vm.expectRevert(ICustomSender.CustomSenderZeroAmount.selector);
        sender.redeem(0, 0);

        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientAllowance.selector,
                sender,
                0,
                amountIn
            )
        );
        sender.redeem(amountIn, 0);

        token.approve(address(sender), amountIn);

        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientBalance.selector,
                address(this),
                0,
                amountIn
            )
        );
        sender.redeem(amountIn, 0);
    }

    function test_Fuzz_Sync(
        bytes memory receiver,
        uint256 amountToSync,
        bool payInGhoOtoD,
        uint32 gasLimitOtoD
    ) public {
        vm.assume(receiver.length > 0);

        amountToSync = bound(amountToSync, 1, 100e18);
        gasLimitOtoD = uint32(
            bound(
                gasLimitOtoD,
                sender.MIN_PROCESS_MESSAGE_GAS(),
                type(uint32).max
            )
        );

        sender.setReceiver(ETHEREUM_CHAIN_SELECTOR, receiver);
        sender.grantRole(sender.SYNC_ROLE(), address(this));
        sender.setVault(address(vault));

        bytes memory feeOtoD = FeeCodec.encodeCCIP(
            payInGhoOtoD ? GHO_FEE : NATIVE_FEE,
            payInGhoOtoD,
            gasLimitOtoD
        );

        if (payInGhoOtoD) {
            gho.mint(address(this), GHO_FEE);
            gho.approve(address(sender), GHO_FEE);
        }

        Client.EVMTokenAmount[] memory tokenAmounts;

        tokenAmounts = new Client.EVMTokenAmount[](1);
        tokenAmounts[0] = Client.EVMTokenAmount({
            token: address(gho),
            amount: amountToSync
        });

        Client.EVM2AnyMessage memory message = Client.EVM2AnyMessage({
            receiver: receiver,
            data: abi.encode(
                vault,
                bytes32(uint256(uint160(address(oraclePool)))),
                uint256(0),
                true
            ),
            tokenAmounts: tokenAmounts,
            feeToken: payInGhoOtoD ? address(gho) : address(0),
            extraArgs: Client._argsToBytes(
                Client.EVMExtraArgsV1({gasLimit: gasLimitOtoD})
            )
        });

        gho.mint(address(oraclePool), amountToSync);

        uint256 balance = address(this).balance;

        sender.sync{value: 1e18 + NATIVE_FEE}(
            address(gho),
            amountToSync,
            0,
            feeOtoD,
            new bytes(0)
        );

        assertEq(gho.balanceOf(address(this)), 0, "test_Fuzz_Sync::1");
        assertEq(gho.balanceOf(address(oraclePool)), 0, "test_Fuzz_Sync::2");
        assertEq(
            gho.balanceOf(address(ccipRouter)),
            payInGhoOtoD ? amountToSync + GHO_FEE : amountToSync,
            "test_Fuzz_Sync::3"
        );
        assertEq(token.balanceOf(address(this)), 0, "test_Fuzz_Sync::4");
        assertEq(token.balanceOf(address(oraclePool)), 0, "test_Fuzz_Sync::5");
        assertEq(token.balanceOf(address(ccipRouter)), 0, "test_Fuzz_Sync::6");
        assertEq(
            address(this).balance,
            balance - (payInGhoOtoD ? 0 : NATIVE_FEE),
            "test_Fuzz_Sync::7"
        );
        assertEq(address(oraclePool).balance, 0, "test_Fuzz_Sync::8");
        assertEq(
            address(ccipRouter).balance,
            payInGhoOtoD ? 0 : NATIVE_FEE,
            "test_Fuzz_Sync::9"
        );

        assertEq(
            ccipRouter.value(),
            payInGhoOtoD ? 0 : NATIVE_FEE,
            "test_Fuzz_Sync::10"
        );
        assertEq(
            ccipRouter.data(),
            abi.encode(ETHEREUM_CHAIN_SELECTOR, message),
            "test_Fuzz_Sync::11"
        );
    }

    function test_Fuzz_Revert_Sync(uint256 amountToSync) public {
        amountToSync = bound(amountToSync, 1, type(uint256).max);

        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                address(this),
                sender.SYNC_ROLE()
            )
        );
        sender.sync(address(gho), 0, 0, new bytes(0), new bytes(0));

        sender.grantRole(sender.SYNC_ROLE(), address(this));

        sender.setOraclePool(address(0));

        vm.expectRevert(ICustomSender.CustomSenderZeroAmount.selector);
        sender.sync(address(gho), 0, 0, new bytes(0), new bytes(0));

        vm.expectRevert(ICustomSender.CustomSenderOraclePoolNotSet.selector);
        sender.sync(address(gho), 1, 0, new bytes(0), new bytes(0));

        sender.setOraclePool(address(oraclePool));

        vm.expectRevert(
            abi.encodeWithSelector(
                IOraclePool.OraclePoolInsufficientToken.selector,
                address(gho),
                amountToSync,
                0
            )
        );
        sender.sync(address(gho), amountToSync, 0, new bytes(0), new bytes(0));

        amountToSync = bound(amountToSync, 1, 100e18);

        gho.mint(address(oraclePool), amountToSync);

        vm.expectRevert(
            abi.encodeWithSelector(
                FeeCodec.FeeCodecInvalidDataLength.selector,
                0,
                21
            )
        );
        sender.sync(address(gho), amountToSync, 0, new bytes(0), new bytes(0));

        vm.expectRevert(ICustomSender.CustomSenderInsufficientGas.selector);
        sender.sync(
            address(gho),
            amountToSync,
            0,
            new bytes(21),
            new bytes(0)
        );
    }

    receive() external payable {}

    function _predictContractAddress(
        uint256 deltaNonce
    ) private view returns (address) {
        uint256 nonce = vm.getNonce(address(this)) + deltaNonce;
        return vm.computeCreateAddress(address(this), nonce);
    }
}
