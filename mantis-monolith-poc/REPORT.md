## Summary

`CoinDAOFactory.deploy()` (GovernanceFactory repo) always reverts when composed with the canonical Monolith repo Lender, because it unconditionally applies a 5,000 bps local reserve fee while **every public revision of the Monolith Lender caps `setLocalReserveFeeBps` at 1,000 bps** (`require(_feeBps <= 1000, "Invalid fee")` — `src/Lender.sol:869` at repo main `3511ab5`; also `fd6c7ed:720`, `3d63d25:720`, `b1d3e4e:781`). The two public repos cannot be integrated as published, and the mock in the GovernanceFactory test suite (`test/mocks/MockMonolith.sol:62` allows `<= 5_000`) masks the divergence so the suite stays green.

On-chain evidence (measured Nov 4–5, 2026, via eth.drpc.org):
- Deployment #0 Lender `0x4ed5c72816aBc1b67ac31DdAbE31cff4a8c56a15` (deployed by Monolith Factory `0xc68F...f931` through the CoinDAOFactory flow): bytecode 19,400 bytes, `feeBps() == 5000`, and an `eth_call` simulation of `setLocalReserveFeeBps(5000)` from the operator **succeeds**.
- Lender `0xf8B3...49c9` (deployed by Monolith Factory `0x6D96...` per repo code): 19,162 bytes, reverts `"Invalid fee"` at 5,000 — matching repo main.
- No public branch of Monolith permits 5,000 bps (checked `main`, `unstablecoins` merge `fd6c7ed`, `3d63d25`, `b1d3e4e`, `1942497`).
- The RevenueRouter docstring in GovernanceFactory itself says the Lender "enforces its 5,000 bps cap" — the two repos contradict each other in their own documentation.

Impact:
1. **Integration break:** any integrator composing the two public repos as published cannot deploy a CoinDAO at all — `deploy()` reverts atomically after the Monolith market is created.
2. **Unaudited mainnet variant:** the live CoinDAO Lender is running a fee-cap/fee-tier code path that matches no public source; the variant handles 5% of all Coin revenue for that deployment. Bounty pages judge the published repos — the deployed Lender diverging from them is a transparency/audit-trail risk.

## PoC (Foundry, PASS)

`test/MantisPoC.t.sol` against GovernanceFactory @ `36cb280` (repo suite 84/84 green, plus 4 new tests, 88/88 total):

- `test_deployRevertsAgainstCanonicalLenderFeeCap` — a strict mock applying the canonical repo cap (1000) makes `factory.deploy(...)` revert at `setLocalReserveFeeBps(5000)` right after `monolithFactory.deploy()`.
- `test_mockAllows5000SoRepoSuiteMasksIt` — the same call against a mock with the shipped suite's 5,000 cap completes the full launch — proving the repo's own suite can never catch the divergence.

## Suggested fix

Either publish the Lender variant that enforces the 5,000 bps cap the CoinDAOFactory docstring references, or change `DEFAULT_LOCAL_RESERVE_FEE_BPS` to a value within the canonical cap (and fix `MockMonolith.sol` so the suite fails on divergence).

## Verification trail

- GovernanceFactory repo @ main (`36cb280`): `forge build` clean, 84/84 repo tests + 4/4 new PoC/fuzz tests pass.
- Fuzz (`test/AllocationFuzz.t.sol`, 256+ runs): allocation math conserves the fixed 10M GOV supply exactly (65:28 split, dust to treasury) — allocation math ruled out as a second finding.
- On-chain comparisons listed above; scope bytecode sizes for all GovernanceFactory contracts match repo builds byte-for-byte modulo linker immutables.
