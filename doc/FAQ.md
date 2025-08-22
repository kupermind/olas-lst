# stOLAS — Frequently Asked Questions (FAQ)

*This FAQ complements the `README.md` and reflects the code/design at commit `a23db47`. Generated: 2025-08-20 11:56 UTC.*

---

## 1) What is stOLAS?
**stOLAS** is a liquid staking token (LST) that represents a share of OLAS held and managed by the `stOLAS` vault on L1.
Its value is expressed via **price‑per‑share (PPS)**: as protocol reserves grow from staking rewards bridged from L2,
PPS increases and each stOLAS is redeemable for more OLAS over time.

## 2) How does Liquid OLAS Staking work?
- Users deposit **OLAS** through the system’s **Depository** module (the only allowed caller of `stOLAS.deposit()`).
- The protocol stakes OLAS on **L2** services. Rewards accrued on L2 are **bridged back** to L1 and **topped up** into the vault’s reserves.
- The vault updates internal accounting (`totalReserves = staked + vault + reserve`), and **PPS increases** accordingly.
- Withdrawals are requested and finalized by the **Treasury** module (see below).

## 3) What are the risks of staking with stOLAS?
- **Smart‑contract risk.** Bugs or unforeseen interactions in the contracts.
- **Cross‑chain/bridge risk.** Messages and funds move between L2 and L1; delays or failures can impact withdrawals and rewards.
- **Operational/configuration risk.** The L2→L1 routing must be set so that rewarded/unstaked OLAS return to **Treasury**; misconfiguration can delay finalization.
- **Liquidity/withdrawal timing risk.** If the vault has insufficient immediate liquidity, withdrawals depend on unstaking on L2 and bridging.
- **Governance/upgrade risk.** Parameters and upgrade flows are governed; poor process control can introduce risk.
- **Market risk.** Secondary‑market price of (w)stOLAS may deviate from PPS (if/where a market exists).

## 4) What is stOLAS staking APY?
There is **no fixed or guaranteed APY**. 
Returns are realized as **PPS growth** driven by L2 rewards and can vary over time. 
Historical PPS and dashboard metrics are the best way to assess realized performance.

## 5) What fee is applied by Liquid OLAS Staking?
At the **contract level** (audited commit), we did **not** identify a protocol fee taken on deposit or withdrawal. 
Protocol fee is taken from rewards on L2 in order to manage all the required maintenance costs. Another part of rewards fee is taken on L1 in order to increase the protocol veOLAS lock.
Users pay **gas fees** and, if a withdrawal requires bridging/unstaking, **network/bridge costs** may apply. 
Third party integrations (DEXes, aggregators) may charge their own fees. Governance can introduce changes in the future; always check the app for current parameters.

## 6) How can I get stOLAS?
- **Mint:** Deposit OLAS through the official front‑end/wallet flow (invoking the **Depository**, which calls `stOLAS.deposit()` on your behalf).
- **Buy:** Acquire on a secondary market/DEX **if listed** (availability is not guaranteed).

## 7) How can I use stOLAS?
- **Hold** to participate in PPS growth as L2 rewards are added to reserves.
- **DeFi integrations (if/when available):** use as collateral, provide liquidity, etc. Integration availability is ecosystem‑dependent and not guaranteed by the protocol.

## 8) How can I unstake stOLAS?
Use the app to **request a withdrawal**. The **Treasury** records your ticket (ERC‑6909 semantics / cooldown applies)
and redeems your shares against available liquidity. If there is a shortfall, an **unstake on L2** is triggered and OLAS
are bridged back to L1. After cooldown, you **finalize** to receive OLAS. Alternatively, a **secondary‑market swap**
may provide an earlier exit (subject to price and liquidity).

## 9) How much OLAS can I stake?
Initially for alpha and beta versions there will be stake limits. After more protocol stability is traced, there will be
**no on chain hard cap** specific to a single user in the audited contracts. Practical limits arise from **gas costs**,
wallet/app minimums, and overall protocol capacity.

## 10) What are withdrawals?
Withdrawals are a **two‑step (request → finalize)** process. A request mints/records a ticket (with a cooldown).
Finalization transfers OLAS to you once liquidity is available and the cooldown has elapsed.

## 11) How does the withdrawal process work?
1. **Request:** You submit a withdrawal request via the app; **Treasury** records the ticket and (up to available liquidity) calls `stOLAS.redeem()`.
2. **Unstake if needed:** If the vault’s immediate liquidity is insufficient, **Depository** initiates **unstake on L2**.
3. **Bridge back:** L2 **Collector** routes `UNSTAKE → Treasury (L1)`. Returned OLAS top up Treasury’s balance for payouts.
4. **Finalize:** After cooldown, call **finalize** to receive OLAS and close the ticket.

## 12) How do I withdraw?
Open the app, navigate to **Withdraw**, submit the **amount of stOLAS**, confirm the transaction(s), then **finalize** after cooldown.
The UI will display your ticket status and when finalization is available.

## 13) Can I transform my stOLAS to OLAS?
Yes. You can **redeem** via the withdrawal process (on‑chain PPS‑based redemption), or **swap** on a DEX if/where liquidity exists (subject to price/slippage).

## 14) How long does it take to withdraw?
**Varies.** If the vault has enough liquidity, redemption can be completed promptly after the **cooldown**.
Otherwise, timing depends on L2 **unstake** and **bridge** latency, which are external to the protocol and can fluctuate.

## 15) What are the factors affecting the withdrawal time?
- Available **vault/reserve** liquidity at request time.
- L2 **unstake** duration and batching.
- **Bridge** confirmation time and network conditions.
- **Cooldown** parameters in **Treasury**.
- Gas/network congestion on both chains.

## 16) Do I still get rewards after I withdraw?
You accrue value via PPS **until your shares are redeemed** against your withdrawal ticket. After redemption/finalization,
you no longer participate in PPS growth for the redeemed amount. The app shows your ticket status and whether redemption has occurred.

## 17) Is there a fee for withdrawal?
At the **contract level** (audited commit), no explicit protocol fee on withdrawal was identified. You will pay **gas** and,
if unstake/bridging is needed, any **network/bridge** costs. Third‑party venue fees (e.g., DEX) may apply if you choose to swap
instead of on‑chain redemption.

---

### Notes
- Asset token is assumed to be **standard ERC‑20 OLAS** (no hooks/rebase/fee‑on‑transfer).
- Upgrade authority is expected to be **multisig → timelock** in production.
- For integrators: ERC4626 entrypoints are **non‑standard** (`deposit` only via Depository; `redeem` only via Treasury; `mint/withdraw` not meant for external use).

