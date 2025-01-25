// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IToken} from "../interfaces/IToken.sol";
import "hardhat/console.sol";

interface IDepositProcessor {
    // TODO remove later
    /// @dev Sends a single message to the L2 side via a corresponding bridge.
    /// @param target Staking target addresses.
    /// @param stakingShare Corresponding staking amount.
    /// @param bridgePayload Bridge payload necessary (if required) for a specific bridge relayer.
    /// @param transferAmount Actual OLAS amount to be transferred.
    /// @param operation Funds operation: stake / unstake.
    function sendMessage(address target, uint256 stakingShare, bytes memory bridgePayload, uint256 transferAmount,
        bytes32 operation) external payable;

    /// @dev Sends a batch message to the L2 side via a corresponding bridge.
    /// @param targets Set of staking target addresses.
    /// @param stakingShares Corresponding set of staking amounts.
    /// @param bridgePayload Bridge payload necessary (if required) for a specific bridge relayer.
    /// @param transferAmount Actual total OLAS amount across all the targets to be transferred.
    /// @param operation Funds operation: stake / unstake.
    function sendMessageBatch(address[] memory targets, uint256[] memory stakingShares, bytes memory bridgePayload,
        uint256 transferAmount, bytes32 operation) external payable;
}

interface ILock {
    /// @dev Increases lock amount and time.
    /// @param olasAmount OLAS amount.
    function increaseLock(uint256 olasAmount) external;
}

interface ITreasury {
    /// @dev Processes OLAS amount supplied and mints corresponding amount of stOLAS.
    /// @param account Account address.
    /// @param olasAmount OLAS amount.
    /// @return Amount of stOLAS
    function processAndMintStToken(address account, uint256 olasAmount) external returns (uint256);
}

/// @dev Only `owner` has a privilege, but the `sender` was provided.
/// @param sender Sender address.
/// @param owner Required sender address as an owner.
error OwnerOnly(address sender, address owner);

/// @dev Zero address.
error ZeroAddress();

/// @dev Zero value.
error ZeroValue();

/// @dev The contract is already initialized.
error AlreadyInitialized();

/// @dev Wrong length of two arrays.
/// @param numValues1 Number of values in a first array.
/// @param numValues2 Number of values in a second array.
error WrongArrayLength(uint256 numValues1, uint256 numValues2);

/// @dev Value overflow.
/// @param provided Overflow value.
/// @param max Maximum possible value.
error Overflow(uint256 provided, uint256 max);

/// @dev Staking model already exists.
/// @param stakingModelId Staking model Id.
error StakingModelAlreadyExists(uint256 stakingModelId);

/// @dev Account is unauthorized.
/// @param account Account address.
error UnauthorizedAccount(address account);

error WrongStakingModel(uint256 stakingModelId);

struct StakingModel {
    uint96 supply;
    uint96 remainder;
    bool active;
}

