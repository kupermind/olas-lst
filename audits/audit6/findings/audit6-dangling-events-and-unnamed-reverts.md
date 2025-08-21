# Dangling Events & Unnamed Reverts Audit — `olas-lst`
## Summary

- Solidity files scanned: **33**
- Declared events: **65** distinct names: **60**
- Emits found: **75** across **58** event names
- **Dangling events (declared, never emitted anywhere in repo):** 2 (prod: 2, test: 0)
- **Unnamed reverts (`revert();` / `revert;`):** 4 (prod: 3, test: 1)

> Note: Events can be emitted by derived contracts. We treated an event as **non-dangling** if an `emit <EventName>(...)` was found **anywhere** in the repository. Therefore, the list below is conservative.

## Findings — Dangling Events (Production)
- `ReserveBalanceTopUpped` — contracts/l1/stOLAS.sol:50
- `VaultBalanceTopUpped` — contracts/l1/stOLAS.sol:51

## Findings — Unnamed Reverts (Production)
- contracts/l1/bridging/LzOracle.sol:135 — ```... odeHash) {                 // TODO                 revert ();             }              // Considering 1 agent per service: depos ...```
- contracts/l1/bridging/LzOracle.sol:151 — ```... if (availableRewards > 0) {                 revert ();             }              IDepository(depository).LzCloseStakingMod ...```
- contracts/l1/bridging/LzOracle.sol:159 — ```... // This must never happen             revert();         }     }      /// @dev Constructs a command to query stakingH ...```

---
### Methodology
- Parsed all `contracts/**/*.sol` files from the provided ZIP.
- **Dangling events** = events declared via `event Name(...)` with **zero** `emit Name(...)` occurrences across the repo (including derived contracts).
- **Unnamed reverts** = `revert;` or `revert();` (with or without whitespace). Calls like `revert CustomError(...)` are **not** included.

### Caveats
- False positives/negatives can occur with generated code, macros, or if `emit` is constructed via unusual string concatenation (rare in Solidity).
- Line numbers are best-effort based on the scanned snapshot and may drift if the file changes.
