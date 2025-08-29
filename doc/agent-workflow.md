# stOLAS — Agent Workflow

This file provides agent workflow description section. 
---

## Workflow Diagram

```mermaid
graph LR
  StartRound
  CheckAnyWorkRound
  WaitingRound

  StartRound-->|DONE|CheckAnyWorkRound
  CheckAnyWorkRound-->|CLAIM_BRIDGED_TOKEN|ClaimBridgedTokensRound
  CheckAnyWorkRound-->|CALL_REDEEM|RedeemRound
  CheckAnyWorkRound-->|CLAIM_REWARDS|ClaimRewardTokensRound
  CheckAnyWorkRound-->|CALL_CHECKPOINTS|CheckpointRound 
  CheckAnyWorkRound-->|TRIGGER_L2_TO_L1|TriggerL2ToL1BridgeRound
  CheckAnyWorkRound-->|NO_WORK|WaitingRound
  

  ClaimRewardTokensRound-->|DONE|CheckAnyWorkRound
  ClaimBridgedTokensRound-->|DONE|CheckAnyWorkRound
  TriggerL2ToL1BridgeRound-->|DONE|CheckAnyWorkRound
  CheckpointRound-->|DONE|CheckAnyWorkRound
  RedeemRound-->|DONE|CheckAnyWorkRound
  WaitingRound-->|DONE|CheckAnyWorkRound
```

---

## Agent Workflow — Step by Step

### Claim Bridged Tokens (L2 -> L1)

Agents are going to interact with relevant L1 bridge contracts in order to finalize fund transfers from L2 to L1.
Each native bridge is specific to its fund transfer finalization times and routines.

#### Gnosis Bridge

In order to finalize token transfer on L1, the [`executeSignatures()`](https://etherscan.io/address/0x4C36d2919e407f0Cc2Ee3c993ccF8ac26d9CE64e#writeProxyContract#F3)
function needs to be called on [AMB (Foreign)](https://docs.gnosischain.com/bridges/About%20Token%20Bridges/amb-bridge#contracts)
contract with the following parameters:
- `_data`: `encodedData` value from `UserRequestForSignature()` event from [AMB (Home)](https://gnosisscan.io/address/0x75Df5AF045d91108662D8080fD1FEFAd6aA0bb59#events) contract;
- `_signatures`: from the return value of [`getSignatures()`](https://gnosisscan.io/address/0x7d94ece17e81355326e3359115D4B02411825EdD#readContract#F2) method.

Read full Gnosis guide of how to call execute signatures [here](https://docs.gnosischain.com/bridges/About%20Token%20Bridges/amb-bridge#how-to-call-executesignatures-on-foreign-amb-ethereum).

#### Base bridge

In order to finalize token transfer on L1, the [`relayMessage()`](https://etherscan.io/address/0x866E82a600A1414e583f7F13623F1aC5d58b0Afa#writeProxyContract#F2)
function needs to be called on [L1CrossDomainMessenger](https://docs.base.org/base-chain/network-information/base-contracts#ethereum-mainnet) contract.
However, there is a script that facilitates a required sequence of calls for bridging assets from L2 to L1.

It is advised to use documentation and workflow provided [here](https://github.com/valory-xyz/l2_withdraws/tree/main?tab=readme-ov-file#base).

#### Finalize Bridged Tokens Destination

Once tokens are fully bridged on L1 in their corresponding contracts, the last step is to direct them to designated destinations.
Currently, there are two contracts that require L2-L1 bridged funds forwarding further:
- [Distributor](../contracts/l1/Distributor.sol): call function `distribute()`;
- [UnstakeRelayer](../contracts/l1/UnstakeRelayer.sol): call function `relay()`.

It is advised to check `olas.balanceOf(distributorProxyAddress)` and `olas.balanceOf(unstakeRelayerProxyAddress)` before executing function calls.

### Redeem Stake Operations

There could be scenarios when **STAKE** / **UNSTAKE** operations are not complete in an automatic way on L2 when triggered on L1.
For example, OLAS funds arrive across bridge later than the message with the instruction about where funds need to be relayed.
In this case, the `RequestQueued()` event in each [DefaultStakingProcessorL2](../contracts/l2/bridging/DefaultStakingProcessorL2.sol)
is emitted with the following variables:

```solidity
event RequestQueued(bytes32 indexed queueHash, address indexed target, uint256 amount, bytes32 indexed batchHash, bytes32 operation, uint256 issueType);
```

In order to complete the queued request, the agent must call the `redeem()` function using values from the `RequestQueued()` event:
```solidity
/// @dev Redeems queued staking deposit / withdraw.
/// @param target Staking target address.
/// @param amount Staking amount.
/// @param batchHash Batch hash.
/// @param operation Funds operation: stake / unstake.
function redeem(address target, uint256 amount, bytes32 batchHash, bytes32 operation) external;
```

### Claim Reward Tokens

Each staked service has a controlling [ActivityModule](../contracts/l2/ActivityModule.sol) contract, which serves as an entry point
to all the LST service activity. In order to claim reward tokens and immediately transfer them to [Collector](../contracts/l2/Collector.sol)
contract, agents need to call the `claim()` function, which triggers the `checkpoint()` function call as well of a corresponding `stakingProxy` contract.

Events to track staking proxy addresses, stacked service Ids and their corresponding activity modules in [StakingManager](../contracts/l2/StakingManager.sol) proxy contract:
```solidity
event Staked(address indexed stakingProxy, uint256 indexed serviceId, address activityModule);
event Unstaked(address indexed stakingProxy, uint256 indexed serviceId, address activityModule);
```

Helper function to get all the staked services in [StakingManager](../contracts/l2/StakingManager.sol) proxy contract:
```solidity
/// @dev Gets staked service Ids for a specific staking proxy.
/// @param stakingProxy Staking proxy address.
/// @return serviceIds Set of service Ids.
function getStakedServiceIds(address stakingProxy) external view returns (uint256[] memory serviceIds);
```

Ultimately there is a set of active activity module addresses that must be called by agents to get rewards.

### Staking Proxy Checkpoint

For any of `stakingProxy` address, the `checkpoint()` function can be called at any moment. However, note that the `checkpoint()`
is also called when `stake()`, `claim()` and `ustake()` are called. If applicable, it is advised to monitor the following condition
prior to calling the `checkpoint()` function:
```
if (block.timestamp - stakingProxy.tsCheckpoint() > stakingProxy.livenessPeriod()) {
    send stakingProxy.checkpoint();
}
```

This check is going to skip the `checkpoint()` call if the checkpoint has been already triggered within the `livenessPeriod` time.

### Trigger L2 to L1 Tokens Bridging



---
