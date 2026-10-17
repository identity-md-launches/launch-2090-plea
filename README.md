# plea (PLEA)

`PleaToken` is a fixed-supply ERC-20. Its constructor mints exactly **1,000,000,000 PLEA** to the immediate deployer, once. It has no administrative roles or post-deployment minting.

| Property | Value |
| --- | --- |
| Source / contract identifier | `src/PleaToken.sol:PleaToken` |
| Token name | `plea` |
| Token symbol | `PLEA` |
| Decimals | `18` |
| Supply in smallest units | `1000000000000000000000000000` (`10^27`) |
| Constructor arguments | None (`[]`) |
| Initial recipient | Constructor `msg.sender` |
| Deployment transaction value | `0` |
| Intended launch chain | Ethereum, chain ID `1` |

## Behavior and assumptions

The implementation inherits the vendored OpenZeppelin ERC-20, without overriding transfers, approvals, or decimal handling. The only added logic is the constructor mint and the public `INITIAL_SUPPLY` constant.

- `transfer`, `approve`, and `transferFrom` return `true` on success and revert with ERC-6093 custom errors on failure.
- Transfers deliver the exact amount. There are no taxes, fees, rebases, transfer hooks, limits, exemptions, or trading activation steps.
- Zero-value transfers and self-transfers are supported. Transfers to the zero address and approvals to the zero address revert, including for zero amounts.
- `approve` replaces the caller's allowance for a spender. A finite allowance decreases on `transferFrom`; `type(uint256).max` is an unlimited allowance and is not decreased. Even a holder calling `transferFrom` on its own balance needs an allowance.
- The constructor emits one `Transfer` from the zero address. Transfers emit `Transfer`; explicit approvals emit `Approval`. OpenZeppelin v5 does not emit another `Approval` when `transferFrom` spends an allowance.
- The token exposes no mint, burn, pause, blacklist, seizure, owner, upgrade, permit, or asset-recovery functions. Supply remains constant after construction. No recipient callbacks or other external contract calls occur.

The deployer is the **immediate creator**, including a factory using CREATE or CREATE2. The transaction origin and the wallet calling that factory receive no allocation in the constructor. The factory receives the entire supply and handles subsequent launch distribution and liquidity. This contract does not encode launch wallets or pool configuration.

## Build and test

Run from this repository's root with Foundry and Solidity **0.8.26** available:

```sh
forge build
FOUNDRY_FUZZ_SEED=0xa37391da2716e10cb5a391291338e7929f26d24b70d32b2ffcd8933d9e88f876 forge test
forge fmt --check
```

`foundry.toml` pins Solidity 0.8.26, the Cancun EVM target, optimizer settings (200 runs), and `bytecode_hash = "none"`. All Solidity dependencies are ordinary files under `lib/`; building needs no dependency downloads or submodules. An offline worker must already have Foundry and the pinned compiler installed. FFI and filesystem cheatcode permissions are not enabled.

Tests cover metadata, the exact supply and mint event, full/zero/self transfers, approvals and revocation, delegated transfers, allowance isolation, unlimited approvals, invalid addresses, insufficient balances and allowances, and atomic failure behavior. They also probe absent mint/burn/admin functions and inspect the runtime for forbidden opcodes.

Factory tests cover immediate-creator allocation, CREATE2 prediction, and exact transfer amounts for the launch's 10% distributor / 10% pool / 80% remainder distribution, claims, and transfers in both directions with a pool counterparty. These fixtures model token transfer legs; they do not implement Uniswap pricing or settlement.

Six fuzz tests run 1,024 cases each. Two stateful invariants run 128 sequences of 64 calls each, mixing transfers, approvals, delegated transfers, and attempted overspending among four actors. They check fixed supply, conservation of balances, exact amounts, and allowance authorization. Tests use local fixtures with deterministic test addresses and require no RPC, fork, environment reads, keys, or shared mutable state.

The supplied protected checks were reviewed. Their complete launch harness, Uniswap contracts, and manifest-resolved deployment inputs are not part of this repository; those end-to-end admission checks remain the launch verifier's responsibility. Local tests do not claim to replace them.

## Deployment and operational responsibilities

Deploy the creation bytecode for `PleaToken` with **no constructor arguments** and no attached ETH. There is no initialization transaction, constructor address to configure, external dependency to initialize, or linked library to deploy. The token itself is chain-agnostic; the launch operator selects the intended chain and deploying factory.

Before launch, the operator should reproduce the build, check the artifact and supply above, and run the protected factory/pool admission tests against the final bytecode and launch configuration. The network's separate manifest step supplies `launch.json`; this project intentionally does not include one. No deployment or broadcast is performed by this project.

### After launch

- There are no owner-only settings or ongoing administrative duties. The launch factory must distribute its initial supply according to the accepted launch configuration.
- The launch operator should verify the deployed source and bytecode, confirm the constructor mint event and total supply, and confirm the factory's final allocations and liquidity operations.
- Holders control their balances and allowances. Use bounded approvals where practical; when replacing an existing allowance, first revoke it and confirm the revocation before setting a new one. An approved spender can spend within its allowance until revocation takes effect.
- Transfers are irreversible. The token has no recovery mechanism for tokens sent to an incorrect address or assets sent to the token contract. No administrator can correct a holder's balance or upgrade the contract.

Local validation consists of `forge build`, `forge test`, and `forge fmt --check`, including the requested fuzz seed. Slither and Mythril were not run. This implementation and its tests are not an independent security audit; the separate contributor review remains part of the release process.

Dependency versions, provenance, and licenses are documented in [DEPENDENCIES.md](DEPENDENCIES.md).
