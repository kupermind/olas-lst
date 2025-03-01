// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IToken} from "../interfaces/IToken.sol";

interface IDepositProcessor {
    /// @dev Sends a message to the L2 side via a corresponding bridge.
    /// @param target Staking target addresses.
    /// @param amount Corresponding staking amount.
    /// @param bridgePayload Bridge payload necessary (if required) for a specific bridge relayer.
    /// @param operation Funds operation: stake / unstake.
    function sendMessage(address target, uint256 amount, bytes memory bridgePayload, bytes32 operation) external payable;
}

interface ILock {
    /// @dev Increases lock amount and time.
    /// @param olasAmount OLAS amount.
    function increaseLock(uint256 olasAmount) external;
}

interface IST {
    /// @dev Deposits OLAS in exchange for stOLAS tokens.
    /// @param assets OLAS amount.
    /// @param receiver Receiver account address.
    /// @return shares stOLAS amount.
    function deposit(uint256 assets, address receiver) external returns (uint256 shares);

    function topUpReserveBalance(uint256 amount) external;

    function fundDepository() external;

    function reserveBalance() external view returns (uint256);
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

/// @dev Wrong staking model Id provided.
/// @param stakingModelId Staking model Id.
error WrongStakingModel(uint256 stakingModelId);

/// @dev Unauthorized account.
/// @param account Account address.
error UnauthorizedAccount(address account);

// StakingModel struct
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
    event DepositoryParamsUpdated(uint256 lockFactor, uint256 maxStakingLimit);
    event Locked(address indexed account, uint256 olasAmount, uint256 lockAmount, uint256 vaultBalance);
    event SetDepositProcessorChainIds(address[] depositProcessors, uint256[] chainIds);
    event StakingModelsActivated(uint256[] chainIds, address[] stakingProxies, uint256[] supplies);
    event ChangeModelStatuses(uint256[] modelIds, bool[] statuses);
    event Deposit(address indexed sender, uint256 stakeAmount, uint256 stAmount, uint256[] chainIds,
        address[] stakingProxies, uint256[] amounts);
    event Unstake(address indexed sender, uint256 unstakeAmount, uint256[] chainIds, address[] stakingProxies,
        uint256[] amounts);

    // Code position in storage is keccak256("DEPOSITORY_PROXY") = "0x40f951bb727bcaf251807e38aa34e1b3f20d890f9f3286454f4c473c60a21cdc"
    bytes32 public constant DEPOSITORY_PROXY = 0x40f951bb727bcaf251807e38aa34e1b3f20d890f9f3286454f4c473c60a21cdc;
    // Stake operation
    bytes32 public constant STAKE = 0x1bcc0f4c3fad314e585165815f94ecca9b96690a26d6417d7876448a9a867a69;
    // Unstake operation
    bytes32 public constant UNSTAKE = 0x8ca9a95e41b5eece253c93f5b31eed1253aed6b145d8a6e14d913fdf8e732293;
    // Max lock factor
    uint256 public constant MAX_LOCK_FACTOR = 10_000;

    // OLAS contract address
    address public immutable olas;
    // stOLAS contract address
    address public immutable st;
    // veOLAS contract address
    address public immutable ve;
    // Lock contract address
    address public immutable lock;

    // Treasury contract address
    address public treasury;
    // Contract owner address
    address public owner;

    // Lock factor in 10_000 value
    uint256 public lockFactor;
    // Max staking limit per a single staking proxy
    uint256 public maxStakingLimit;

    // Mapping of staking model Id => staking model
    mapping(uint256 => StakingModel) public mapStakingModels;
    // Mapping for L2 chain Id => dedicated deposit processors
    mapping(uint256 => address) public mapChainIdDepositProcessors;
    // Set of staking model Ids
    uint256[] public setStakingModelIds;

    // TODO change to initialize in prod
    constructor(
        address _olas,
        address _st,
        address _ve,
        address _treasury,
        address _lock,
        uint256 _lockFactor,
        uint256 _maxStakingLimit
    ) {
        olas = _olas;
        st = _st;
        ve = _ve;
        treasury = _treasury;
        lock = _lock;
        lockFactor = _lockFactor;
        maxStakingLimit = _maxStakingLimit;

        owner = msg.sender;
    }

    /// @dev Increases veOLAS lock.
    /// @param olasAmount OLAS amount to get lock part from.
    /// @return remainder veOLAS locked amount.
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

