# LOW or INFORMATIONAL: Read-Only Reentrancy Vulnerabilities

## Summary
Several contracts in the OLAS Liquid Staking protocol are vulnerable to read-only reentrancy attacks, where external calls to view functions can be exploited to manipulate state through other contracts.

## Vulnerability Details

### 1. StakingTokenLocked.sol - Activity Checker Calls

**Location**: `contracts/l2/StakingTokenLocked.sol:550`

**Issue**: The `stake()` function makes an external call to `IActivityChecker(activityChecker).getMultisigNonces(service.multisig)` before updating state, which could allow read-only reentrancy.

```solidity
// Line 550
uint256[] memory nonces = IActivityChecker(activityChecker).getMultisigNonces(service.multisig);
sInfo.nonces = nonces;
sInfo.tsStart = block.timestamp;

// Add the service Id to the set of staked services
setServiceIds.push(serviceId);

// Transfer the service for staking
IService(serviceRegistry).safeTransferFrom(msg.sender, address(this), serviceId);
```

**Impact**: An attacker could potentially manipulate the activity checker contract to return unexpected nonces, affecting reward calculations and service state.

### 2. StakingTokenLocked.sol - Service Registry Calls

**Location**: `contracts/l2/StakingTokenLocked.sol:530-540`

**Issue**: External calls to service registry before state updates could allow read-only reentrancy.

```solidity
// Check the service conditions for staking
IService.Service memory service = IService(serviceRegistry).getService(serviceId);

// Get the service staking token and deposit
(address token, uint96 stakingDeposit) = 
    IService(serviceRegistryTokenUtility).mapServiceIdTokenDeposit(serviceId);
```

**Impact**: The service registry could be manipulated to return incorrect service data or token information.

### 3. Depository.sol - Treasury Calls

**Location**: `contracts/l1/Depository.sol:200-250`

**Issue**: The `deposit()` function makes external calls to treasury contract before updating local state.

```solidity
// External call to treasury
uint256 stAmount = ITreasury(treasury).processAndMintStToken(msg.sender, stakeAmount);

// State updates after external call
mapAccountDeposits[msg.sender] += stakeAmount;
```

**Impact**: The treasury contract could be manipulated to affect deposit calculations.

## Proof of Concept

### Read-Only Reentrancy in StakingTokenLocked

```solidity
contract MaliciousActivityChecker {
    bool public attackTriggered = false;
    
    function getMultisigNonces(address multisig) external view returns (uint256[] memory) {
        if (!attackTriggered) {
            // Trigger reentrancy attack through another contract
            attackTriggered = true;
            // Call back to the staking contract or manipulate other state
        }
        return new uint256[](0);
    }
    
    function isRatioPass(uint256[] memory, uint256[] memory, uint256) external view returns (bool) {
        return true;
    }
}
```

## Recommended Fixes

### 1. Use CEI (Checks-Effects-Interactions) Pattern

```solidity
function stake(uint256 serviceId) external {
    // 1. CHECKS
    if (msg.sender != stakingManager) {
        revert UnauthorizedAccount(msg.sender);
    }
    
    // 2. EFFECTS - Update state first
    ServiceInfo storage sInfo = mapServiceInfo[serviceId];
    sInfo.tsStart = block.timestamp;
    setServiceIds.push(serviceId);
    
    // 3. INTERACTIONS - External calls last
    uint256[] memory nonces = IActivityChecker(activityChecker).getMultisigNonces(service.multisig);
    sInfo.nonces = nonces;
    
    IService(serviceRegistry).safeTransferFrom(msg.sender, address(this), serviceId);
}
```

### 2. Add Reentrancy Guards

```solidity
modifier nonReentrant() {
    require(!_locked, "ReentrancyGuard: reentrant call");
    _locked = true;
    _;
    _locked = false;
}
```

### 3. Use Static Calls for View Functions

```solidity
// Use staticcall for view functions to prevent state changes
bytes memory data = abi.encodeWithSelector(IActivityChecker.getMultisigNonces.selector, multisig);
(bool success, bytes memory returnData) = activityChecker.staticcall(data);
```

