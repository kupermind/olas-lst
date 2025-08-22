
# stOLAS - Liquid Staking Token for OLAS

## Overview

stOLAS is a comprehensive liquid staking solution for the OLAS token in the Autonolas ecosystem.
It enables users to stake OLAS tokens and receive stOLAS (staked OLAS) tokens in return, providing liquidity
while maintaining exposure to staking rewards.

## Key Features

- **ERC4626 Vault Standard**: Fully compliant with the ERC4626 vault standard for maximum DeFi composability
- **Cross-Chain Architecture**: L1 (Ethereum) for deposits/withdrawals, L2 (Gnosis Chain, then Base, etc.) for active staking
- **Automated Staking Management**: Intelligent service deployment and reward distribution
- **Liquidity Preservation**: stOLAS tokens can be freely traded, transferred, and used in DeFi protocols and products
- **Governance Separation**: Future vstOLAS token for governance, keeping stOLAS purely utility-focused

## Architecture Overview

### L1 Layer (Ethereum)
- **stOLAS Vault**: Main ERC4626 vault contract managing deposits and withdrawals
- **Depository**: Handles cross-chain bridging and staking model management
- **Treasury**: Manages withdrawal requests and ERC6909 token issuance
- **Distributor**: Distributes rewards between veOLAS and stOLAS holders
- **Lock**: Manages veOLAS (voting escrow) for governance participation

### L2 Layer (i.e. Base, etc)
- **StakingManager**: Orchestrates service deployment and staking operations
- **StakingTokenLocked**: Manages individual staking instances and reward distribution
- **ActivityModule**: Handles service activity verification and reward claiming
- **Collector**: Collects and bridges rewards back to L1

### Cross-Chain Bridge
- **LayerZero Integration**: Secure cross-chain messaging for token and data transfer
- **Bridge Processors**: Handle deposit and withdrawal operations across chains

## Repository Structure

```
contracts/
├── l1/                    # L1 (Ethereum) contracts
│   ├── stOLAS.sol         # Main ERC4626 vault
│   ├── Depository.sol     # Cross-chain deposit management
│   ├── Treasury.sol       # Withdrawal and ERC6909 management
│   ├── Distributor.sol    # Reward distribution
│   ├── Lock.sol           # veOLAS management
│   ├── LzOracle.sol       # LzRead-driven staking model management
│   └── UnstakeRelayer.sol # Unstake request handling
├── l2/                    # L2 (Gnosis Chain) contracts
│   ├── StakingManager.sol    # Staking orchestration
│   ├── StakingTokenLocked.sol # Individual staking instances
│   ├── ActivityModule.sol     # Service activity management
│   └── Collector.sol          # Reward collection and bridging
├── bridging/              # Cross-chain bridge contracts
├── Beacon.sol             # Upgradeable contract beacon
└── Implementation.sol     # Upgradeable implementation

test/
├── LiquidStaking.js       # JavaScript E2E tests
├── LiquidStaking.t.sol    # Solidity/Forge E2E tests
└── mocks/                 # Mock contracts for testing

audits/                    # Security audit reports
doc/                       # Documentation and whitepaper
```

## How It Works

### 1. Deposit Process
1. User deposits OLAS into the stOLAS vault on L1
2. stOLAS tokens are minted 1:1 initially, then adjusts proportionally as amount of OLAS starts to grow
3. OLAS is bridged to L2 for active staking
4. StakingManager deploys services and manages staking operations
5. Each staked service is controlled by a corresponding ActivityModule proxy contract that shields access to funds
6. Autonomous agents trigger each ActivityModule to perform actions and claim rewards

### 2. Staking Operations
1. Services are deployed on L2 with OLAS backing
2. Rewards accumulate based on service performance
3. ActivityModule verifies service liveness and required KPI performance
4. Collector gathers rewards and bridges them back to L1 via a Distributor contract

### 3. Withdrawal Process
1. User requests withdrawal through Treasury
2. ERC6909 tokens are minted representing the withdrawal request
3. If L1 has sufficient OLAS on stOLAS, it is immediately transferred to Treasury for finalized withdrawal
4. If not, L2 unstaking is triggered in order to bridge required amount of OLAS back to L1 to fund Treasury directly
5. User finalizes withdrawal after cool-down period

