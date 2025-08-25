# Smart Contract Audit Report for `olas-lst` 

- **Repository:** `github.com/kupermind/olas-lst`  
- **Branch/Commit:** HEAD `main` (`a23db47`)  
- **Scope:** only code under `contracts/`. Deployment/scripts/environment configuration are out of scope, except where configuration directly impacts protocol correctness.  
- **Tests:** for context, the integration test `test/LiquidStaking.js` was considered; 

## Executive Summary

The contracts implement an OLAS liquid staking model with cross-chain (L1/L2) interaction and a separation of responsibilities between `stOLAS` (ERC4626-like vault), `Depository`, `Treasury`, L2 contracts (`Collector`, `StakingManager`, etc.), and service modules (bridge processors, `UnstakeRelayer`).

For the audited commit, the architecture is coherent; **no critical logic bugs** were identified within the agreed scope. Below are items that require operational attention (initialization, invariants, configuration checklists), UX-level considerations, and strengths of the current implementation.

---

## Important Notes and Recommendations

### 1) Withdrawal path configuration dependency (L2 → L1) — **Important**

**What this is.** Payments in `Treasury.finalizeWithdrawRequests()` are executed **from `Treasury`’s balance**, not `stOLAS`. If `redeem()` lacks sufficient `vault+reserve` liquidity, the shortfall is covered by `unstake` on L2 and bridging back to L1. Therefore, **the L2 → L1 routing must be configured such that the `UNSTAKE` operation directs OLAS to `Treasury`**, otherwise withdraw tickets (ERC6909) may “hang” due to insufficient `Treasury` funds at finalization time.

**Status.** This is **not a code defect**; it is a **potential initialization/configuration pitfall**. The current design already exposes events and methods to validate configuration:

- On L2 `Collector`: `setOperationReceivers()` + event `OperationReceiversSet(bytes32[] operations, address[] receivers)` (captures current routing).  
- On L1 `Treasury`: `WithdrawRequestInitiated / WithdrawRequestExecuted` (observability of requests and payouts).  
- On L1 `Depository`: `Unstake / Retired` (observability of unstake initiation).

**Developer checklist (initialization):**  
- Ensure `Collector.setOperationReceivers()` is invoked with:  
  - `REWARD → Distributor (L1)`  
  - `UNSTAKE → Treasury (L1)`  
  ̵-̵ ̵`̵U̵N̵S̵T̵A̵K̵E̵_̵R̵E̵T̵I̵R̵E̵D̵ ̵→̵ ̵U̵n̵s̵t̵a̵k̵e̵R̵e̵l̵a̵y̵e̵r̵ ̵(̵L̵1̵)̵`  (moved to note below)  
  The `bytes32` values for `UNSTAKE` must **match** the constants in `Depository.sol` (same hashes).

**Note.** For `UNSTAKE_RETIRED`, tokens arrive at `UnstakeRelayer`, then are reflected in `stOLAS` via `topUpRetiredBalance()` (vault-side reserve accounting). This separate path does **not** interfere with ticket finalization in `Treasury` provided `UNSTAKE → Treasury` is configured correctly.

- Include an automated preflight (off-chain/script): read back the current receivers and compare to expected; abort if they differ.
- Operational monitoring: subscribe to `OperationReceiversSet` and `TokensRelayed` on L2, and to `WithdrawRequest*` on L1; alert on volume mismatches and delays in `UNSTAKE` inflows to `Treasury`.

[x] Noted, static audit is required and is already planned


---

### 2) ERC4626: **non-standard** entrypoints — **Medium**

**What this is.** In `stOLAS`:
- `deposit()` is callable **only** by `Depository`;  
- `redeem()` is callable **only** by `Treasury`;  
- `mint()` and `withdraw()` are overridden and return `0` (instead of reverting or performing the usual ERC4626 behavior).

This is an intentional design to centralize flow control. **However**, it diverges from typical ERC4626 expectations. External integrators unaware of this may misinterpret a `0` return value.

**Procedural recommendations:**
- Document in README/API that only `deposit` (via `Depository`) and `redeem` (via `Treasury`) are meant to be used; `mint/withdraw` are **non-standard** and not for external use.
- Reflect the same model in SDKs/integration tests to prevent accidental misuse by apps/aggregators.

[x] Fixed


---

### 3) Trust model `Depository → stOLAS` and invariants — **Medium**

**What this is.** `stOLAS` keeps **internal** reserve accounting:  
`totalReserves = stakedBalance + vaultBalance + reserveBalance`.  
`syncStakeBalances(reserveAmount, stakeAmount, topUp, direction)` is callable **only** by `Depository` and:
- updates accounting fields without necessarily moving assets for `reserveAmount/stakeAmount`;
- moves assets **only** for `topUp` (into `stOLAS` if `direction=true` via `transferFrom`, or back to `Depository` if `direction=false`).

Consequently, `Depository` is a trusted party; correctness of its parameters is crucial to keep `stOLAS` accounting aligned with real OLAS placements.

