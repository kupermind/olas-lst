
# stOLAS - Liquid Staking Token for OLAS

## Overview

stOLAS is a comprehensive liquid staking solution for the OLAS token in the Autonolas ecosystem. It enables users to stake OLAS tokens and receive stOLAS (staked OLAS) tokens in return, providing liquidity while maintaining exposure to staking rewards.

## Key Features

- **ERC4626 Vault Standard**: Fully compliant with the ERC4626 vault standard for maximum DeFi composability
- **Cross-Chain Architecture**: L1 (Ethereum) for deposits/withdrawals, L2 (Gnosis Chain) for active staking
- **Automated Staking Management**: Intelligent service deployment and reward distribution
- **Liquidity Preservation**: stOLAS tokens can be freely traded, transferred, and used in DeFi protocols
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
│   ├── stOLAS.sol        # Main ERC4626 vault
│   ├── Depository.sol    # Cross-chain deposit management
│   ├── Treasury.sol      # Withdrawal and ERC6909 management
│   ├── Distributor.sol   # Reward distribution
│   ├── Lock.sol          # veOLAS management
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
- **External Audits**: Planned via Hunt platform (https://hunt.r.xyz)
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
- Soft caps on deposits/withdraws; safe batch sizes enforced by UI/SDK.
- SLO/SLA targets for bridge/unstake latency and ticket finalization windows.
- Weekly PPS/liquidity reports and post‑mortems for any incidents.

**Exit criteria:**
- ≥N weeks without Sev‑1 incidents; metrics within SLO; negative scenarios rehearsed.

### Phase 2 — DeFi Integration []
**Goal:** expand utility once core flows are stable.
- Uniswap V3 liquidity pools (strategy & monitoring for IL).
- Lending integration starting with isolated markets; publish risk & oracle policy (Chainlink with TWAP fallback).
- Yield‑aggregator partnerships after liquidity/pps stability is demonstrated.

**Dependencies:** Phase 0 & 1 exit criteria met.

### Phase 3 — Governance Launch []
**Goal:** transition to community‑driven control.
- Deploy **vstOLAS** (if applicable) and enable on‑chain governance processes.
- Activate timelock as the execution layer; document upgrade runbooks (fork rehearsal + storage layout checks).
- Define proposal thresholds, quorum, and emergency procedures.

**Dependencies:** stable operations and monitoring from Phases 0–1.

### Phase 4 — Cross‑Chain Expansion []
**Goal:** scale to additional networks and diversify bridges.
- Multi‑chain `stOLAS` deployments where strategic; provider‑diverse bridges with health checks/fallbacks.
- Cross‑chain yield strategies gated by end‑to‑end monitoring and SLO adherence.

**Dependencies:** governance in place; proven reliability and observability.

## Documentation

- [Whitepaper (PDF)](doc/stolas_whitepaper_formatted.pdf)
- [Whitepaper (Text)](doc/stolas_whitepaper.txt)
- [Technical Architecture](doc/architecture.md)
- [FAQ](doc/FAQ.md)

## Contributing

We welcome contributions! Please see our [Contributing Guide](CONTRIBUTING.md) for details.

## Contact

- **Website**: [https://URL](https://URL)
- **Repository**: https://github.com/kupermind/olas-lst
- **Security**: security@project.com

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

---

*stOLAS: Liquid Staking for the Autonolas Ecosystem*
