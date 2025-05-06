# Audit of `main` branch
The review has been performed based on the contract code in the following repository:<br>
`https://github.com/kupermind/olas-lst` <br>
commit: `c624a770bb3e274dd7f48b6ae184411904eadea1` <br> 

## Objectives
The audit focused on contracts in repo <br>

## Issue
### Test fixing
```
Fix:
it("Multiple stakes-unstakes", async function () {
  this.timeout(80000); // Up to 80 sec , 40 sec default
....

npx hardhat test
...
  1 passing (53s) (53 sec vs 40 sec default)
```
[x] Update timeout

### Coverage with current test setup.
```
--------------------------------|----------|----------|----------|----------|----------------|
File                            |  % Stmts | % Branch |  % Funcs |  % Lines |Uncovered Lines |
--------------------------------|----------|----------|----------|----------|----------------|
 contracts/                     |       40 |    19.23 |    58.33 |    34.09 |                |
  Beacon.sol                    |    14.29 |       10 |    33.33 |       20 |... 55,56,59,60 |
  BeaconProxy.sol               |      100 |       50 |      100 |    85.71 |             29 |
  Implementation.sol            |        0 |        0 |        0 |        0 |... 49,50,54,58 |
  Proxy.sol                     |      100 |       50 |    66.67 |       60 |    34,39,49,71 |
 contracts/interfaces/          |      100 |      100 |      100 |      100 |                |
  IBridgeErrors.sol             |      100 |      100 |      100 |      100 |                |
  IService.sol                  |      100 |      100 |      100 |      100 |                |
  IStaking.sol                  |      100 |      100 |      100 |      100 |                |
  IToken.sol                    |      100 |      100 |      100 |      100 |                |
  IUniswapV3.sol                |      100 |      100 |      100 |      100 |                |
 contracts/l1/                  |    75.18 |    36.18 |    53.33 |    65.49 |                |
  Depository.sol                |       75 |    37.07 |       50 |    65.29 |... 616,620,624 |
  Lock.sol                      |       65 |       25 |    57.14 |       50 |... 204,205,208 |
  Treasury.sol                  |    82.76 |    43.75 |    57.14 |    76.47 |... 200,220,224 |
 contracts/l1/bridging/         |    57.58 |    29.41 |       60 |       50 |                |
  BaseDepositProcessorL1.sol    |        0 |        0 |        0 |        0 |... 113,116,119 |
  DefaultDepositProcessorL1.sol |    73.68 |    33.33 |    66.67 |    60.53 |... 177,182,201 |
  GnosisDepositProcessorL1.sol  |      100 |      100 |      100 |      100 |                |
 contracts/l2/                  |    90.09 |    43.29 |    82.05 |    77.31 |                |
  ActivityModule.sol            |      100 |    43.75 |      100 |    81.08 |... 175,193,211 |
  Collector.sol                 |    78.57 |    35.71 |       80 |    62.07 |... 107,118,124 |
  ModuleActivityChecker.sol     |      100 |      100 |      100 |      100 |                |
  StakingManager.sol            |     93.1 |    39.06 |    91.67 |    84.11 |... 533,536,539 |
  StakingTokenLocked.sol        |    86.52 |    48.57 |    66.67 |    72.93 |... 738,746,753 |
 contracts/l2/bridging/         |     35.9 |    17.86 |    35.29 |    30.08 |                |
  BaseStakingProcessorL2.sol    |        0 |        0 |        0 |        0 |... 79,80,83,84 |
  DefaultStakingProcessorL2.sol |    34.85 |     17.5 |    27.27 |    28.93 |... 435,436,439 |
  GnosisStakingProcessorL2.sol  |    83.33 |       50 |      100 |    83.33 |             63 |
--------------------------------|----------|----------|----------|----------|----------------|
All files                       |    72.71 |    33.91 |    62.04 |    62.93 |                |
--------------------------------|----------|----------|----------|----------|----------------|
```
[]

### Unfixed TODO. Notes
```
grep -r TODO ./contracts/    
./contracts/l1/concept/LiquidityManager._sol:    // TODO change to transient bool
./contracts/l1/concept/LiquidityManager._sol:    // TODO Make same function accessed by owner to create pairs from this contract balances
./contracts/l1/concept/LiquidityManager._sol:            // TODO
./contracts/l1/concept/LiquidityManager._sol:            // TODO
./contracts/l1/concept/LiquidityManager._sol:            // TODO Check result?
TODO is OK for unused LiquidityManager

./contracts/l1/Depository.sol:    // TODO Activate via proofs
./contracts/l1/Depository.sol:    // TODO Deactivate staking models for good via proofs
Please, comment as TODO for next version.
```
[x] TODO for next trustless versions

### Named revert(). Low issue
```
function topUpReserveBalance(uint256 amount) external {
        if (msg.sender != depository) {
            revert();
        }

function fundDepository() external {
        if (msg.sender != depository) {
            revert();
        }

            // It is safe to just move 64 bits as there is a single withdrawTime value after that
            uint256 withdrawTime = requestIds[i] >> 64;
            // Check for earliest possible withdraw time
            if (withdrawTime > block.timestamp) {
                revert();
            }
```
[x] Fixed

### Unused StakingManager
```
/// @dev Wrong length of two arrays.
/// @param numValues1 Number of values in a first array.
/// @param numValues2 Number of values in a second array.
error WrongArrayLength(uint256 numValues1, uint256 numValues2);
/// @dev Wrong staking instance.
/// @param stakingProxy Staking proxy address.
error WrongStakingInstance(address stakingProxy);
/// @dev Request Id already processed.
/// @param requestId Request Id.
error AlreadyProcessed(uint256 requestId);
/// @dev Service is not evicted.
/// @param stakingProxy Staking proxy address.
/// @param serviceId Service Id.
error ServiceNotEvicted(address stakingProxy, uint256 serviceId);
  // Threshold
    uint256 public constant THRESHOLD = 1;
    // Contributors proxy address
    address public immutable contributorsProxy;
```
[x] Fixed

### Unused StakingTokenLocked
```
/// @dev Agent Id is not correctly provided for the current routine.
/// @param agentId Component Id.
error WrongAgentId(uint256 agentId);
/// @dev Multisig is not whitelisted.
/// @param multisig Address of a multisig implementation.
error UnauthorizedMultisig(address multisig);
/// @dev Required service configuration is wrong.
/// @param serviceId Service Id.
error WrongServiceConfiguration(uint256 serviceId);
```
[x] Fixed

### Question. Treasury. How is it used?
```
    // Total withdraw amount requested
    uint256 public withdrawAmountRequested;
    
    // Update total withdraw amount requested
    withdrawAmountRequested += olasAmount;
```
[]








