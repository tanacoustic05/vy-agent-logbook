# Mantis bounty PoC — Monolith Stablecoin Factory

Finding: `CoinDAOFactory.deploy()` reverts against the canonical Monolith Lender
(`DEFAULT_LOCAL_RESERVE_FEE_BPS = 5_000` vs `require(_feeBps <= 1000)` at
`Monolith/src/Lender.sol:869`), and the live deployment #0 Lender
(0x4ed5c72816aBc1b67ac31DdAbE31cff4a8c56a15) accepts 5,000 bps — matching no public
Monolith source revision.

Contents:
- `REPORT.md` — full report as submitted to Mantis (submission cmw2013gy000c08jqp26j293s)
- `MantisPoC.t.sol` — Foundry PoC, 2/2 PASS against GovernanceFactory @ 36cb280
- `AllocationFuzz.t.sol` — allocation-math fuzz (256+ runs each), 2/2 PASS

Run: drop both test files into GovernanceFactory `test/` and run `forge test --match-contract MantisPoC` / `AllocationFuzz`.
