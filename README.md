
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

### L2 Layer (Gnosis Chain)
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
2. stOLAS tokens are minted 1:1 (initially)
3. OLAS is bridged to L2 for active staking
4. StakingManager deploys services and manages staking operations

### 2. Staking Operations
1. Services are deployed on L2 with OLAS backing
2. Rewards accumulate based on service performance
3. ActivityModule verifies service liveness
4. Collector gathers rewards and bridges them back to L1

### 3. Withdrawal Process
1. User requests withdrawal through Treasury
2. ERC6909 tokens are minted representing the withdrawal request
3. If L1 has sufficient OLAS, immediate withdrawal
4. If not, L2 unstaking is triggered and bridged back to L1
5. User finalizes withdrawal after cool-down period

### 4. Reward Distribution
1. Rewards are bridged from L2 to L1
2. Distributor splits rewards between veOLAS and stOLAS
3. stOLAS holders receive their share of rewards
4. veOLAS holders receive governance rewards

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

# Run JavaScript tests
yarn test
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

### Phase 1: Core Infrastructure ✅
- [x] stOLAS vault deployment
- [x] Cross-chain bridge implementation
- [x] Basic staking operations

### Phase 2: DeFi Integration 🚧
- [ ] Uniswap V3 liquidity pools
- [ ] Lending protocol integration
- [ ] Yield aggregator partnerships

### Phase 3: Governance Launch 📅
- [ ] vstOLAS token deployment
- [ ] On-chain governance processes
- [ ] Community-driven protocol upgrades

### Phase 4: Cross-Chain Expansion 📅
- [ ] Multi-chain stOLAS deployment
- [ ] Additional bridge protocols
- [ ] Cross-chain yield strategies

## Documentation

- [Whitepaper (PDF)](doc/stolas_whitepaper_formatted.pdf)
- [Whitepaper (Text)](doc/stolas_whitepaper.txt)
- [Technical Architecture](doc/architecture.md)
- [API Reference](doc/api.md)

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
