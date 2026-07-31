// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {ERC1967Utils} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Utils.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";

import {DeployContracts} from "../../script/DeployContracts.sol";
import {CustomSender} from "../../contracts/senders/CustomSender.sol";
import {OraclePool} from "../../contracts/utils/OraclePool.sol";
import {PriceOracle} from "../../contracts/utils/PriceOracle.sol";

import {MockERC20} from "../mocks/MockERC20.sol";
import {MockCCIPRouter} from "../mocks/MockCCIPRouter.sol";
import {MockDataFeed} from "../mocks/MockDataFeed.sol";

contract DeployContractsTest is Test {
    DeployContracts public script;
    MockERC20 public gho;
    MockERC20 public sgho;
    MockCCIPRouter public ccipRouter;
    MockDataFeed public dataFeed;
    PriceOracle public priceOracle;

    address public admin = makeAddr("admin");
    address public vault = makeAddr("vault");

    function setUp() public {
        gho = new MockERC20("GHO", "GHO", 18);
        sgho = new MockERC20("sGHO", "sGHO", 18);
        ccipRouter = new MockCCIPRouter(address(gho), 1e18, 0.01e18);
        dataFeed = new MockDataFeed(18);
        priceOracle = new PriceOracle(address(dataFeed), false, 1 hours);
        script = new DeployContracts();

        dataFeed.set(int256(1e18), 1, block.timestamp, block.timestamp, 1);
    }

    function test_DeployInitializesAtomically() public {
        DeployContracts.DeployConfig memory config = _config();

        (address proxy, address oraclePool) = script.deploy(
            address(script),
            config
        );

        // Atomic-init guarantee: a follow-up `initialize` call must revert, proving that initialization
        // happened in the same transaction as proxy deployment (no window for a front-runner).
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        CustomSender(proxy).initialize(oraclePool, vault, admin);

        bytes32 adminRole = CustomSender(proxy).DEFAULT_ADMIN_ROLE();

        // Configured admin (and only that admin) holds DEFAULT_ADMIN_ROLE on the proxy.
        assertTrue(
            CustomSender(proxy).hasRole(adminRole, admin),
            "test_DeployInitializesAtomically::1"
        );
        assertFalse(
            CustomSender(proxy).hasRole(adminRole, address(script)),
            "test_DeployInitializesAtomically::2"
        );
        assertFalse(
            CustomSender(proxy).hasRole(adminRole, address(this)),
            "test_DeployInitializesAtomically::3"
        );

        // OraclePool's immutable SENDER matches the proxy and the proxy's oraclePool storage points back.
        assertEq(
            OraclePool(oraclePool).SENDER(),
            proxy,
            "test_DeployInitializesAtomically::4"
        );
        assertEq(
            CustomSender(proxy).getOraclePool(),
            oraclePool,
            "test_DeployInitializesAtomically::5"
        );

        // Vault is set on proxy storage.
        assertEq(
            CustomSender(proxy).getVault(),
            vault,
            "test_DeployInitializesAtomically::6"
        );

        // Approvals from _setOraclePool ran against the proxy's storage, not the impl's.
        assertEq(
            gho.allowance(proxy, oraclePool),
            type(uint256).max,
            "test_DeployInitializesAtomically::7"
        );
        assertEq(
            sgho.allowance(proxy, oraclePool),
            type(uint256).max,
            "test_DeployInitializesAtomically::8"
        );

        // ProxyAdmin was auto-deployed and is owned by `config.admin`.
        address proxyAdmin = address(
            uint160(uint256(vm.load(proxy, ERC1967Utils.ADMIN_SLOT)))
        );
        assertEq(
            ProxyAdmin(proxyAdmin).owner(),
            admin,
            "test_DeployInitializesAtomically::9"
        );
    }

    function _config()
        internal
        view
        returns (DeployContracts.DeployConfig memory)
    {
        return
            DeployContracts.DeployConfig({
                gho: address(gho),
                sgho: address(sgho),
                ccipRouter: address(ccipRouter),
                priceOracle: address(priceOracle),
                oraclePoolFee: 0,
                oraclePoolOwner: admin,
                maxYearlyGrowthBps: 425,
                vault: vault,
                admin: admin
            });
    }
}