/// @title Depository - Smart contract for the stOLAS Depository.
contract Depository {
    event ImplementationUpdated(address indexed implementation);
    event OwnerUpdated(address indexed owner);
    event TreasuryUpdated(address indexed treasury);
    event LockFactorUpdated(uint256 lockFactor);
    event Locked(address indexed account, uint256 olasAmount, uint256 lockAmount, uint256 vaultBalance);
    event SetDepositProcessorChainIds(address[] depositProcessors, uint256[] chainIds);
    event SetGuardianServiceStatuses(address[] guardianServices, bool[] statuses);
    event StakingModelsActivated(uint256[] chainIds, address[] stakingProxies, uint256[] supplies);
    event ChangeModelStatuses(uint256[] modelIds, bool[] statuses);
    event Deposit(address indexed sender, uint256 indexed stakingModelId, uint256 olasAmount, uint256 stAmount);

    // Code position in storage is keccak256("DEPOSITORY_PROXY") = "0x40f951bb727bcaf251807e38aa34e1b3f20d890f9f3286454f4c473c60a21cdc"
    bytes32 public constant DEPOSITORY_PROXY = 0x40f951bb727bcaf251807e38aa34e1b3f20d890f9f3286454f4c473c60a21cdc;
    // Stake operation
    bytes32 public constant STAKE = 0x1bcc0f4c3fad314e585165815f94ecca9b96690a26d6417d7876448a9a867a69;
    // Unstake operation
    bytes32 public constant UNSTAKE = 0x8ca9a95e41b5eece253c93f5b31eed1253aed6b145d8a6e14d913fdf8e732293;
    // Max lock factor
    uint256 public constant MAX_LOCK_FACTOR = 10_000;

    address public immutable olas;
    address public immutable ve;
    address public immutable lock;

    address public treasury;
    address public owner;

    // Lock factor in 10_000 value
    uint256 public lockFactor;
    uint256 internal _nonce;

    mapping(uint256 => StakingModel) public mapStakingModels;
    mapping(address => bool) public mapGuardianAgents;
    // Mapping for L2 chain Id => dedicated deposit processors
    mapping(uint256 => address) public mapChainIdDepositProcessors;
    // Set of staking model Ids
    uint256[] public setStakingModelIds;

    // TODO change to initialize in prod
    constructor(address _olas, address _ve, address _treasury, address _lock, uint256 _lockFactor) {
        olas = _olas;
        ve = _ve;
        treasury = _treasury;
        lock = _lock;
        lockFactor = _lockFactor;

        owner = msg.sender;
    }

    function _increaseLock(uint256 olasAmount) internal returns (uint256 remainder) {
        // Get treasury veOLAS lock amount
        uint256 lockAmount = (olasAmount * lockFactor) / MAX_LOCK_FACTOR;
        remainder = olasAmount - lockAmount;

        // Approve OLAS for Lock
        IToken(olas).transfer(lock, lockAmount);

        // Increase lock
        ILock(lock).increaseLock(lockAmount);

        emit Locked(msg.sender, olasAmount, lockAmount, remainder);
    }

    /// @dev Depository initializer.
    function initialize() external{
        // Check for already initialized
        if (owner != address(0)) {
            revert AlreadyInitialized();
        }

        owner = msg.sender;
    }

    /// @dev Changes depository implementation contract address.
    /// @param newImplementation New implementation contract address.
    function changeImplementation(address newImplementation) external {
        // Check for ownership
        if (msg.sender != owner) {
            revert OwnerOnly(msg.sender, owner);
        }

        // Check for zero address
        if (newImplementation == address(0)) {
            revert ZeroAddress();
        }

        // Store depository implementation address
        assembly {
            sstore(DEPOSITORY_PROXY, newImplementation)
        }

        emit ImplementationUpdated(newImplementation);
    }

    /// @dev Changes contract owner address.
    /// @param newOwner Address of a new owner.
    function changeOwner(address newOwner) external {
        // Check for ownership
        if (msg.sender != owner) {
            revert OwnerOnly(msg.sender, owner);
        }

        // Check for zero address
        if (newOwner == address(0)) {
            revert ZeroAddress();
        }

        owner = newOwner;
        emit OwnerUpdated(newOwner);
    }

    /// @dev Changes Treasury contract address.
    /// @param newTreasury Address of a new treasury.
    function changeTreasury(address newTreasury) external {
        // Check for ownership
        if (msg.sender != owner) {
            revert OwnerOnly(msg.sender, owner);
        }

        // Check for zero address
        if (newTreasury == address(0)) {
            revert ZeroAddress();
        }

        treasury = newTreasury;
        emit TreasuryUpdated(newTreasury);
    }

    /// @dev Sets guardian service multisig statues.
    /// @param guardianServices Guardian service multisig addresses.
    /// @param statuses Corresponding whitelisting statues.
    function setGuardianServiceStatuses(address[] memory guardianServices, bool[] memory statuses) external {
        // Check for ownership
        if (msg.sender != owner) {
            revert OwnerOnly(msg.sender, owner);
        }

        // Check for array lengths
        if (guardianServices.length == 0 || guardianServices.length != statuses.length) {
            revert WrongArrayLength(guardianServices.length, statuses.length);
        }

        // Traverse all guardian service multisigs and statuses
        for (uint256 i = 0; i < guardianServices.length; ++i) {
            // Check for zero addresses
            if (guardianServices[i] == address(0)) {
                revert ZeroAddress();
            }

            mapGuardianAgents[guardianServices[i]] = statuses[i];
        }

        emit SetGuardianServiceStatuses(guardianServices, statuses);
    }

    /// @dev Sets deposit processor contracts addresses and L2 chain Ids.
    /// @notice It is the contract owner responsibility to set correct L1 deposit processor contracts
    ///         and corresponding supported L2 chain Ids.
    /// @param depositProcessors Set of deposit processor contract addresses on L1.
    /// @param chainIds Set of corresponding L2 chain Ids.
    function setDepositProcessorChainIds(address[] memory depositProcessors, uint256[] memory chainIds) external {
        // Check for the ownership
        if (msg.sender != owner) {
            revert OwnerOnly(msg.sender, owner);
        }

        // Check for array length correctness
        if (depositProcessors.length == 0 || depositProcessors.length != chainIds.length) {
            revert WrongArrayLength(depositProcessors.length, chainIds.length);
        }

        // Link L1 and L2 bridge mediators, set L2 chain Ids
        for (uint256 i = 0; i < chainIds.length; ++i) {
            // Check supported chain Ids on L2
            if (chainIds[i] == 0) {
                revert ZeroValue();
            }

            // Note: depositProcessors[i] might be zero if there is a need to stop processing a specific L2 chain Id
            mapChainIdDepositProcessors[chainIds[i]] = depositProcessors[i];
        }

        emit SetDepositProcessorChainIds(depositProcessors, chainIds);
    }

    /// @dev Creates and activates staking models.
    /// @param chainIds Chain Ids.
    /// @param stakingProxies Corresponding staking proxy addresses.
    /// @param supplies Corresponding staking supplies.
    function createAndActivateStakingModels(
        uint256[] memory chainIds,
        address[] memory stakingProxies,
        uint256[] memory supplies
    ) external {
        // Check for ownership
        if (msg.sender != owner) {
            revert OwnerOnly(msg.sender, owner);
        }

        // TODO Check array sizes
        // Check for array lengths
//        if (modelIds.length == 0 || modelIds.length != statuses.length) {
//            revert WrongArrayLength(modelIds.length, statuses.length);
//        }

        for (uint256 i = 0; i < chainIds.length; ++i) {
            // TODO Check chainIds order

            // Check for zero value
            if (supplies[i] == 0) {
                revert ZeroValue();
            }

            // TODO Check supplies overflow

            // Check for zero address
            if (stakingProxies[i] == address(0)) {
                revert ZeroAddress();
            }

            // Push a pair of key defining variables into one key: chainId | stakingProxy
            // stakingProxy occupies first 160 bits, chainId occupies next bits as they both fit well in uint256
            uint256 stakingModelId = uint256(uint160(stakingProxies[i]));
            stakingModelId |= chainIds[i] << 160;

            // Get staking model struct
            StakingModel storage stakingModel = mapStakingModels[stakingModelId];

            // Check for existent staking model
            if (stakingModel.supply > 0) {
                revert StakingModelAlreadyExists(stakingModelId);
            }

            // Set supply and activate
            stakingModel.supply = uint96(supplies[i]);
            stakingModel.remainder = uint96(supplies[i]);
            stakingModel.active = true;

            // Add into global staking model set
            setStakingModelIds.push(stakingModelId);
        }

        emit StakingModelsActivated(chainIds, stakingProxies, supplies);
    }


    /// @dev Sets staking model statuses.
    /// @notice Models must be sorted in ascending order. If the model is deactivated, it does not meat that it must
    ///         be unstaked right away as it might continue working and accumulating rewards until fully depleted.
    /// @param stakingModelIds Staking model Ids in ascending order.
    /// @param statuses Corresponding staking model statuses.
    function setStakingModelStatuses(uint256[] memory stakingModelIds, bool[] memory statuses) external {
        // Check for ownership
        if (msg.sender != owner) {
            revert OwnerOnly(msg.sender, owner);
        }

        // Check for array length correctness
        if (stakingModelIds.length == 0 || stakingModelIds.length != statuses.length) {
            revert WrongArrayLength(stakingModelIds.length, statuses.length);
        }

        uint256 localNum;
        for (uint256 i = 0; i < stakingModelIds.length; ++i) {
            if (localNum >= stakingModelIds[i]) {
                revert Overflow(localNum, stakingModelIds[i]);
            }

            mapStakingModels[stakingModelIds[i]].active = statuses[i];

            localNum = stakingModelIds[i];
        }
        
        emit ChangeModelStatuses(stakingModelIds, statuses);
    }

    /// @dev Changes lock factor value.
    /// @param newLockFactor New lock factor value.
    function changeLockFactor(uint256 newLockFactor) external {
        // Check for ownership
        if (msg.sender != owner) {
            revert OwnerOnly(msg.sender, owner);
        }

        // Check for zero value
        if (lockFactor == 0) {
            revert ZeroValue();
        }

        lockFactor = newLockFactor;
        emit LockFactorUpdated(newLockFactor);
    }

    // TODO: array of modelId-s and olasAmount-s as on stake might not fit into one model
    // TODO: consider taking any amount, just add to the stOLAS balance unused remainder
    function deposit(
        uint256 stakingModelId,
        uint256 olasAmount,
        bytes memory bridgePayload
    ) external payable returns (uint256 stAmount) {
        // Get staking model
        StakingModel storage stakingModel = mapStakingModels[stakingModelId];
        // Check for model existence and activity
        if (stakingModel.supply == 0 || !stakingModel.active) {
            revert WrongStakingModel(stakingModelId);
        }

        if (olasAmount > type(uint96).max) {
            revert Overflow(olasAmount, uint256(type(uint96).max));
        }

        // Check for staking model remainder
        if (olasAmount > stakingModel.remainder) {
            revert Overflow(olasAmount, stakingModel.remainder);
        }

        // Update staking model remainder
        stakingModel.remainder = stakingModel.remainder - uint96(olasAmount);

        // Get OLAS from sender
        IToken(olas).transferFrom(msg.sender, address(this), olasAmount);

        // Lock OLAS for veOLAS
        olasAmount = _increaseLock(olasAmount);

        // Calculates stAmount and mints stOLAS
        stAmount = ITreasury(treasury).processAndMintStToken(msg.sender, olasAmount);

        // Decode chain Id and staking proxy
        uint256 chainId = stakingModelId >> 160;
        address stakingProxy = address(uint160(stakingModelId));

        // Transfer OLAS via the bridge
        address depositProcessor = mapChainIdDepositProcessors[chainId];

        // Approve OLAS for depositProcessor
        IToken(olas).transfer(depositProcessor, olasAmount);

        // Transfer OLAS to its corresponding Staker on L2
        IDepositProcessor(depositProcessor).sendMessage{value: msg.value}(stakingProxy, olasAmount, bridgePayload,
            olasAmount, STAKE);

        emit Deposit(msg.sender, stakingModelId, olasAmount, stAmount);
    }

    /// @dev Calculates amounts and initiates cross-chain unstake request from specified models.
    /// @param unstakeAmount Total amount to unstake.
    /// @param chainIds Set of chain Ids with staking proxies.
    /// @param stakingProxies Set of sets of staking proxies corresponding to each chain Id.
    /// @param bridgePayloads Bridge payloads corresponding to each chain Id.
    /// @param values Value amounts for each bridge interaction, if applicable.
    /// @return amounts Corresponding OLAS amounts for each staking proxy.
    function processUnstake(
        uint256 unstakeAmount,
        uint256[] memory chainIds,
        address[][] memory stakingProxies,
        bytes[] memory bridgePayloads,
        uint256[] memory values
    ) external payable returns (uint256[][] memory amounts) {
        // Allocate arrays of max possible size
        amounts = new uint256[][](chainIds.length);

        // TODO Check array lengths

        uint256 totalAmount;

        // Collect staking contracts and amounts
        for (uint256 i = 0; i < chainIds.length; ++i) {
            // TODO chain Ids order

            // Check if more cycles are needed
            if (unstakeAmount == 0) {
                break;
            }

            uint256 olasAmount;

            for (uint256 j = 0; i < stakingProxies[i].length; ++j) {
                // TODO stakingProxies order
                // Push a pair of key defining variables into one key: chainId | stakingProxy
                // stakingProxy occupies first 160 bits, chainId occupies next bits as they both fit well in uint256
                uint256 stakingModelId = uint256(uint160(stakingProxies[i][j]));
                stakingModelId |= chainIds[i] << 160;

                StakingModel memory stakingModel = mapStakingModels[stakingModelId];
                uint256 maxUnstakeAmount = stakingModel.supply - stakingModel.remainder;

                if (unstakeAmount > maxUnstakeAmount) {
                    amounts[i][j] = maxUnstakeAmount;
                    olasAmount += maxUnstakeAmount;
                    unstakeAmount -= maxUnstakeAmount;
                    mapStakingModels[stakingModelId].remainder = stakingModel.supply;
                } else {
                    amounts[i][j] = unstakeAmount;
                    olasAmount += unstakeAmount;
                    unstakeAmount = 0;
                    mapStakingModels[stakingModelId].remainder += stakingModel.remainder + uint96(unstakeAmount);
                    break;
                }
            }

            totalAmount += olasAmount;

            // Transfer OLAS via the bridge
            address depositProcessor = mapChainIdDepositProcessors[chainIds[i]];

            // Approve OLAS for depositProcessor
            IToken(olas).approve(depositProcessor, olasAmount);

            // Transfer OLAS to its corresponding Staker on L2
            IDepositProcessor(depositProcessor).sendMessageBatch{value: values[i]}(stakingProxies[i], amounts[i],
                bridgePayloads[i], totalAmount, UNSTAKE);
        }

        // Check if accumulated necessary amount of tokens
        if (unstakeAmount > 0) {
            revert();
        }
    }

    function getNumStakingModels() external view returns (uint256) {
        return setStakingModelIds.length;
    }

    function getStakingModelId(uint256 chainId, address stakingProxy) external pure returns (uint256) {
        return uint256(uint160(stakingProxy)) | (chainId << 160);
    }

    function getChainIdAndStakingProxy(uint256 stakingModelId) external pure returns (uint256, address) {
        return ((stakingModelId >> 160), address(uint160(stakingModelId)));
    }
}