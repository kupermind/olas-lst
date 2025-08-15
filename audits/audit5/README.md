# Audit of `main` branch
The review has been performed based on the contract code in the following repository:<br>
`https://github.com/kupermind/olas-lst` <br>
commit: `17b88a26bd04c846e458d9f309c0c125e8318fd4` <br> 

## Objectives
The audit focused on contracts in repo <br>


## Issue (to discussion)
### Issue? Access control for Oracle function
```
function lzCreateAndActivateStakingModel(uint256 chainId, address stakingProxy, bytes calldata options) external payable
Who can call this function?
In which network (chainid)?
What happens if it is called with obviously incorrect parameters?
``` 
[]

### Issue? Access control for Oracle function
```
function lzCloseStakingModel(uint256 chainId, address stakingProxy, bytes calldata options) external payable
Who can call this function?
In which network (chainid)?
What happens if it is called with obviously incorrect parameters?
``` 
[]


## Notes
[audits\audit4\findings\INFO-1-access-control-review.md](audits\audit5\findings\INFO-1-access-control-review.md)
[audits\audit4\findings\INFO-1-integer-overflow-rewards.md](audits\audit5\findings\INFO-1-integer-overflow-rewards.md)