    /// @dev Changes depository params.
    /// @param newLockFactor New lock factor value.
    /// @param newMaxStakingLimit New max staking limit per staking proxy.
    function changeLockFactor(uint256 newLockFactor, uint256 newMaxStakingLimit) external {
        // Check for ownership
        if (msg.sender != owner) {
            revert OwnerOnly(msg.sender, owner);
        }

        // Check for zero value
        if (newLockFactor == 0 || newMaxStakingLimit == 0) {
            revert ZeroValue();
        }

        lockFactor = newLockFactor;
        maxStakingLimit = newMaxStakingLimit;
        emit DepositoryParamsUpdated(newLockFactor, newMaxStakingLimit);
    }

    // TODO: consider taking any amount, just add to the stOLAS balance unused remainder
    /// @dev Calculates amounts and initiates cross-chain stake request for specified models.
    /// @param stakeAmount Total incoming amount to stake.
    /// @param chainIds Set of chain Ids with staking proxies.
    /// @param stakingProxies Set of staking proxies corresponding to each chain Id.
    /// @param bridgePayloads Bridge payloads corresponding to each chain Id.
    /// @param values Value amounts for each bridge interaction, if applicable.
    /// @return stAmount Amount of stOLAS minted for staking.
    /// @return amounts Corresponding OLAS amounts for each staking proxy.
    function deposit(
        uint256 stakeAmount,
        uint256[] memory chainIds,
        address[] memory stakingProxies,
        bytes[] memory bridgePayloads,
        uint256[] memory values
    ) external payable returns (uint256 stAmount, uint256[] memory amounts) {
        if (stakeAmount > type(uint96).max) {
            revert Overflow(stakeAmount, uint256(type(uint96).max));
        }
        // Get OLAS from sender
        IToken(olas).transferFrom(msg.sender, address(this), stakeAmount);

        // Lock OLAS for veOLAS
        stakeAmount = _increaseLock(stakeAmount);

        // TODO Check array lengths

        // Remainder is stake amount plus reserve balance
        uint256 remainder = IST(st).reserveBalance();
        // Pull OLAS reserve balance from stOLAS
        if (remainder > 0) {
            IST(st).fundDepository();
        }

        // Add requested stake amount
        remainder += stakeAmount;
        // Check for zero value
        if (remainder == 0) {
            revert ZeroValue();
        }

        uint256 actualStakeAmount;
        // Allocate arrays of max possible size
        amounts = new uint256[](chainIds.length);

        // Get max staking limit
        uint256 curMaxStakingLimit = maxStakingLimit;

        // Collect staking contracts and amounts
        for (uint256 i = 0; i < chainIds.length; ++i) {
            // Push a pair of key defining variables into one key: chainId | stakingProxy
            // stakingProxy occupies first 160 bits, chainId occupies next bits as they both fit well in uint256
            uint256 stakingModelId = uint256(uint160(stakingProxies[i]));
            stakingModelId |= chainIds[i] << 160;

            StakingModel memory stakingModel = mapStakingModels[stakingModelId];
            // Check for model existence and activity
            if (stakingModel.supply == 0 || !stakingModel.active) {
                revert WrongStakingModel(stakingModelId);
            }

            // Skip potential zero funds models
            if (stakingModel.remainder == 0) {
                continue;
            }

            // Adjust staking amount to not overflow the max allowed one
            amounts[i] = remainder;
            if (amounts[i] > curMaxStakingLimit) {
                amounts[i] = curMaxStakingLimit;
            }

            if (amounts[i] > stakingModel.remainder) {
                amounts[i] = stakingModel.remainder;
                remainder -= amounts[i];
                // Update staking model remainder
                mapStakingModels[stakingModelId].remainder = 0;
            } else {
                // Update staking model remainder
                mapStakingModels[stakingModelId].remainder = stakingModel.remainder - uint96(amounts[i]);
                remainder -= amounts[i];
            }

            // Increase actual stake amount
            actualStakeAmount += amounts[i];

            // Transfer OLAS via the bridge
            address depositProcessor = mapChainIdDepositProcessors[chainIds[i]];
            // Check for zero address
            if (depositProcessor == address(0)) {
                revert ZeroAddress();
            }

            // Approve OLAS for depositProcessor
            IToken(olas).transfer(depositProcessor, amounts[i]);

            // Transfer OLAS to its corresponding Staker on L2
            IDepositProcessor(depositProcessor).sendMessage{value: values[i]}(stakingProxies[i], amounts[i],
                bridgePayloads[i], STAKE);

            if (remainder == 0) {
                break;
            }
        }

        // If there are OLAS leftovers, transfer (back) to stOLAS
        if (stakeAmount > actualStakeAmount) {
            remainder = stakeAmount - actualStakeAmount;
            IToken(olas).approve(st, remainder);
            IST(st).topUpReserveBalance(remainder);
        }

        // Calculates stAmount and mints stOLAS
        // If stakeAmount is zero, stakes are performed from reserves
        if (stakeAmount > 0) {
            stAmount = IST(st).deposit(stakeAmount, msg.sender);
        }

        emit Deposit(msg.sender, stakeAmount, stAmount, chainIds, stakingProxies, amounts);
    }

