
# stOLAS - Staked OLAS Token

## Overview
stOLAS is a liquid staking token representing staked OLAS assets. It follows the ERC4626 vault standard and is designed to integrate seamlessly with DeFi protocols.

## Repository Structure
- `stOLAS.sol` — Main ERC4626 vault contract for OLAS staking.

## Usage
Users deposit OLAS and receive stOLAS tokens in return. These tokens are freely transferable and can be used across the DeFi ecosystem.

## Development

### Prerequisites
- This repository follows the [`Foundry Forge`](https://getfoundry.sh/forge/overview) development process.
- The code is written on Solidity starting from version `0.8.30`.
- The standard versions of Node.js along with Yarn are required to proceed further (confirmed to work with Yarn `1.22.22` and npx/npm `10.9.2` and node `v22.15.1`).

### Install the dependencies
The project has submodules to get the dependencies. Make sure you run `git clone --recursive` or init the submodules yourself.
The dependency list is managed by the `package.json` file, and the setup parameters are stored in `foundry.yaml` file.
Simply run the following command to install the project:
```
yarn install
```

### Core components
The contracts, deployment scripts and tests are located in the following folders respectively:
```
contracts
scripts
test
```

### Compile the code and run
Compile the code:
```
forge build
```
Run tests:
```
forge test -vvv
```


## Documentation
- [Whitepaper (formatted PDF)](doc/stolas_whitepaper_formatted.pdf)
- [Whitepaper (text)](doc/stolas_whitepaper.txt)

## Contact
- Website: [https://URL](https://URL)
