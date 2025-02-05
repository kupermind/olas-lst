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

#### Design auth/control issue. Treasury unstake vs Depository processUnstake
```
owner only -> Treasury.unstake() -> Treasury._unstake() -> IDepository(depository).processUnstake
vs
any -> Depository.processUnstake
```
[]

#### Treasure/stOLAS update stakedBalance after unstake
```
stakedBalance only changed curStakedBalance += assets; in deposit
stakedBalance affteced `unstake`?
```
[]

#### requestToWithdraw non-clear using global variable withdrawAmountRequested
```
Double-check uint256 curWithdrawAmountRequested = withdrawAmountRequested + olasAmount;
```
[]

#### requestToWithdraw/redeem question. 
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
[x] Verified, false positive

### stOLAS
#### Question. Balance in function redeem
```
curVaultBalance = 0
reserveBalance = 0
Can they be non-zero in this case?
else {
            transferAmount = curVaultBalance;
            uint256 diff = assets - curVaultBalance;
            curVaultBalance = 0;

            // Check for overflow, must never happen
            if (diff > curStakedBalance) {
                revert Overflow(diff, curStakedBalance);
            }

            curStakedBalance -= diff;
            stakedBalance = curStakedBalance;
            reserveBalance = 0;
        }
    
```
[x] reserveBalance is part of vaultBalance

#### Medium/Question. Return value of redeem and redeem vs previewRedeem
```
Should this computation (*) be wrapped in previewRedeem. Because transferAmount <= assets. 
By standard
According to the ERC‑4626 standard, the redeem function is indeed expected to return the actual amount of underlying tokens that have been transferred out of the vault. This return value represents the exact assets that were withdrawn as a result of burning the specified shares. It is intended to provide clarity and consistency so that both users and integrators can reliably determine the outcome of the redemption operation.

(*) if (curVaultBalance > assets) {
            transferAmount = assets;

            // Reserve balance update
            if (assets > curReserveBalance) {
                curReserveBalance = 0;
                curVaultBalance -= (assets - curReserveBalance);
            } else {
                curReserveBalance -= assets;
            }
        } else {
            transferAmount = curVaultBalance;
            uint256 diff = assets - curVaultBalance;
            curVaultBalance = 0;

            // Check for overflow, must never happen
            if (diff > curStakedBalance) {
                revert Overflow(diff, curStakedBalance);
            }

            curStakedBalance -= diff;
            stakedBalance = curStakedBalance;
            reserveBalance = 0;
        }

Confirming previewRedeem behavior

In line with ERC4626, previewRedeem should mirror redeem's output. It's designed to simulate, matching expected results in a transaction.

Evaluating discrepancies

previewRedeem and redeem outputs might diverge due to fees or rounding errors. This insight clarifies that previewRedeem simulates outcomes without considering these factors.

Clarifying simulation and precision

EIP-4626 distinguishes previewRedeem from redeem, attributing discrepancies to rounding or fees, while previewRedeem mimics the redemption reverse order, minus fees or slippage.

According to the ERC‑4626 standard, the purpose of the previewRedeem function is to provide a view (or estimate) of the amount of underlying assets you would receive if you redeemed a given number of shares. In an ideal scenario—where there are no fees, rounding errors, or state-dependent factors—the value returned by previewRedeem would match the actual amount transferred by redeem.

However, there are a couple of important nuances:

Rounding Errors: In some implementations, due to integer arithmetic or rounding, there might be minor differences between the previewed value and the actual value received.
State Changes or Fees: If the vault has any mechanisms (like fees or dynamic conversion rates) that affect the redemption process, the actual value returned by redeem might slightly differ from the preview if those factors change between the preview and the actual redemption transaction.
In summary, while previewRedeem is intended to reflect what you’d receive from a redeem call, it should be considered an estimate. Under normal conditions without complicating factors, they would return the same number, but slight discrepancies may occur in practice.

```
[x] Discussed, not an issue

###  curReserveBalance is not obviously taken into account in the contract
```
Issue 1:
function updateTotalAssets() public
uint256 curTotalReserves = curStakedBalance + curVaultBalance;
vs
curReserveBalance

Issue 2:
function redeem(uint256 shares, address receiver, address tokenOwner) public override returns (uint256 assets)
curReserveBalance -= assets;
vs
uint256 curTotalReserves = curStakedBalance + curVaultBalance;

Thus TotalReserves not included same time curReserveBalance, same time included.
```
[x] Discussed, not an issue