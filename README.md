# ChainLink Custom Sender-Receiver (GHO / sGHO)

A set of smart contracts that let users swap **GHO** for **sGHO** (and back) on a deployed chain at an exchange rate provided by a Chainlink oracle, while keeping the local liquidity pool rebalanced across chains using [Chainlink CCIP](https://docs.chain.link/ccip).

Users interact with a [`SwapHandler`](contracts/senders/SwapHandler.sol) on the deployed chain:

- `deposit` swaps `GHO` → `sGHO` through a local [`OraclePool`](contracts/utils/OraclePool.sol).
- `redeem` swaps `sGHO` → `GHO` through the same pool.

Both swaps are instant and settled from the pool's inventory at the oracle rate (with an optional fee). To keep the pool solvent, an operator periodically calls `sync`, which moves accumulated inventory to Ethereum mainnet so it can be processed and the pool refilled.

## How it works

### Swapping (deposit / redeem)

`deposit` and `redeem` on the `SwapHandler` pull the user's tokens, forward them to the `OraclePool`, and send the swapped tokens straight back to the user. The pool prices the swap using an exchange-rate oracle (`sGHO` priced in `GHO`) and can apply a configurable fee that stays in the pool. Swaps succeed only while the pool holds enough of the output token; otherwise they revert (see the [FAQ](#frequently-asked-questions--troubleshooting)).

### Rebalancing (sync)

As users swap, the pool's balance of one token grows while the other shrinks. An account holding the `SYNC_ROLE` calls `sync(token, amount, …)` on the `SwapHandler`, which pulls `amount` of `token` (`GHO` or `sGHO`) from the pool and bridges it to a receiver on **Ethereum mainnet** via CCIP. The mainnet receiver is the **Chainlink Cross-Chain Vault solution**, which is maintained in a separate repository and is therefore out of scope for this repo; it processes the synced tokens and returns value so the pool can be refilled.

The CCIP destination is fixed to Ethereum mainnet, and the CCIP fee is paid by the caller (in the GHO fee token or in native token, as encoded in `feeData`). Any excess native value is refunded to the caller.

## Key contracts

[`contracts/senders/SwapHandler.sol`](contracts/senders/SwapHandler.sol): The main user-facing contract. Implements `deposit` (GHO→sGHO) and `redeem` (sGHO→GHO) against the local `OraclePool`, and `sync` to rebalance the pool by bridging inventory to the mainnet vault via CCIP. Holds the oracle pool and vault addresses using [EIP-7201](https://eips.ethereum.org/EIPS/eip-7201) namespaced storage, and can be deployed directly or behind a proxy.

[`contracts/senders/SwapHandlerReferral.sol`](contracts/senders/SwapHandlerReferral.sol): Extends `SwapHandler` with `depositReferral`, which behaves like `deposit` but additionally emits a `Referral` event for off-chain attribution.

[`contracts/utils/OraclePool.sol`](contracts/utils/OraclePool.sol): Swaps `GHO` for `sGHO` (and vice versa) using an exchange-rate oracle, with an optional swap fee. Only the configured `SENDER` (the `SwapHandler`) may call the swap and `pull` functions; the owner may `sweep` tokens and update the oracle/fee. Not compatible with fee-on-transfer tokens.

[`contracts/utils/PausableImmutableOraclePool.sol`](contracts/utils/PausableImmutableOraclePool.sol): An `OraclePool` variant whose oracle and fee are immutable after deployment, and whose `deposit`, `redeem`, and `pull` can be paused/unpaused by the owner.

[`contracts/utils/PriceOracle.sol`](contracts/utils/PriceOracle.sol): Wraps a Chainlink aggregator and returns the price scaled to 1e18, with optional inversion and a heartbeat-based staleness check.

[`contracts/ccip`](contracts/ccip): Base contracts implementing the CCIP sending logic used by the `SwapHandler` (router wiring, fee handling, and trusted per-chain receivers).

[`contracts/adapters/BridgeAdapter.sol`](contracts/adapters/BridgeAdapter.sol): Abstract base for bridge adapters that are delegate-called to move tokens across chains. The `IBridgeAdapter` interface defines events for CCIP and the supported native bridges (Base, Optimism, Arbitrum, Frax Ferry, Linea); a concrete adapter implements `_sendToken` for a specific bridge. Adapters must not use storage to avoid collisions with their delegator.

[`contracts/libraries/FeeCodec.sol`](contracts/libraries/FeeCodec.sol): Encode/decode helpers for the bridge fee data (e.g. `encodeCCIP`, `encodeArbitrumL1toL2`, `encodeOptimismL1toL2`, `encodeBaseL1toL2`, `encodeFraxFerryL1toL2`, `encodeLineaL1toL2`).

[`contracts/libraries/TokenHelper.sol`](contracts/libraries/TokenHelper.sol): Helpers for transferring ERC20 and native tokens and refunding excess native value.

## Roles and access control

- **`SwapHandler` `DEFAULT_ADMIN_ROLE`** — set at initialization (`initialAdmin`). Can call `setOraclePool` and `setVault`, and manage roles.
- **`SwapHandler` `SYNC_ROLE`** — may call `sync`. Grant this to the operator or automation account that rebalances the pool.
- **`OraclePool` `SENDER`** — the `SwapHandler`; the only account allowed to call `deposit`, `redeem`, and `pull` on the pool.
- **`OraclePool` owner** — can `sweep` tokens and (on the mutable pool) update the oracle and fee.

## Key parameters for deployment

### `SwapHandler` / `SwapHandlerReferral`

- `sghoToken`: The `sGHO` token address on the deployed chain.
- `ghoToken`: The `GHO` token address on the deployed chain (also used as the CCIP fee token).
- `ccipRouter`: The CCIP router address on the deployed chain.
- `oraclePool`: The `OraclePool` address (use `0x0` to deploy without swaps enabled; it can be set later via `setOraclePool`).
- `vault`: The mainnet receiver (Chainlink Cross-Chain Vault) that `sync` bridges to. Must be non-zero.
- `initialAdmin`: The address granted the `DEFAULT_ADMIN_ROLE`.

### `OraclePool` / `PausableImmutableOraclePool`

- `sender`: The `SwapHandler` allowed to drive swaps and pulls.
- `gho` / `sgho`: The `GHO` and `sGHO` token addresses.
- `oracle`: The exchange-rate oracle (a `PriceOracle`/`PriceConverterOracle`). For `PausableImmutableOraclePool` this must be non-zero.
- `fee`: The swap fee applied to each swap, in 1e18 scale (e.g. `1e16` = 1%). Must be `<= 1e18`.
- `initialOwner`: The pool owner.

### `PriceOracle`

- `aggregator`: The Chainlink aggregator address. `DECIMALS` is read from it directly.
- `isInverse`: `true` if the price should be reported as `1 / price`.
- `heartbeat`: Seconds after which the aggregator's answer is considered stale.

## Fees (sync via CCIP)

`sync` bridges to Ethereum mainnet using CCIP. The fee data passed to `sync` is built with `FeeCodec.encodeCCIP(maxFee, payInLink, gasLimit)`:

- `maxFee`: The maximum CCIP fee the caller is willing to pay. Estimate it with `getFee()` on the CCIP router and add a small buffer; any excess is refunded.
- `payInLink` / fee token: Whether the CCIP fee is paid in the GHO fee token or native token.
- `gasLimit`: The gas for processing the message on the destination chain. Must be at least `MIN_PROCESS_MESSAGE_GAS` (75,000).

Front-ends and operators should use the same encoding (e.g. via JS) when constructing `feeData`.

## Frequently asked questions / troubleshooting

### Protocol operators

**What routine maintenance is required?**
Keep the `SYNC_ROLE` account funded with enough of the CCIP fee token (GHO or native) to pay for periodic `sync` bridging, and monitor the pool's balances so it stays able to honor swaps.

**How is `sync` triggered?**
By any account holding the `SYNC_ROLE`, either manually or via an off-chain automation that holds the role. (This repo no longer ships an on-chain automation contract; automation, if used, lives off-chain or in a separate component.)

### Front-end operators

**Where do we get the exchange rate shown to users?**
Read the swap rate from the configured oracle (the [`PriceOracle`](contracts/utils/PriceOracle.sol) used by the pool). Account for the pool fee and, if the CCIP fee is paid in native token rather than the GHO fee token, surface that separately.

**What do we pass as `minAmountOut`?**
It is the minimum output you will accept for the swap. For a `deposit`, output ≈ `exactAmountIn * (1e18 - oraclePoolFee) / oraclePrice`. Apply a small slippage buffer to allow for the oracle rate updating between quoting and execution.

**The pool didn't have enough output token — what error is returned?**
The pool reverts with `OraclePoolInsufficientTokenOut` when its balance of the output token is insufficient to complete the swap. Front-ends can pre-check by querying the pool's token balances.

**What does `OraclePoolInvalidPrice` mean?**
The oracle reported a price lower than the previously recorded price. The pool rejects this to guard against a decreasing exchange rate; the system should be paused/investigated for that deployment when it occurs.

**Notes for front-ends**
Use the proxy address of the `SwapHandler` (not the implementation) when integrating.

## Usage

This repository uses **yarn** for package management and **Foundry** for smart contract development. Solidity scripting helpers live in [`script/ScriptHelper.sol`](script/ScriptHelper.sol).

### Off-chain library

For TypeScript utilities and off-chain tooling, see the **[Offchain README](offchain/README.md)**.

### Environment setup

First, install dependencies:

```shell
yarn install
```

Then copy the example environment file and fill in the values (RPC URLs, explorer keys, deployer keys):

```shell
cp .env.example .env
```

Supported networks in `.env.example`: Ethereum, Arbitrum, Optimism, Base, and Linea.

### Build

```shell
yarn build
```

### Test

```shell
yarn test
```

### Deploy

Deploy with `forge script` against your deployment script:

```shell
forge script --broadcast --verify --multi <path-to-script>
```

If a deployment fails partway, resume from the last failed transaction:

```shell
forge script --broadcast --verify --multi --resume <path-to-script>
```

## Foundry documentation

https://book.getfoundry.sh/