    /// @dev Calculates amounts and initiates cross-chain unstake request from specified models.
    /// @notice This allows to deduct reserves from their staked part and get them back as vault assets.
    /// @param unstakeAmount Total amount to unstake.
    /// @param chainIds Set of chain Ids with staking proxies.
    /// @param stakingProxies Set of staking proxies corresponding to each chain Id.
    /// @param bridgePayloads Bridge payloads corresponding to each chain Id.
    /// @param values Value amounts for each bridge interaction, if applicable.
    /// @return amounts Corresponding OLAS amounts for each staking proxy.
    function unstake(
        uint256 unstakeAmount,
        uint256[] memory chainIds,
        address[] memory stakingProxies,
        bytes[] memory bridgePayloads,
        uint256[] memory values
    ) external payable returns (uint256[] memory amounts) {
        if (msg.sender != owner && msg.sender != treasury) {
            revert UnauthorizedAccount(msg.sender);
        }

        // TODO - obsolete as called by Treasury?
        // Check for zero value
        if (unstakeAmount == 0) {
            revert ZeroValue();
        }

        // TODO Check array lengths

        // Allocate arrays of max possible size
        amounts = new uint256[](chainIds.length);

        // Collect staking contracts and amounts
        for (uint256 i = 0; i < chainIds.length; ++i) {
            // Push a pair of key defining variables into one key: chainId | stakingProxy
            // stakingProxy occupies first 160 bits, chainId occupies next bits as they both fit well in uint256
            uint256 stakingModelId = uint256(uint160(stakingProxies[i]));
            stakingModelId |= chainIds[i] << 160;

            StakingModel memory stakingModel = mapStakingModels[stakingModelId];
            // Check for model existence and activity
            if (stakingModel.supply == 0) {
                revert WrongStakingModel(stakingModelId);
            }

            // Adjust unstaking amount to not overflow the max allowed one
            amounts[i] = stakingModel.supply - stakingModel.remainder;
            if (amounts[i] > maxStakingLimit) {
                amounts[i] = maxStakingLimit;
            }

            if (unstakeAmount > amounts[i]) {
                // Remainder resulting value is limited by stakingModel.supply
                mapStakingModels[stakingModelId].remainder += uint96(amounts[i]);
                unstakeAmount -= amounts[i];
            } else {
                amounts[i] = unstakeAmount;
                mapStakingModels[stakingModelId].remainder = stakingModel.remainder + uint96(unstakeAmount);
                unstakeAmount = 0;
            }

            // Transfer OLAS via the bridge
            address depositProcessor = mapChainIdDepositProcessors[chainIds[i]];
            // Check for zero address
            if (depositProcessor == address(0)) {
                revert ZeroAddress();
            }

            // Approve OLAS for depositProcessor
            IToken(olas).approve(depositProcessor, amounts[i]);

            // Transfer OLAS to its corresponding Staker on L2
            IDepositProcessor(depositProcessor).sendMessage{value: values[i]}(stakingProxies[i], amounts[i],
                bridgePayloads[i], UNSTAKE);

            if (unstakeAmount == 0) {
                break;
            }
        }

        // Check if accumulated necessary amount of tokens
        if (unstakeAmount > 0) {
            // TODO correct with unstakeAmount vs totalAmount
            revert Overflow(unstakeAmount, 0);
        }

        // TODO correct msg.sender
        emit Unstake(msg.sender, unstakeAmount, chainIds, stakingProxies, amounts);
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