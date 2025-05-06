# Audit of `main` branch
The review has been performed based on the contract code in the following repository:<br>
`https://github.com/kupermind/olas-lst` <br>
commit: `0f86df05c3e93fc341d8febef5a4175af5aab6af` <br> 

## Objectives
The audit focused on contracts in repo <br>

## Issue
### Test failed
```
npx hardhat test
...
L2
OLAS rewards available on L2 staking contract: 1941675264500000000000000
Reward before checkpoint 0
Wait for liveness period to pass
Calling checkpoint by agent or manually
Number of staked services:  100
      1) Multiple stakes-unstakes


  0 passing (41s)
  1 failing

  1) Liquid Staking
       Staking
         Multiple stakes-unstakes:
     Error: Timeout of 40000ms exceeded. For async tests and hooks, ensure "done()" is called; if returning a Promise, ensure it resolves. (/home/andrey/valory/olas-lst/test/LiquidStaking.js)
      at listOnTimeout (node:internal/timers:573:17)
      at processTimers (node:internal/timers:514:7)
```
[x] This happens sometimes on various platforms, but the CI works as expected

### A lof of ToDo for final version
```
grep -r TODO ./contracts/   
./contracts/l2/ActivityModule.sol:        // TODO reentrancy check?
./contracts/l2/Collector.sol:    // TODO adjust
./contracts/l2/Collector.sol:    // TODO Add bridgePayload
./contracts/l2/Collector.sol:        // TODO Check on relays, but the majority of them does not require value
./contracts/l2/Collector.sol:        // TODO: Make sure once again no value is needed to send tokens back
./contracts/l2/Collector.sol:    // TODO withdraw
./contracts/l2/StakingManager.sol:    // TODO change to transient bool
./contracts/l2/StakingManager.sol:        // TODO Check on relays, but the majority of them does not require value
./contracts/l2/StakingManager.sol:        // TODO Check that activityModule is eligible, i.e. created by address(this)
./contracts/l2/StakingManager.sol:        // TODO map of activityModule => staking proxy?
./contracts/l2/bridging/DefaultStakingProcessorL2.sol:    // TODO Add bridgePayload
./contracts/l1/LiquidityManager.sol:    // TODO change to transient bool
./contracts/l1/LiquidityManager.sol:    // TODO Make same function accessed by owner to create pairs from this contract balances
./contracts/l1/LiquidityManager.sol:            // TODO
./contracts/l1/LiquidityManager.sol:            // TODO
./contracts/l1/LiquidityManager.sol:            // TODO Check result?
./contracts/l1/Treasury.sol:    // TODO Move high level part to depository?
./contracts/l1/Treasury.sol:    // TODO Withdraw by owner - any asset
./contracts/l1/Lock.sol:    // TODO lock full balance and make this ownerless?
./contracts/l1/Lock.sol:        // TODO Never withdraw the full amount, i.e. neve close the treasury lock
./contracts/l1/Lock.sol:        // TODO For testing purposes now
./contracts/l1/stOLAS.sol:        // TODO Vault inflation attack
./contracts/l1/stOLAS.sol:        // TODO Is this check needed?
./contracts/l1/stOLAS.sol:        // TODO Optimize
./contracts/l1/stOLAS.sol:        // TODO Is it correct it happens after assets calculation? Seems so, as assets must be calculated on current holdings
./contracts/l1/stOLAS.sol:        // TODO optimize?
./contracts/l1/stOLAS.sol:        // TODO event or Transfer event is enough?
./contracts/l1/stOLAS.sol:        // TODO event or Transfer event is enough?
./contracts/l1/stOLAS.sol:    // TODO Optimize
./contracts/l1/stOLAS.sol:        // TODO Vault inflation attack
./contracts/l1/stOLAS.sol:        // TODO Change with function balanceOf()
./contracts/l1/Depository.sol:        // TODO Check array sizes
./contracts/l1/Depository.sol:            // TODO Check chainIds order
./contracts/l1/Depository.sol:            // TODO Check supplies overflow
./contracts/l1/Depository.sol:    // TODO: consider taking any amount, just add to the stOLAS balance unused remainder
./contracts/l1/Depository.sol:        // TODO Check array lengths
./contracts/l1/Depository.sol:        // TODO - obsolete as called by Treasury?
./contracts/l1/Depository.sol:        // TODO Check array lengths
./contracts/l1/Depository.sol:            // TODO correct with unstakeAmount vs totalAmount
./contracts/l1/Depository.sol:        // TODO correct msg.sender
```
[x] Fixed

### function createAndActivateStakingModels. low issue
```
size arrays
```
[x] Fixed

### Missign Reentrance guard. low issue
```
function deposit(
        uint256 stakeAmount,
        uint256[] memory chainIds,
        address[] memory stakingProxies,
        bytes[] memory bridgePayloads,
        uint256[] memory values
    ) external payable returns (uint256 stAmount, uint256[] memory amounts) {
```
[x] Fixed

### Maybe stakeAmount == 0 => revert in function deposit(
```
if (stakeAmount > 0) {
            // Get OLAS from sender
            IToken(olas).transferFrom(msg.sender, address(this), stakeAmount);

            // Increase deposit amounts
            mapAccountDeposits[msg.sender] += stakeAmount;

            // Lock OLAS for veOLAS
            stakeAmount = _increaseLock(stakeAmount);
        }
else {revert()} ?
``` 
[x] False positive - the amount is assembled with the reserve balance on stOLAS

### Fix ToDo  function unstake(). Remove msg.sender == owner?
```
// If withdraw amount is bigger than the current one, need to unstake
        if (stakedBalanceBefore > stakedBalanceAfter) {
            uint256 withdrawDiff = stakedBalanceBefore - stakedBalanceAfter;

            IDepository(depository).unstake(withdrawDiff, chainIds, stakingProxies, bridgePayloads, values);
        }
withdrawDiff always > 0
// TODO - obsolete as called by Treasury?
        // Check for zero value
        if (unstakeAmount == 0) {
            revert ZeroValue();
        }
unstakeAmount -> alwys if controlled only by Treasury.
But why msg.sender can by owner?
```
[x] Fixed

### Medium. previewDeposit(assets) not "view" version of deposit 
```
function deposit(uint256 assets, address receiver) public override returns (uint256 shares) {}
We need a view function, returned correct shares based on actual calculation in deposit
```
[x] Fixed

### Medium. previewRedeem(shares) not "view" version of redeem
```
We need a view function for function redeem(uint256 shares, address receiver, address tokenOwner) public override returns (uint256 assets) {}
```
[x] Fixed



