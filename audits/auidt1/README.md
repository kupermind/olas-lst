# Audit of `reserve` branch
The review has been performed based on the contract code in the following repository:<br>
`https://github.com/kupermind/olas-lst` <br>
commit: `3a7fd731101aa35c917a3ff76ad0c42f02f5e29b` <br> 

## Objectives
The audit focused on contracts in repo <br>

## Issue
### Depository
#### Medium. Fixing TODO change to initialize
```
Because proxy-pattern.
```
[]

#### Medium/Design issue. mapGuardianAgents do nothing
```
mapGuardianAgents just settuped. 
```
[]

#### Revert in fundDepository.
```
we are sure that we want revert() deposit in case: amount > curReserveBalance?
IST(st).fundDepository(remainder);
    function fundDepository(uint256 amount) external {
        if (msg.sender != depository) {
            revert();
        }

        uint256 curReserveBalance = reserveBalance;
        if (amount > curReserveBalance) {
            revert Overflow(amount, curReserveBalance);
        }

        curReserveBalance -= amount;
        reserveBalance = curReserveBalance;
        totalReserves -= amount;

        asset.transfer(msg.sender, amount);

        // TODO event or Transfer event is enough?
    }
```
[]

#### Question. function processUnstake() is non-ownable? Any can unstake all program
```
Maybe only Treasure?
```
[]

#### Fix todo in processUnstake()
[]

### LiquidityManager **unaudited**
```
This contract is not currently involved in workflow. I suggest moving it somewhere to utilities. To avoid confusion.
More features are good, of course, but they are confusing and will not be used in at least the first version of the protocol.
```
[]

### Lock
#### Logical issue. Need synchronization with contract Depository
```
1. Sync with when the first lock starts and Deposit must be on pause before createFirstLock
L.createFirstLock()
D.deposit() -> L.increaseLock
2. uint256 public constant MAX_LOCK_TIME = 4 * 365 * 1 days;
What will happen after this time. Deposit will it be able to work?
```
[]

#### Design issue. Unlock
```
// TODO Never withdraw the full amount, i.e. neve close the treasury lock
Think again about the conditions unlock and the cycle after it.
We can't increase the lock time - it's already maximum. We can unlock only after the maximum lock time. There's some problem with the logic here, what will happen after 4 years.
```
[]

#### Remove mock function. 
```
function propose() + castVote()
they refer to an undeveloped governance system. To avoid confusion, I suggest removing it from the first version.
```
[]

### Treasury
#### Design issue. Deposit -> Treasury (just re-route) -> stOLAS
```
With function:
function fundDepository(uint256 amount) external {
    +
function topUpReserveBalance(uint256 amount) external {
Maybe more clear path: Depository -> stOLAS ?
We don't store anything in Treasury in this function.
function processAndMintStToken(address account, uint256 olasAmount) external returns (uint256 stAmount) {
        // Check for depository access
        if (msg.sender != depository) {
            revert DepositoryOnly(msg.sender, depository);
        }

        // mint stOLAS
        stAmount = IST(st).deposit(olasAmount, account);
    }
```
[]

### Design auth/control issue. Treasury unstake vs Depository processUnstake
```
owner only -> Treasury.unstake() -> Treasury._unstake() -> IDepository(depository).processUnstake
vs
any -> Depository.processUnstake
```
[]

### Treasure/stOLAS update stakedBalance after unstake
```
stakedBalance only changed curStakedBalance += assets; in deposit
stakedBalance affteced `unstake`?
```
[]

### requestToWithdraw non-clear using global variable withdrawAmountRequested
```
Double-check uint256 curWithdrawAmountRequested = withdrawAmountRequested + olasAmount;
```
[]

### requestToWithdraw/redeem question. 
```
No idea how to solve it.
olasAmount = IST(st).redeem(stAmount, address(this), address(this));
1. _burn(tokenOwner, shares); = This means that stOLAS burned
2. if (curVaultBalance > assets) {} else {} => transferAmount = curVaultBalance;
asset.transfer(receiver, transferAmount);
This means that it will be transferred to the treasury limited by curVaultBalance
        // If withdraw amount is bigger than the current one, need to unstake
        if (stakedBalanceBefore > stakedBalanceAfter) {
            uint256 withdrawDiff = stakedBalanceBefore - stakedBalanceAfter;

            _unstake(withdrawDiff, chainIds, stakingProxies, bridgePayloads, values);
        }
Accordingly, this unstake does not compensate for anything from the recipient's this requestToWithdraw point of view
We need to think about this.

+ 
assets = previewRedeem(shares)
uint256 curVaultBalance = asset.balanceOf(address(this));
curVaultBalance < assets ---> Does this even make sense?
Main question: stOLAS.previewRedeem(shares) > asset.balanceOf(stOLAS) is this correct from some point of view?
```
[]