### 4. Reward Distribution
1. Rewards are bridged from L2 to L1
2. Distributor contract takes a small percentage to lock OLAS into veOLAS, and sends the rest to stOLAS
3. stOLAS holders receive their share of rewards
4. veOLAS accumulated voting power allows protocol to vote for its continuous support

## Development

### Prerequisites
- **Foundry Forge**: This repository follows the Foundry development process
- **Solidity**: Code written in Solidity starting from version 0.8.30
- **Node.js**: Required for JavaScript testing (confirmed with v22.15.1)
- **Yarn**: Package management (confirmed with 1.22.22)

### Installation

```bash
# Clone with submodules
git clone --recursive https://github.com/kupermind/olas-lst.git
cd olas-lst

# Install dependencies
yarn install
```

### Compilation and Testing

```bash
# Compile contracts
forge build

# Run all tests
forge test -vvv

# Run specific test file
forge test --match-path "test/LiquidStaking.t.sol" -vv

# Run Hardhat tests
yarn test:hardhat
```

### Key Test Scenarios

The test suite covers comprehensive E2E scenarios:

1. **Basic Liquid Staking**: Simple deposit → staking → reward → withdrawal flow
2. **Multi-Service Staking**: Multiple services with different staking amounts
3. **Partial Withdrawals**: Withdraw portions while maintaining staking exposure
4. **Maximum Stakes**: Test system limits and edge cases
5. **Multiple Stake-Unstake Cycles**: Complex scenarios with repeated operations
6. **Model Retirement**: Proper handling of retired staking models

## Security

- **Internal Audits**: Comprehensive internal code review completed
- **External Audits**: Reviewing options, TBD
- **Open Source**: Full transparency with public repository
- **Bug Bounty**: Program under consideration post-audit

## Roadmap
> This roadmap reflects the current design and audit notes. Items and ordering may be updated by governance. *(Last updated: 2025-08-20 12:14 UTC)*

### Phase 0 — Security & Ops Readiness [x]
**Goal:** lock in correct configuration and observability before broader integrations.
- **L2→L1 routing guardrails:** `REWARD → Distributor (L1)`, `UNSTAKE → Treasury (L1)`, `UNSTAKE_RETIRED → UnstakeRelayer (L1)`; add off‑chain preflight that reads back receivers and fails on mismatch.
- **Docs for ERC4626 caveats:** `deposit` only via **Depository**, `redeem` only via **Treasury**; `mint/withdraw` are non‑standard and not for external use.
- **Monitoring & dashboards:** `totalReserves` breakdown, PPS, outstanding withdraw tickets, `UNSTAKE` inflows to Treasury, bridge latency.
- **Access control baseline:** `owner` under multisig, timelock prepared; incident runbooks.
- **QA:** fork tests for withdrawals under low liquidity; batch‑size limits in UI/SDK; basic bug‑bounty process (`SECURITY.md`).

**Exit criteria:**
- Preflight/alerts in place; correct routing confirmed on staging/mainnet.
- ≥1 full cycle of request→unstake→bridge→finalize validated end‑to‑end.
- Dashboards live and reviewed by maintainers.

### Phase 1 — Core Protocol Stabilization / Mainnet Beta []
**Goal:** operate with conservative limits and prove reliability.
- veOLAS vote to whitelist StakingTokenLocked implementation in OLAS staking economy ecosystem.
- Soft caps on deposits/withdraws; safe batch sizes enforced by UI/SDK.
- SLO/SLA targets for bridge/unstake latency and ticket finalization windows.
- Weekly PPS/liquidity reports and post‑mortems for any incidents.

**Exit criteria:**
- ≥N weeks without Sev‑1 incidents; metrics within SLO; negative scenarios rehearsed.

### Phase 2 — Governance Launch []
**Goal:** transition to community‑driven control.
- Deploy **vstOLAS** (if applicable) and enable on‑chain governance processes.
- Activate timelock as the execution layer; document upgrade runbooks (fork rehearsal + storage layout checks).
- Define proposal thresholds, quorum, and emergency procedures.

