# `olas-lst` Architecture (Short Guide)

*Generated: 2025-08-20 11:47 UTC*  
*Scope: idealized funds flow based on the current contracts and the integration intent shown in `test/LiquidStaking.js`.*

This document summarizes the core components and **ideal funds paths** across L1/L2 as exercised by the integration test. It is meant to accompany `README.md` and serve as a quick reference for developers and auditors.

---

## Components

**L1 (Ethereum):**
- **`stOLAS`** — ERC4626-like vault for OLAS with **internal accounting** of reserves; only system modules call `deposit`/`redeem`.
- **`Depository`** — orchestrates staking/unstaking and keeps `stOLAS` accounting in sync (`syncStakeBalances`, `topUp*`).
- **`Treasury`** — issues and finalizes withdraw requests (tickets, ERC-6909) and pays out OLAS on finalization.
- **`Distributor`** — receives bridged rewards and allocates them (e.g., locks for veOLAS and/or tops up the vault).
- **`UnstakeRelayer`** — handles `UNSTAKE_RETIRED` returns; tops up `stOLAS` retired reserves.

**L2 (e.g., Gnosis):**
- **`StakingManager` / `StakingTokenLocked`** — staking logic for services, accrual of rewards, initiation of `UNSTAKE`.
- **`Collector`** — bridge egress: routes operations and tokens back to L1 (REWARD/UNSTAKE/UNSTAKE_RETIRED).

**Bridging Processors:**  
Default/Gnosis processors that encode/decode operations + ship OLAS across chains.

---

## Required Configuration (Happy Path)

On L2 `Collector` (performed once during initialization):  
```
setOperationReceivers(
  [REWARD, UNSTAKE, UNSTAKE_RETIRED],
  [Distributor (L1), Treasury (L1), UnstakeRelayer (L1)]
)
```
> The operation identifiers (`bytes32`) **must match** those used by L1 `Depository`/`Treasury`. The integration test follows this mapping; diverging from it may stall withdrawals.

---

## Funds Flow — Ideal Paths

### A) Deposit → Mint `stOLAS` Shares
1. **User** transfers OLAS into the system via **`Depository`** (the only authorized caller of `stOLAS.deposit()`).
2. **`Depository`** forwards OLAS to **`stOLAS`** (`topUpVaultBalance` / `syncStakeBalances(..., topUp=true, direction=true)`), which **mints shares** to the user (price-per-share = `totalReserves / totalSupply`).
3. Optionally, **`Depository`** moves OLAS to stake on **L2** and updates `stOLAS` accounting (`stakedBalance`, `vaultBalance`, `reserveBalance`).

### B) Rewards → Distributor (L1) → Vault / veOLAS
1. On **L2**, rewards accrue and are **bridged via `Collector`** with operation **`REWARD` → `Distributor (L1)`**.
2. **`Distributor`** allocates incoming OLAS per policy, e.g.:
   - Lock part into **`Lock`** (veOLAS mechanics), and
   - **Top up** the vault (**`stOLAS.topUpVaultBalance`**) to benefit all share holders.
3. **`stOLAS`** updates `totalReserves` accordingly; `pps` reflects the increased reserves.

### C) Withdraw Request → Unstake Shortfall → Finalize
1. **User** initiates a **withdraw request** at **`Treasury`** (a ticket is recorded per ERC-6909 semantics, subject to cooldown).
2. **`Treasury`** calls **`stOLAS.redeem()`** **up to available** `vault + reserve` balance.
3. If there is a **shortfall**, **`Depository`** triggers **`unstake`** on **L2**.
4. **L2 `Collector`** bridges returned OLAS with operation **`UNSTAKE` → `Treasury (L1)`**.
5. After cooldown, **`Treasury.finalizeWithdrawRequests()`** pays OLAS to the user and closes the ticket.

### D) Unstake of Retired Stakes → UnstakeRelayer → Vault
1. For **retired** positions, **L2 `Collector`** uses **`UNSTAKE_RETIRED` → `UnstakeRelayer (L1)`**.
2. **`UnstakeRelayer`** forwards OLAS into **`stOLAS.topUpRetiredBalance()`**.
3. **`stOLAS`** accounts this as **retired reserves**; it does **not** directly finalize Treasury tickets. (Normal withdrawals rely on **`UNSTAKE → Treasury`**.)

---

## Accounting & PPS

- `stOLAS` maintains:  
  `totalReserves = stakedBalance + vaultBalance + reserveBalance`  
- **Price-per-share**: `pps = totalReserves / totalSupply` (ERC4626 semantics).  
- Calculations use internal accounting; unsolicited OLAS transfers to the vault contract **do not** change `pps`.

**Entrypoints (non-standard ERC4626):**
- `deposit()` — **only** `Depository`
- `redeem()` — **only** `Treasury`
- `mint()` and `withdraw()` — not for external use

---

## Events to Monitor (Minimal Set)

- **L2 `Collector`**: `OperationReceiversSet`, `TokensRelayed`
- **L1 `Depository`**: `Deposit/Unstake/Retired`
- **L1 `Treasury`**: `WithdrawRequestInitiated`, `WithdrawRequestExecuted`
- **L1 `stOLAS`**: `TotalReservesUpdated`, `VaultBalanceTopUpped`, `ReserveBalanceTopUpped`

---

## Operational Checklist

- Verify `setOperationReceivers` mapping matches the **Required Configuration** above.
- Dashboard/alerts for:
  - `UNSTAKE` inflows to **`Treasury`** (timeliness vs outstanding tickets),
  - `totalReserves` breakdown and `pps`,
  - reward arrivals to **`Distributor`** and top-ups into **`stOLAS`**.

---

## Notes

- Asset token is assumed to be **standard ERC-20 OLAS** (no hooks/rebase/fee-on-transfer).
- Upgrade authority should be **multisig → timelock** in production.
