# Audit of `post_lock` branch
The review has been performed based on the contract code in the following repository:<br>
`https://github.com/kupermind/olas-lst` <br>
commit: `3fdfbf7bc37c39506dd783bbff2f3973c1a189dc` <br> 

## Objectives
The audit focused on contracts in repo <br>

## Coverage
```
--------------------------------|----------|----------|----------|----------|----------------|
File                            |  % Stmts | % Branch |  % Funcs |  % Lines |Uncovered Lines |
--------------------------------|----------|----------|----------|----------|----------------|
 contracts/                     |       40 |    19.23 |    58.33 |    33.33 |                |
  Beacon.sol                    |    14.29 |       10 |    33.33 |    18.75 |... 55,56,59,60 |
  BeaconProxy.sol               |      100 |       50 |      100 |    85.71 |             29 |
  Implementation.sol            |        0 |        0 |        0 |        0 |... 49,50,54,58 |
  Proxy.sol                     |      100 |       50 |    66.67 |       60 |    34,39,49,71 |
 contracts/interfaces/          |      100 |      100 |      100 |      100 |                |
  IBridgeErrors.sol             |      100 |      100 |      100 |      100 |                |
  IService.sol                  |      100 |      100 |      100 |      100 |                |
  IStaking.sol                  |      100 |      100 |      100 |      100 |                |
  IToken.sol                    |      100 |      100 |      100 |      100 |                |
  IUniswapV3.sol                |      100 |      100 |      100 |      100 |                |
 contracts/l1/                  |    78.62 |    38.13 |    59.38 |    67.16 |                |
  Depository.sol                |    78.75 |    39.29 |    53.85 |    66.45 |... 566,573,579 |
  Distributor.sol               |    76.92 |       30 |       80 |    70.37 |... 104,105,112 |
  Lock.sol                      |    63.16 |       25 |    57.14 |       50 |... 207,208,211 |
  Treasury.sol                  |    87.88 |       50 |    57.14 |    77.59 |... 226,244,250 |
 contracts/l1/bridging/         |    54.84 |    26.67 |       60 |    49.09 |                |
  BaseDepositProcessorL1.sol    |        0 |        0 |        0 |        0 |... 111,114,117 |
  DefaultDepositProcessorL1.sol |    70.59 |       30 |    66.67 |    60.61 |... 162,167,186 |
  GnosisDepositProcessorL1.sol  |      100 |      100 |      100 |      100 |                |
 contracts/l2/                  |    92.49 |    45.68 |    82.93 |    79.85 |                |
  ActivityModule.sol            |      100 |       50 |      100 |    83.33 |... 204,223,248 |
  Collector.sol                 |    81.25 |    35.71 |       80 |    64.52 |... 111,124,130 |
  ModuleActivityChecker.sol     |      100 |      100 |      100 |      100 |                |
  StakingManager.sol            |      100 |     43.1 |      100 |    90.97 |... 440,463,511 |
  StakingTokenLocked.sol        |    85.56 |    48.57 |     62.5 |    72.53 |... 735,742,754 |
 contracts/l2/bridging/         |    36.84 |    17.86 |    35.29 |    30.08 |                |
  BaseStakingProcessorL2.sol    |        0 |        0 |        0 |        0 |... 84,85,88,89 |
  DefaultStakingProcessorL2.sol |    34.85 |     17.5 |    27.27 |    28.93 |... 439,440,443 |
  GnosisStakingProcessorL2.sol  |      100 |       50 |      100 |    83.33 |             68 |
--------------------------------|----------|----------|----------|----------|----------------|
All files                       |    75.05 |    35.28 |    64.29 |    64.57 |                |
--------------------------------|----------|----------|----------|----------|----------------|
```
[x] Noted

## Issue (to discussion)
### CEI pattern 
[audits\audit4\findings\INFORMATIONAL-CEI-pattern-violations.md](audits\audit4\findings\INFORMATIONAL-CEI-pattern-violations.md)
[x] Fixed

### Read-only reentrancy
[audits\audit4\findings\INFORMATIONAL-read-only-reentrancy.md](audits\audit4\findings\INFORMATIONAL-read-only-reentrancy.md)
[x] Fixed

### ERC4626 check
[MEDIUM-balance-of-manipulation.md](findings/MEDIUM-balance-of-manipulation.md)
[x] Fixed

## Notes
### Doc for fix coverage issue
[COVERAGE_FIX.md](COVERAGE_FIX.md)