**Dependencies:** stable operations and monitoring from Phases 0–1.

### Phase 3 — Cross‑Chain Expansion []
**Goal:** scale to additional networks and diversify bridges.
- Multi-chain `stOLAS` deployments where strategic, with provider-diverse bridges including health checks and fallbacks.

**Dependencies:** governance in place; proven reliability and observability.

### Phase 4 — External service integration []
**Goal:** utility expansion via external service performance.
- Integrate LST performance with other services supported by the protocol and expand the flywheel of OLAS flow.

**Dependencies:** continued reliability and observability.

### Phase 5 — DeFi Integration []
**Goal:** expand utility once core flows are stable.
- Yield‑aggregator partnerships after liquidity/pps stability is demonstrated.
- Liquidity pools (strategy & monitoring for IL).

## OLAS Protocol Proposal to Jump Start LST Deployment

Olas Staking enables Launchers to deploy staking contracts via [launch.olas.network](https://launch.olas.network).

The protocol limits what kind of staking contracts can be deployed. For the OLAS LST, the current `StakingToken` [`StakingToken`](https://github.com/valory-xyz/autonolas-registries/blob/main/contracts/staking/StakingToken.sol)
implementation is less restrictive than required: any service that corresponds to a given staking setup can be staked freely.
A new [`StakingTokenLocked`](contracts/l2/StakingTokenLocked.sol) implementation is needed such that it limits the number of stakers
to just one contract - OLAS LST [`StakingManager`](contracts/l2/StakingManager.sol).

This setup allows to have a full internal control of cross-chain OLAS balances without intervention by other parties and
possible misalignment of deposits. Also, `StakingTokenLocked`-created and nominated staking proxies are guaranteed
to have a full capacity of seats dedicated to LST performance. Note that the standard staking launcher workflow is respected
and no further modification is requested.

A governance proposal is live with the following intent:

Whitelist `StakingTokenLocked` implementation contract on Gnosis and Base. Passing of the proposal allows enabling OLAS
protocol staking inflation to be directed towards LST-compatible staking contracts, enabling the whole LST workflow.
LST specific `StakingTokenLocked` contracts are more lightweight compared to original `StakingToken`
ones. However, they are more restricted and designed in a way such that only the internals of LST ecosystem are able
to control the stake / unstake dynamics resulting in efficient accumulation of OLAS incentives. Adoption of the proposal would
mark the start of the deployment of all LST contracts.

Proposal tx: https://etherscan.io/tx/0x7682f2042e1524a6aa971ec2438846c58282ed48546a5a7885caa096b4933178

Proposal Id: [`59025344683074789922169705239782887646995636661382504070382540682844243682748`](https://etherscan.io/tx/0x7682f2042e1524a6aa971ec2438846c58282ed48546a5a7885caa096b4933178#eventlog)

Proposal State: [Active](https://etherscan.io/address/0x8e84b5055492901988b831817e4ace5275a3b401#readContract#F21)

## Documentation

- [Technical Architecture](doc/architecture.md)
- [Architecture Diagrams](doc/architecture-diagrams.md)
- [FAQ](doc/FAQ.md)
- [Whitepaper (PDF)](doc/stolas_whitepaper_formatted.pdf) (Under liquid edition)
- [Whitepaper (Text)](doc/stolas_whitepaper.txt) (Under liquid edition)

## Contributing

We welcome contributions! Please see our [Contributing Guide](CONTRIBUTING.md) for details.

## Contact

- **Website**: [https://lstolas.xyz](https://lstolas.xyz) (Under construction)
- **Repository**: https://github.com/kupermind/olas-lst
- **Security**: security@lstolas.xyz

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Acknowledgements
stOLAS contracts were inspired and based on the following sources:
- [Solmate](https://github.com/transmissions11/solmate).
- [Autonolas Registries](https://github.com/valory-xyz/autonolas-registries).
- [Safe Contracts](https://github.com/safe-global/safe-smart-account).
- [Layer Zero](https://github.com/LayerZero-Labs/layerzero-v2).
- [OpenZeppelin](https://github.com/OpenZeppelin/openzeppelin-contracts).

---

*stOLAS: Liquid Staking for the Autonolas Ecosystem*