**Key invariants that must hold operationally:**
- After any operation:  
  `totalReserves == stakedBalance + vaultBalance + reserveBalance` (internal contract invariant).
- For `direction=true`: the `topUp` amount must match the **actual** `transferFrom(Depository → stOLAS)` (so vault token balance covers the stated increase in reserves).
- For `direction=false`: `stOLAS` must actually transfer `topUp` back to `Depository` (transfer + decrease of `totalReserves`/corresponding fields).
- Periodic off-chain reconciliation: compare `balanceOf(OLAS, stOLAS) + balanceOf(OLAS, Treasury) + ...` against aggregated reserves by storage roles (as part of operational monitoring).

**Risks.** Incorrect `syncStakeBalances` parameters could **distort `pps`** (price-per-share) by desynchronizing internal accounting and real assets. Within the current trust model, this is acceptable but requires discipline and monitoring.

[x] Noted, static audit is required and is already planned


---

### 4) Safety of asset transfers (OLAS) — **Low**

**What this is.** The code uses raw `ERC20.transfer / transferFrom`. Reentrancy/side-effect risks are typically discussed for **non-standard** tokens (rebasing, fee-on-transfer, hooks).

**Project context.** The asset is **OLAS**, which in this setup is a **standard ERC-20** (no fee/rebase/hooks). Under this assumption, the concern is theoretical and only relevant if the asset changes in the future.

**Procedural recommendations:**
- State explicitly in documentation that the asset must be a **plain** ERC-20 without transfer side effects.
- If the asset is ever replaced, run a mini-compatibility audit (hooks, fee-on-transfer, rebase, etc.).

[x] Noted, the OLAS token is verified


---

### 5) Initialization and upgrades — **Medium**

**What this is.** Many contracts inherit `Implementation` (owner, implementation changes via proxy slots). The mechanism is flexible but requires process controls:

- Clearly list which contracts are actually **behind proxies** and which are **immutable** (where implementation change is inapplicable).
- Operationally, the plan is for **`owner` to be a multisig**, and after the governance token is deployed, authority transfers to a **timelock**. This is an expected operational model (not a code issue), but it must be **executed in practice** and captured in a rollout checklist.

**Procedural recommendations:**
- Adopt a “two-check” upgrade procedure: off-chain state-migration plan + on-chain rehearsal (e.g., fork network) before broadcasting.
- Publish a table: `contract → type (proxy/immutable), current owner / post-DAO owner, timelock parameters`.

[x] Noted, the table will be added during contract deployments


---

### 6) Edge cases and UX — **Low/Medium**

**What this is.**
- Iteration over arrays (e.g., `Treasury.finalizeWithdrawRequests(requestIds, amounts)`) can be gas-heavy for large batches. Function signatures do not enforce array length limits—this is left to the caller.
- Certain `preview*` and “estimation” functions rely on internal accounting rather than raw balances, which is correct for this design but may surprise integrators.
- Non-standard ERC4626 entrypoints (see §2) are also relevant for UX.

**Procedural recommendations:**
- Establish max batch sizes off-chain; have the UI/SDK split large operations into safe chunks.
- Explicitly document in README that `pps` and calculations derive from **internal reserves** (`totalReserves`), not from raw token balances.
- Maintain a minimal monitoring dashboard (key metrics: component breakdown of `totalReserves`, outstanding withdraw tickets, `UNSTAKE` inflows to `Treasury`).

[x] Noted for UX


---

## Invariants Currently Satisfied

- **`pps` is immune to external donations.** Price-per-share is based on **internal** accounting (`totalReserves`), not on the vault’s `balanceOf`; unsolicited donations to the contract cannot skew `pps`.
- **State update order in `redeem()`.** Accounting (`staked/vault/reserve/totalReserves`) is updated first, then the transfer occurs—this order is safe.
- **Reentrancy guards** are present in sensitive entrypoints (`Treasury`, bridge processors, etc.).
- **Zero-dust protection.** Calculations (ERC4626 math) include checks/constraints that prevent rounding “dust” issues.
- **Event coverage.** Most critical actions emit events (`OperationReceiversSet`, `WithdrawRequest*`, `Deposit/Unstake/Retired`, `TotalReservesUpdated`, etc.), aiding traceability.

[x] Noted


---

## Appendices

- Detailed report on **dangling events** and **unnamed `revert()`** occurrences (separate artifact):  
  **`audit6-dangling-events-and-unnamed-reverts.md`** — lists events declared but never emitted and locations with `revert();` (without custom errors), with file paths and approximate line numbers.

---

## Methodology

- Manual review of all `contracts/` files for commit `a23db47`.
- Specific checks for events/`revert` performed with a static scanning script on the provided snapshot (see appendix).
- Test logic and deployment were not audited, except for configuration aspects that affect protocol correctness.

---

### Disclaimer

This report is not a formal security certification.
Any changes to code or environment require re-evaluation. 
Operational reliability depends on correct configuration (especially §1) and disciplined initialization/upgrade procedures.
