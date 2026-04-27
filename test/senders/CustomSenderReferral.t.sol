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

    uint128 public constant GHO_FEE = 1e18;
    uint128 public constant NATIVE_FEE = 0.01e18;

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
            0.05e18,
            address(this)
        );
        sender = new CustomSenderReferral(
            address(token),
            address(gho),
            address(ccipRouter),
            address(oraclePool),
            address(this)
        );
    }

    function test_Constructor() public {
        sender = new CustomSenderReferral(
            address(token),
            address(gho),
            address(ccipRouter),
            address(oraclePool),
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
            address(this)
        );

        vm.expectRevert(ICustomSender.CustomSenderInvalidParameters.selector);
        sender = new CustomSenderReferral(
            address(token),
            address(0),
            address(ccipRouter),
            address(oraclePool),
            address(this)
        );

        vm.expectRevert(
            ICCIPSenderUpgradeable.CCIPSenderInvalidParameters.selector
        );
        sender = new CustomSenderReferral(
            address(token),
            address(gho),
            address(0),
            address(oraclePool),
            address(this)
        );

        vm.expectRevert(
            ICCIPBaseUpgradeable.CCIPBaseInvalidParameters.selector
        );
        sender = new CustomSenderReferral(
            address(token),
            address(gho),
            address(ccipRouter),
            address(oraclePool),
            address(0)
        );

        // Should not revert, we allow the oracle pool to be set to address(0) to disable fast stake
        sender = new CustomSenderReferral(
            address(token),
            address(gho),
            address(ccipRouter),
            address(0),
            address(this)
        );
    }

    function test_Revert_Initialize() public {
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        sender.initialize(address(0), address(0));
    }

    function test_Fuzz_Revert_DepositReferral(uint256 amountIn) public {
        amountIn = bound(amountIn, 1, type(uint256).max);

        dataFeed.set(1e18, 1, block.timestamp, block.timestamp, 1);

        sender.setOraclePool(address(0));

        vm.expectRevert(ICustomSender.CustomSenderOraclePoolNotSet.selector);
        sender.depositReferral(amountIn, 0, address(0));

        sender.setOraclePool(address(oraclePool));

        address badToken = address(new MockERC20("BadToken", "BAD", 18));

        vm.expectRevert(ICustomSender.CustomSenderInvalidToken.selector);
        sender.depositReferral(1, 0, address(0));

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
            address(this)
        );

        vm.expectRevert(ICustomSender.CustomSenderInvalidToken.selector);
        sender.depositReferral(1, 0, address(0));
    }

    struct Amounts {
        uint256 gho;
    }

    function test_Fuzz_Sync(
        bytes memory receiver,
        uint64 destChainSelector,
        uint256 amountToSync,
        uint32 gasLimitOtoD,
        uint128 feeAmountDtoO
    ) public {
        bool payInLinkOtoD = true;

        vm.assume(receiver.length > 0);

        amountToSync = bound(amountToSync, 1, 100e18);
        feeAmountDtoO = uint128(bound(feeAmountDtoO, 0, 10e18));
        gasLimitOtoD = uint32(
            bound(
                gasLimitOtoD,
                sender.MIN_PROCESS_MESSAGE_GAS(),
                type(uint32).max
            )
        );

        sender.setReceiver(destChainSelector, receiver);
        sender.grantRole(sender.SYNC_ROLE(), address(this));

        bytes memory feeOtoD = FeeCodec.encodeCCIP(
            payInLinkOtoD ? GHO_FEE : NATIVE_FEE,
            payInLinkOtoD,
            gasLimitOtoD
        );

        Amounts memory amounts = Amounts({gho: GHO_FEE});

        if (amounts.gho > 0) {
            gho.mint(address(this), amounts.gho);
            gho.approve(address(sender), amounts.gho);
        }

        Client.EVMTokenAmount[] memory tokenAmounts;

        tokenAmounts = new Client.EVMTokenAmount[](2);
        tokenAmounts[0] = Client.EVMTokenAmount({
            token: address(gho),
            amount: amounts.gho
        });
        tokenAmounts[1] = Client.EVMTokenAmount({
            token: address(gho),
            amount: feeAmountDtoO
        });

        Client.EVM2AnyMessage memory message = Client.EVM2AnyMessage({
            receiver: receiver,
            data: FeeCodec.encodePackedDataMemory(
                address(oraclePool),
                amountToSync,
                ""
            ),
            tokenAmounts: tokenAmounts,
            feeToken: payInLinkOtoD ? address(gho) : address(0),
            extraArgs: Client._argsToBytes(
                Client.EVMExtraArgsV1({gasLimit: gasLimitOtoD})
            )
        });

        gho.transfer(address(oraclePool), amountToSync);

        uint256 balance = address(this).balance;

        sender.sync(
            destChainSelector,
            address(gho),
            amountToSync,
            0,
            feeOtoD,
            ""
        );

        assertEq(gho.balanceOf(address(this)), 0, "test_Fuzz_Sync::1");
        assertEq(gho.balanceOf(address(oraclePool)), 0, "test_Fuzz_Sync::2");
        assertEq(
            gho.balanceOf(address(ccipRouter)),
            amounts.gho,
            "test_Fuzz_Sync::3"
        );
        assertEq(token.balanceOf(address(this)), 0, "test_Fuzz_Sync::4");
        assertEq(token.balanceOf(address(oraclePool)), 0, "test_Fuzz_Sync::5");
        assertEq(token.balanceOf(address(ccipRouter)), 0, "test_Fuzz_Sync::6");
        assertEq(gho.balanceOf(address(this)), 0, "test_Fuzz_Sync::7");
        assertEq(gho.balanceOf(address(oraclePool)), 0, "test_Fuzz_Sync::8");
        assertEq(
            gho.balanceOf(address(ccipRouter)),
            amounts.gho,
            "test_Fuzz_Sync::9"
        );
        assertEq(
            address(this).balance,
            balance - amounts.gho,
            "test_Fuzz_Sync::10"
        );
        assertEq(address(oraclePool).balance, 0, "test_Fuzz_Sync::11");
        assertEq(
            address(ccipRouter).balance,
            payInLinkOtoD ? 0 : NATIVE_FEE,
            "test_Fuzz_Sync::12"
        );

        assertEq(
            ccipRouter.value(),
            (payInLinkOtoD ? 0 : NATIVE_FEE),
            "test_Fuzz_Sync::13"
        );
        assertEq(
            ccipRouter.data(),
            abi.encode(destChainSelector, message),
            "test_Fuzz_Sync::14"
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
        sender.sync(0, address(gho), 0, 0, new bytes(0), new bytes(0));

        sender.grantRole(sender.SYNC_ROLE(), address(this));

        sender.setOraclePool(address(0));

        vm.expectRevert(ICustomSender.CustomSenderZeroAmount.selector);
        sender.sync(0, address(gho), 0, 0, new bytes(0), new bytes(0));

        vm.expectRevert(ICustomSender.CustomSenderOraclePoolNotSet.selector);
        sender.sync(0, address(gho), 1, 0, new bytes(0), new bytes(0));

        sender.setOraclePool(address(oraclePool));

        vm.expectRevert(
            abi.encodeWithSelector(
                IOraclePool.OraclePoolInsufficientToken.selector,
                address(gho),
                amountToSync,
                0
            )
        );
        sender.sync(
            0,
            address(gho),
            amountToSync,
            0,
            new bytes(0),
            new bytes(0)
        );

        amountToSync = bound(amountToSync, 1, 100e18);

        gho.transfer(address(oraclePool), amountToSync);

        vm.expectRevert(
            abi.encodeWithSelector(
                FeeCodec.FeeCodecInvalidDataLength.selector,
                0,
                17
            )
        );
        sender.sync(
            0,
            address(gho),
            amountToSync,
            0,
            new bytes(0),
            new bytes(0)
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                FeeCodec.FeeCodecInvalidDataLength.selector,
                0,
                21
            )
        );
        sender.sync(
            0,
            address(gho),
            amountToSync,
            0,
            new bytes(0),
            new bytes(17)
        );

        vm.expectRevert(ICustomSender.CustomSenderInsufficientGas.selector);
        sender.sync(
            0,
            address(gho),
            amountToSync,
            0,
            new bytes(21),
            new bytes(17)
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
