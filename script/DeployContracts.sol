// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import {CustomSender} from "../contracts/senders/CustomSender.sol";
import {OraclePool} from "../contracts/utils/OraclePool.sol";
import {ScriptHelper} from "./ScriptHelper.sol";

/**
 * @title DeployContracts
 * @dev Deploys an OraclePool, the CustomSender implementation, and a TransparentUpgradeableProxy that is
 * initialized in the same transaction as its deployment.
 *
 * Atomic deploy-and-initialize is a hard invariant. `CustomSender.initialize` is publicly callable and
 * authenticates nothing about its caller. If a proxy is deployed without being initialized in the same
 * transaction, an attacker can front-run the deployer's initialize call and seize `DEFAULT_ADMIN_ROLE`. The
 * proxy is therefore deployed with `abi.encodeCall(CustomSender.initialize, ...)` as its constructor data
 * argument so initialization happens atomically.
 *
 * `config.admin` is used both as the owner of the auto-deployed `ProxyAdmin` (i.e. the address authorized to
 * upgrade the proxy) and as the `DEFAULT_ADMIN_ROLE` holder on the proxy's CustomSender storage.
 *
 * The same pattern applies to `CustomSenderReferral`; duplicate this script for that variant.
 */
contract DeployContracts is ScriptHelper {
    error DeployContractsProxyAddressMismatch(
        address predicted,
        address actual
    );

    struct DeployConfig {
        address gho;
        address sgho;
        address ccipRouter;
        address priceOracle;
        uint96 oraclePoolFee;
        address oraclePoolOwner;
        address vault;
        address admin;
    }

    function run() external returns (address proxy, address oraclePool) {
        DeployConfig memory config = DeployConfig({
            gho: vm.envAddress("GHO"),
            sgho: vm.envAddress("SGHO"),
            ccipRouter: vm.envAddress("CCIP_ROUTER"),
            priceOracle: vm.envAddress("PRICE_ORACLE"),
            oraclePoolFee: uint96(vm.envUint("ORACLE_POOL_FEE")),
            oraclePoolOwner: vm.envAddress("ORACLE_POOL_OWNER"),
            vault: vm.envAddress("VAULT"),
            admin: vm.envAddress("ADMIN")
        });

        uint256 deployerKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address deployer = vm.addr(deployerKey);

        vm.startBroadcast(deployerKey);
        (proxy, oraclePool) = deploy(deployer, config);
        vm.stopBroadcast();
    }

    function deploy(
        address deployer,
        DeployConfig memory config
    ) public returns (address, address) {
        // OraclePool's SENDER is immutable and must equal the proxy address. We predict the proxy address
        // from `deployer`'s nonce: the three sequential CREATEs land at nonces N (OraclePool), N+1 (impl),
        // N+2 (proxy). Under `vm.startBroadcast(...)`, `deployer` is the broadcaster. When invoked directly
        // from a test, pass the script contract's own address as `deployer`.
        address predictedProxy = _predictContractAddress(deployer, 2);

        address oraclePool = address(
            new OraclePool(
                predictedProxy,
                config.gho,
                config.sgho,
                config.priceOracle,
                config.oraclePoolFee,
                config.oraclePoolOwner
            )
        );

        CustomSender impl = new CustomSender(
            config.sgho,
            config.gho,
            config.ccipRouter,
            oraclePool,
            config.vault,
            config.admin
        );

        address proxy = address(
            new TransparentUpgradeableProxy(
                address(impl),
                config.admin,
                abi.encodeCall(
                    CustomSender.initialize,
                    (oraclePool, config.vault, config.admin)
                )
            )
        );

        require(
            proxy == predictedProxy,
            DeployContractsProxyAddressMismatch(predictedProxy, proxy)
        );

        return (proxy, oraclePool);
    }
}
