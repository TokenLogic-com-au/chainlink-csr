// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import {SwapHandler} from "../contracts/senders/SwapHandler.sol";
import {OraclePool} from "../contracts/utils/OraclePool.sol";
import {ScriptHelper} from "./ScriptHelper.sol";

/**
 * @title DeployContracts
 * @dev Deploys an OraclePool, the SwapHandler implementation, and a TransparentUpgradeableProxy that is
 * initialized in the same transaction as its deployment.
 *
 * Atomic deploy-and-initialize is a hard invariant. `SwapHandler.initialize` is publicly callable and
 * authenticates nothing about its caller. If a proxy is deployed without being initialized in the same
 * transaction, an attacker can front-run the deployer's initialize call and seize `DEFAULT_ADMIN_ROLE`. The
 * proxy is therefore deployed with `abi.encodeCall(SwapHandler.initialize, ...)` as its constructor data
 * argument so initialization happens atomically.
 *
 * `config.admin` is used both as the owner of the auto-deployed `ProxyAdmin` (i.e. the address authorized to
 * upgrade the proxy) and as the `DEFAULT_ADMIN_ROLE` holder on the proxy's SwapHandler storage.
 *
 * The same pattern applies to `SwapHandlerReferral`; duplicate this script for that variant.
 */
contract DeployContracts is ScriptHelper {
    /**
     * @dev The deployed proxy did not land at the predicted address, so the `OraclePool`'s immutable `SENDER`
     * points at the wrong contract. The deployment is aborted rather than left in an unusable state.
     * @param predicted The proxy address the `OraclePool` was configured against.
     * @param actual The address the proxy was actually deployed to.
     */
    error DeployContractsProxyAddressMismatch(
        address predicted,
        address actual
    );

    /**
     * @dev The full set of parameters required to deploy an `OraclePool` and a proxied `SwapHandler`.
     * @param gho The address of the `GHO` token on the target chain (also the CCIP fee token).
     * @param sgho The address of the `sGHO` token on the target chain.
     * @param ccipRouter The address of the CCIP router on the target chain.
     * @param priceOracle The exchange-rate oracle the pool prices swaps with.
     * @param oraclePoolFee The pool's swap fee, in 1e18 scale. Must be `<= 1e18`.
     * @param oraclePoolOwner The address that may sweep tokens and update the pool's oracle, fee, and cap.
     * @param maxYearlyGrowthBps The maximum yearly growth of the pool's price cap, in basis points.
     * @param vault The mainnet receiver that `sync` bridges to.
     * @param admin The `DEFAULT_ADMIN_ROLE` holder on the proxy and the owner of its `ProxyAdmin`.
     */
    struct DeployConfig {
        address gho;
        address sgho;
        address ccipRouter;
        address priceOracle;
        uint96 oraclePoolFee;
        address oraclePoolOwner;
        uint16 maxYearlyGrowthBps;
        address vault;
        address admin;
    }

    /**
     * @dev Reads the deployment parameters from the environment and broadcasts the deployment.
     *
     * Requires `GHO`, `SGHO`, `CCIP_ROUTER`, `PRICE_ORACLE`, `ORACLE_POOL_FEE`, `ORACLE_POOL_OWNER`,
     * `MAX_YEARLY_GROWTH_BPS`, `VAULT`, `ADMIN`, and `DEPLOYER_PRIVATE_KEY` to be set.
     *
     * @return proxy The address of the deployed and initialized `SwapHandler` proxy.
     * @return oraclePool The address of the deployed `OraclePool`.
     */
    function run() external returns (address proxy, address oraclePool) {
        DeployConfig memory config = DeployConfig({
            gho: vm.envAddress("GHO"),
            sgho: vm.envAddress("SGHO"),
            ccipRouter: vm.envAddress("CCIP_ROUTER"),
            priceOracle: vm.envAddress("PRICE_ORACLE"),
            oraclePoolFee: uint96(vm.envUint("ORACLE_POOL_FEE")),
            oraclePoolOwner: vm.envAddress("ORACLE_POOL_OWNER"),
            maxYearlyGrowthBps: uint16(vm.envUint("MAX_YEARLY_GROWTH_BPS")),
            vault: vm.envAddress("VAULT"),
            admin: vm.envAddress("ADMIN")
        });

        uint256 deployerKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address deployer = vm.addr(deployerKey);

        vm.startBroadcast(deployerKey);
        (proxy, oraclePool) = deploy(deployer, config);
        vm.stopBroadcast();
    }

    /**
     * @dev Deploys the `OraclePool`, the `SwapHandler` implementation, and the proxy, in that order, and
     * initializes the proxy atomically with its deployment.
     *
     * Requirements:
     *
     * - `deployer` must be the account issuing the three `CREATE`s, and its next nonce must be the one the
     *   proxy address was predicted from. Reverts with {DeployContractsProxyAddressMismatch} otherwise.
     *
     * @param deployer The account whose nonce the proxy address is predicted from. Under
     * `vm.startBroadcast(...)` this is the broadcaster; when called directly from a test, pass the script
     * contract's own address.
     * @param config The deployment parameters.
     * @return The address of the deployed and initialized `SwapHandler` proxy.
     * @return The address of the deployed `OraclePool`.
     */
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
                config.oraclePoolOwner,
                config.maxYearlyGrowthBps
            )
        );

        SwapHandler impl = new SwapHandler(
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
                    SwapHandler.initialize,
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
