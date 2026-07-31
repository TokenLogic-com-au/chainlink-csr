// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import "forge-std/Test.sol";

import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/introspection/ERC165Upgradeable.sol";
import "../../contracts/ccip/CCIPSenderUpgradeable.sol";
import "../../contracts/libraries/ExtraArgsCodec.sol";
import "../Mocks/MockERC20.sol";
import "../Mocks/MockCCIPRouter.sol";

contract CCIPSenderUpgradeableTest is Test {
    MockCCIPSender public sender;
    MockCCIPRouter ccipRouter;
    MockERC20 public ghoToken;

    uint128 public constant LINK_FEE = 1e18;
    uint128 public constant NATIVE_FEE = 0.01e18;

    function setUp() public {
        ghoToken = new MockERC20("GHO", "GHO", 18);
        ccipRouter = new MockCCIPRouter(
            address(ghoToken),
            LINK_FEE,
            NATIVE_FEE
        );

        sender = new MockCCIPSender(address(ghoToken), address(ccipRouter));

        vm.label(address(ccipRouter), "ccipRouter");
        vm.label(address(ghoToken), "ghoToken");
        vm.label(address(sender), "sender");
    }

    function test_Constructor() public {
        sender = new MockCCIPSender(address(ghoToken), address(ccipRouter)); // to fix coverage

        assertEq(
            sender.CCIP_ROUTER(),
            address(ccipRouter),
            "test_Constructor::1"
        );
        assertEq(sender.GHO_TOKEN(), address(ghoToken), "test_Constructor::2");
    }

    mapping(address => uint256) public _sent;

    function test_Fuzz_CCIPSend(
        uint64 destChainSelector,
        bytes memory receiver,
        Client.EVMTokenAmount[] memory tokenAmounts,
        bool payInLink,
        uint256 maxFee,
        uint32 gasLimit,
        bytes memory data
    ) public {
        vm.assume(receiver.length > 0);

        if (tokenAmounts.length > 16) {
            assembly {
                mstore(tokenAmounts, 16) // Limit the number of token amounts to 16
            }
        }

        uint256 fee;
        if (payInLink) {
            fee = LINK_FEE;

            ghoToken.mint(address(this), fee);
            ghoToken.approve(address(sender), fee);
        } else {
            fee = NATIVE_FEE;
        }

        maxFee = bound(maxFee, fee, 100e18);

        bytes memory tokenCode = address(ghoToken).code;
        for (uint256 i = 0; i < tokenAmounts.length; i++) {
            address token = tokenAmounts[i].token;
            uint256 amount = tokenAmounts[i].amount;

            token = address(
                uint160(
                    uint256(
                        keccak256(
                            abi.encode(
                                uint256(keccak256(abi.encode(token))) - 1
                            )
                        )
                    )
                )
            ); // Should prevent any collisions

            vm.etch(address(token), tokenCode);

            unchecked {
                amount = bound(
                    amount,
                    1,
                    type(uint256).max -
                        _sent[token] +
                        i +
                        1 -
                        tokenAmounts.length
                );
            }

            tokenAmounts[i] = Client.EVMTokenAmount({
                token: token,
                amount: amount
            });
            _sent[token] += amount;

            MockERC20(token).mint(address(sender), amount);
        }

        bytes32 messageId = sender.ccipSendTo{value: payInLink ? 0 : fee}(
            destChainSelector,
            receiver,
            tokenAmounts,
            payInLink,
            maxFee,
            gasLimit,
            data,
            new bytes(0)
        );

        Client.EVM2AnyMessage memory message = Client.EVM2AnyMessage({
            receiver: receiver,
            data: data,
            tokenAmounts: tokenAmounts,
            feeToken: payInLink ? address(ghoToken) : address(0),
            extraArgs: Client._argsToBytes(
                Client.EVMExtraArgsV1({gasLimit: gasLimit})
            )
        });

        assertEq(messageId, keccak256("test"), "test_Fuzz_CCIPSend::1");
        assertEq(
            ccipRouter.value(),
            payInLink ? 0 : fee,
            "test_Fuzz_CCIPSend::2"
        );
        assertEq(
            ccipRouter.data(),
            abi.encode(destChainSelector, message),
            "test_Fuzz_CCIPSend::3"
        );

        for (uint256 i = 0; i < tokenAmounts.length; i++) {
            address token = tokenAmounts[i].token;

            assertEq(
                MockERC20(token).balanceOf(address(ccipRouter)),
                _sent[token],
                "test_Fuzz_CCIPSend::4"
            );
            assertEq(
                MockERC20(token).balanceOf(address(this)),
                0,
                "test_Fuzz_CCIPSend::5"
            );
            assertEq(
                MockERC20(token).balanceOf(address(sender)),
                0,
                "test_Fuzz_CCIPSend::6"
            );
        }
    }

    function test_Revert_CCIPSend() public {
        vm.expectRevert(
            ICCIPSenderUpgradeable.CCIPSenderEmptyReceiver.selector
        );
        sender.ccipSendTo(
            0,
            new bytes(0),
            new Client.EVMTokenAmount[](0),
            false,
            0,
            0,
            new bytes(0),
            new bytes(0)
        );
    }

    function test_Fuzz_Revert_CCIPSend(bool payInLink, uint256 fee) public {
        Client.EVMTokenAmount[]
            memory tokenAmounts = new Client.EVMTokenAmount[](1);

        vm.expectRevert(
            ICCIPSenderUpgradeable.CCIPSenderInvalidTokenAmount.selector
        );
        sender.ccipSendTo(
            0,
            new bytes(1),
            tokenAmounts,
            payInLink,
            0,
            0,
            new bytes(0),
            new bytes(0)
        );

        tokenAmounts[0] = Client.EVMTokenAmount({
            token: address(ghoToken),
            amount: 0
        });

        vm.expectRevert(
            ICCIPSenderUpgradeable.CCIPSenderInvalidTokenAmount.selector
        );
        sender.ccipSendTo(
            0,
            new bytes(1),
            tokenAmounts,
            payInLink,
            0,
            0,
            new bytes(0),
            new bytes(0)
        );

        tokenAmounts[0] = Client.EVMTokenAmount({token: address(0), amount: 1});

        vm.expectRevert(
            ICCIPSenderUpgradeable.CCIPSenderInvalidTokenAmount.selector
        );
        sender.ccipSendTo(
            0,
            new bytes(1),
            tokenAmounts,
            payInLink,
            0,
            0,
            new bytes(0),
            new bytes(0)
        );

        fee = bound(fee, 0, (payInLink ? LINK_FEE : NATIVE_FEE) - 1);

        vm.expectRevert(
            abi.encodeWithSelector(
                ICCIPSenderUpgradeable.CCIPSenderExceedsMaxFee.selector,
                payInLink ? LINK_FEE : NATIVE_FEE,
                fee
            )
        );
        sender.ccipSendTo(
            0,
            new bytes(1),
            new Client.EVMTokenAmount[](0),
            payInLink,
            fee,
            0,
            new bytes(0),
            new bytes(0)
        );
    }

    function test_Revert_CCIPSend_InsufficientGasInExtraArgs() public {
        ExtraArgsCodec.GenericExtraArgsV3 memory args;
        args.gasLimit = sender.minProcessMessageGas() - 1;
        bytes memory extraArgs = abi.encodeWithSelector(ExtraArgsCodec.GENERIC_EXTRA_ARGS_V3_TAG, args);

        vm.expectRevert(
            ICCIPSenderUpgradeable.CCIPSenderInsufficientGas.selector
        );
        sender.ccipSendTo(
            0,
            new bytes(1),
            new Client.EVMTokenAmount[](0),
            false,
            type(uint256).max,
            0,
            new bytes(0),
            extraArgs
        );
    }

    function test_CCIPSend_SufficientGasInExtraArgs() public {
        ExtraArgsCodec.GenericExtraArgsV3 memory args;
        args.gasLimit = sender.minProcessMessageGas();
        bytes memory extraArgs = abi.encodeWithSelector(ExtraArgsCodec.GENERIC_EXTRA_ARGS_V3_TAG, args);

        sender.ccipSendTo{value: NATIVE_FEE}(
            0,
            new bytes(1),
            new Client.EVMTokenAmount[](0),
            false,
            type(uint256).max,
            0,
            new bytes(0),
            extraArgs
        );
    }

    function test_Revert_CCIPSend_InvalidExtraArgsTag() public {
        ExtraArgsCodec.GenericExtraArgsV3 memory args;
        args.gasLimit = sender.minProcessMessageGas();

        // Encode with a wrong tag; every other byte matches a valid V3 blob.
        bytes4 wrongTag = 0xdeadbeef;
        bytes memory extraArgs = abi.encodeWithSelector(wrongTag, args);

        vm.expectRevert(
            abi.encodeWithSelector(
                ICCIPSenderUpgradeable.CCIPSenderInvalidExtraArgsTag.selector,
                wrongTag
            )
        );
        sender.ccipSendTo(
            0,
            new bytes(1),
            new Client.EVMTokenAmount[](0),
            false,
            type(uint256).max,
            0,
            new bytes(0),
            extraArgs
        );
    }

    function test_Revert_CCIPSend_TruncatedExtraArgsTag() public {
        // extraArgs of length > 0 but < 4 — cast to bytes4 pads with zeros and mismatches the tag.
        bytes memory extraArgs = hex"a69dd4"; // 3 bytes, one short of the real tag.
        bytes4 expected = bytes4(extraArgs);

        vm.expectRevert(
            abi.encodeWithSelector(
                ICCIPSenderUpgradeable.CCIPSenderInvalidExtraArgsTag.selector,
                expected
            )
        );
        sender.ccipSendTo(
            0,
            new bytes(1),
            new Client.EVMTokenAmount[](0),
            false,
            type(uint256).max,
            0,
            new bytes(0),
            extraArgs
        );
    }

    function test_SetMinProcessMessageGas() public {
        uint32 initialGas = sender.minProcessMessageGas();
        assertEq(initialGas, 400_000, "test_SetMinProcessMessageGas::1");

        uint32 newGas = 350_000;

        vm.expectEmit(true, true, true, true, address(sender));
        emit ICCIPSenderUpgradeable.MinProcessMessageGasSet(initialGas, newGas);
        sender.setMinProcessMessageGas(newGas);

        assertEq(
            sender.minProcessMessageGas(),
            newGas,
            "test_SetMinProcessMessageGas::2"
        );

        // Setting to the boundary value (max uint32) writes without overflow and reads back cleanly.
        vm.expectEmit(true, true, true, true, address(sender));
        emit ICCIPSenderUpgradeable.MinProcessMessageGasSet(
            newGas,
            type(uint32).max
        );
        sender.setMinProcessMessageGas(type(uint32).max);

        assertEq(
            sender.minProcessMessageGas(),
            type(uint32).max,
            "test_SetMinProcessMessageGas::3"
        );
    }

    function test_Revert_SetMinProcessMessageGas_ZeroValue() public {
        vm.expectRevert(
            ICCIPSenderUpgradeable.CCIPSenderInvalidGasLimit.selector
        );
        sender.setMinProcessMessageGas(0);
    }

    function test_Revert_SetMinProcessMessageGas_NonAdmin() public {
        address notAdmin = makeAddr("notAdmin");
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                notAdmin,
                sender.DEFAULT_ADMIN_ROLE()
            )
        );
        vm.prank(notAdmin);
        sender.setMinProcessMessageGas(350_000);
    }

    function test_Fuzz_Initialize() public {
        sender = new MockCCIPSender(address(ghoToken), address(ccipRouter));

        sender.initialize();

        vm.expectRevert(Initializable.InvalidInitialization.selector);
        sender.initialize();
    }

    function test_Fuzz_InitializeUnchained() public {
        sender = new MockCCIPSender(address(ghoToken), address(ccipRouter));

        sender.initializeUnchained();

        vm.expectRevert(Initializable.InvalidInitialization.selector);
        sender.initializeUnchained();
    }

    function test_Fuzz_BadInitialize() public {
        sender = new MockCCIPSender(address(ghoToken), address(ccipRouter));

        vm.expectRevert(Initializable.NotInitializing.selector);
        sender.badInitialize();
    }
}

contract MockCCIPSender is CCIPSenderUpgradeable {
    constructor(
        address ghoToken,
        address ccipRouter
    ) CCIPSenderUpgradeable(ghoToken) CCIPBaseUpgradeable(ccipRouter) {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    function initialize() public initializer {
        __CCIPSender_init();
    }

    function initializeUnchained() public initializer {
        __CCIPSender_init_unchained();
    }

    function badInitialize() public {
        __CCIPSender_init();
    }

    function ccipSendTo(
        uint64 destChainSelector,
        bytes memory receiver,
        Client.EVMTokenAmount[] memory tokenAmounts,
        bool payInLink,
        uint256 maxFee,
        uint32 gasLimit,
        bytes memory data,
        bytes calldata extraArgs
    ) external payable returns (bytes32) {
        return
            _ccipSendTo(
                destChainSelector,
                msg.sender,
                receiver,
                tokenAmounts,
                payInLink,
                maxFee,
                gasLimit,
                data,
                extraArgs
            );
    }

    // Force foundry to ignore this contract from coverage
    function test() public pure {}
}
