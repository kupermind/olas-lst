// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Implementation, OwnerOnly, ZeroAddress} from "../Implementation.sol";
import {IToken} from "../interfaces/IToken.sol";

interface IDepositProcessor {
    /// @dev Sends a message to the L2 side via a corresponding bridge.
    /// @param target Staking target addresses.
    /// @param amount Corresponding staking amount.
    /// @param bridgePayload Bridge payload necessary (if required) for a specific bridge relayer.
    /// @param operation Funds operation: stake / unstake.
    function sendMessage(address target, uint256 amount, bytes memory bridgePayload, bytes32 operation) external payable;
}

interface IST {
    /// @dev Deposits OLAS in exchange for stOLAS tokens.
    /// @param assets OLAS amount.
    /// @param receiver Receiver account address.
    /// @return shares stOLAS amount.
    function deposit(uint256 assets, address receiver) external returns (uint256 shares);

    /// @dev Top-ups reserve balance via Depository.
    /// @param amount OLAS amount.
    function topUpReserveBalance(uint256 amount) external;

    /// @dev Funds Depository with reserve balances.
    function fundDepository() external;

    /// @dev stOLAS reserve balance.
    function reserveBalance() external view returns (uint256);
}

interface ITreasury {
    /// @dev Processes OLAS amount supplied and mints corresponding amount of stOLAS.
    /// @param account Account address.
    /// @param olasAmount OLAS amount.
    /// @return Amount of stOLAS
    function processAndMintStToken(address account, uint256 olasAmount) external returns (uint256);
}

/// @dev Zero value.
error ZeroValue();

/// @dev The contract is already initialized.
error AlreadyInitialized();

/// @dev Wrong length of arrays.
error WrongArrayLength();

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

/// @dev Caught reentrancy violation.
error ReentrancyGuard();


/// @title Depository - Smart contract for the stOLAS Depository.
contract Depository is Implementation {
    enum StakingModelStatus {
        Retired,
        Active,
        Inactive
    }

    event TreasuryUpdated(address indexed treasury);
    event SetDepositProcessorChainIds(address[] depositProcessors, uint256[] chainIds);
    event StakingModelsActivated(uint256[] chainIds, address[] stakingProxies, uint256[] stakeLimitPerSlots,
        uint256[] numSlots);
    event ChangeModelStatuses(uint256[] chainIds, address[] stakingProxies, StakingModelStatus[] statuses);
    event Deposit(address indexed sender, uint256 stakeAmount, uint256 stAmount, uint256[] chainIds,
        address[] stakingProxies, uint256[] amounts);
    event Unstake(address indexed sender, uint256 unstakeAmount, uint256[] chainIds, address[] stakingProxies,
        uint256[] amounts);
    event Retired(uint256[] chainIds, address[] stakingProxies);

    // StakingModel struct
    struct StakingModel {
        // Max available supply
        uint96 supply;
        // Remaining supply
        uint96 remainder;
        // Stake limit per slot as the deposit amount required for a single service stake
        uint96 stakeLimitPerSlot;
        // Staking model status: Retired, Active, Inactive
        StakingModelStatus status;
    }

    // Depository version
    string public constant VERSION = "0.1.0";
    // Stake operation
    bytes32 public constant STAKE = 0x1bcc0f4c3fad314e585165815f94ecca9b96690a26d6417d7876448a9a867a69;
    // Unstake operation
    bytes32 public constant UNSTAKE = 0x8ca9a95e41b5eece253c93f5b31eed1253aed6b145d8a6e14d913fdf8e732293;

    // OLAS contract address
    address public immutable olas;
    // stOLAS contract address
    address public immutable st;

    // Treasury contract address
    address public treasury;

    // Lock factor in 10_000 value
    uint256 public lockFactor;

    // Reentrancy lock
    bool transient _locked;

    // Mapping for staking model Id => staking model
    mapping(uint256 => StakingModel) public mapStakingModels;
    // Mapping for L2 chain Id => dedicated deposit processors
    mapping(uint256 => address) public mapChainIdDepositProcessors;
    // Mapping for account => deposit amounts
    mapping(address => uint256) public mapAccountDeposits;
    // Mapping for account => withdraw amounts
    mapping(address => uint256) public mapAccountWithdraws;
    // Set of staking model Ids
    uint256[] public setStakingModelIds;

    constructor(address _olas, address _st) {
        olas = _olas;
        st = _st;
    }

    /// @dev Depository initializer.
    function initialize() external{
        // Check for already initialized
        if (owner != address(0)) {
            revert AlreadyInitialized();
        }

        owner = msg.sender;
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
            revert WrongArrayLength();
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

    // TODO Activate via proofs
    /// @dev Creates and activates staking models.
    /// @param chainIds Chain Ids.
    /// @param stakingProxies Corresponding staking proxy addresses.
    /// @param stakeLimitPerSlots Corresponding staking limits per each staking slot.
    /// @param numSlots Corresponding number of staking slots.
    function createAndActivateStakingModels(
        uint256[] memory chainIds,
        address[] memory stakingProxies,
        uint256[] memory stakeLimitPerSlots,
        uint256[] memory numSlots
    ) external {
        // Check for ownership
        if (msg.sender != owner) {
            revert OwnerOnly(msg.sender, owner);
        }

        // Check for array lengths
        if (chainIds.length == 0 || chainIds.length != stakingProxies.length || chainIds.length != numSlots.length ||
            chainIds.length != stakeLimitPerSlots.length) {
            revert WrongArrayLength();
        }

        for (uint256 i = 0; i < chainIds.length; ++i) {
            uint256 supply = stakeLimitPerSlots[i] * numSlots[i];

            // Check for overflow
            if (supply > type(uint96).max) {
                revert Overflow(supply, type(uint96).max);
            }

            // Check for zero value
            if (supply == 0) {
                revert ZeroValue();
            }

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

            // Check for existing staking model
            if (stakingModel.supply > 0) {
                revert StakingModelAlreadyExists(stakingModelId);
            }

            // Set supply and activate
            stakingModel.supply = uint96(supply);
            stakingModel.remainder = uint96(supply);
            stakingModel.stakeLimitPerSlot = uint96(stakeLimitPerSlots[i]);
            stakingModel.status = StakingModelStatus.Active;

            // Add into global staking model set
            setStakingModelIds.push(stakingModelId);
        }

        emit StakingModelsActivated(chainIds, stakingProxies, stakeLimitPerSlots, numSlots);
    }

    // TODO Deactivate staking models for good via proofs
    /// @dev Sets existing staking model statuses.
    /// @notice If the model is inactive, it does not mean that it must be unstaked right away as it might continue
    ///         working and accumulating rewards until fully depleted. Then it must be retired and unstaked.
    /// @param chainIds Set of chain Ids with staking proxies.
    /// @param stakingProxies Set of staking proxies corresponding to each chain Id.
    /// @param statuses Corresponding staking model statuses.
    function setStakingModelStatuses(
        uint256[] memory chainIds,
        address[] memory stakingProxies,
        StakingModelStatus[] memory statuses
    ) external {
        // Check for ownership
        if (msg.sender != owner) {
            revert OwnerOnly(msg.sender, owner);
        }

        // Check for array length correctness
        if (chainIds.length == 0 || chainIds.length != stakingProxies.length || chainIds.length != statuses.length) {
            revert WrongArrayLength();
        }

        // Traverse staking models and statuses
        for (uint256 i = 0; i < chainIds.length; ++i) {
            // Get staking model Id
            // Push a pair of key defining variables into one key: chainId | stakingProxy
            // stakingProxy occupies first 160 bits, chainId occupies next bits as they both fit well in uint256
            uint256 stakingModelId = uint256(uint160(stakingProxies[i]));
            stakingModelId |= chainIds[i] << 160;

            // Check for staking model existence
            if (mapStakingModels[stakingModelId].supply == 0) {
                revert WrongStakingModel(stakingModelId);
            }

            mapStakingModels[stakingModelId].status = statuses[i];
        }

        emit ChangeModelStatuses(chainIds, stakingProxies, statuses);
    }

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
        // Reentrancy guard
        if (_locked) {
            revert ReentrancyGuard();
        }
        _locked = true;

        // Check for overflow
        if (stakeAmount > type(uint96).max) {
            revert Overflow(stakeAmount, type(uint96).max);
        }

        // Check for array lengths
        if (chainIds.length == 0 || chainIds.length != stakingProxies.length ||
            chainIds.length != bridgePayloads.length || chainIds.length != values.length) {
            revert WrongArrayLength();
        }

        if (stakeAmount > 0) {
            // Increase total account deposit amount
            mapAccountDeposits[msg.sender] += stakeAmount;

            // Get OLAS from sender
            IToken(olas).transferFrom(msg.sender, address(this), stakeAmount);
        }

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

        // Collect staking contracts and amounts
        for (uint256 i = 0; i < chainIds.length; ++i) {
            // Push a pair of key defining variables into one key: chainId | stakingProxy
            // stakingProxy occupies first 160 bits, chainId occupies next bits as they both fit well in uint256
            uint256 stakingModelId = uint256(uint160(stakingProxies[i]));
            stakingModelId |= chainIds[i] << 160;

            StakingModel memory stakingModel = mapStakingModels[stakingModelId];
            // Check for model existence and activity
            if (stakingModel.supply == 0 || stakingModel.status != StakingModelStatus.Active) {
                revert WrongStakingModel(stakingModelId);
            }

            // Skip potential zero funds models
            if (stakingModel.remainder == 0) {
                continue;
            }

            // Adjust staking amount to not overflow the max allowed one
            amounts[i] = remainder;
            if (amounts[i] > stakingModel.stakeLimitPerSlot) {
                amounts[i] = stakingModel.stakeLimitPerSlot;
            }

            if (amounts[i] > stakingModel.remainder) {
                amounts[i] = stakingModel.remainder;
                // Update staking model remainder
                mapStakingModels[stakingModelId].remainder = 0;
            } else {
                // Update staking model remainder
                mapStakingModels[stakingModelId].remainder = stakingModel.remainder - uint96(amounts[i]);
            }

            // Adjust remainder
            remainder -= amounts[i];
            // Increase actual stake amount
            actualStakeAmount += amounts[i];

            // Get Deposit Processor address
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

    /// @dev Calculates amounts and initiates cross-chain unstake request for specified models by Treasury.
    /// @notice This action deducts reserves from their staked part and get them back as vault assets.
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
        // Reentrancy guard
        if (_locked) {
            revert ReentrancyGuard();
        }
        _locked = true;

        // Check for Treasury access
        if (msg.sender != treasury) {
            revert UnauthorizedAccount(msg.sender);
        }

        // Check array lengths
        if (chainIds.length == 0 || chainIds.length != stakingProxies.length ||
            chainIds.length != bridgePayloads.length || chainIds.length != values.length) {
            revert WrongArrayLength();
        }

        // Allocate arrays of max possible size
        amounts = new uint256[](chainIds.length);

        // Collect staking contracts and amounts
        for (uint256 i = 0; i < chainIds.length; ++i) {
            // Push a pair of key defining variables into one key: chainId | stakingProxy
            // stakingProxy occupies first 160 bits, chainId occupies next bits as they both fit well in uint256
            uint256 stakingModelId = uint256(uint160(stakingProxies[i]));
            stakingModelId |= chainIds[i] << 160;

            StakingModel memory stakingModel = mapStakingModels[stakingModelId];
            // Check for model existence
            if (stakingModel.supply == 0) {
                revert WrongStakingModel(stakingModelId);
            }

            // Adjust unstaking amount to not overflow the max allowed one
            amounts[i] = stakingModel.supply - stakingModel.remainder;
            if (amounts[i] > stakingModel.stakeLimitPerSlot) {
                amounts[i] = stakingModel.stakeLimitPerSlot;
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

            // Transfer OLAS to its corresponding Staker on L2
            IDepositProcessor(depositProcessor).sendMessage{value: values[i]}(stakingProxies[i], amounts[i],
                bridgePayloads[i], UNSTAKE);

            if (unstakeAmount == 0) {
                break;
            }
        }

        // Check if provided staking proxies result in necessary amount of tokens
        if (unstakeAmount > 0) {
            revert Overflow(unstakeAmount, 0);
        }

        emit Unstake(msg.sender, unstakeAmount, chainIds, stakingProxies, amounts);
    }

    /// @dev Retires specified models.
    /// @notice This action is irreversible and clears up staking model info.
    /// @param chainIds Set of chain Ids with staking proxies.
    /// @param stakingProxies Set of staking proxies corresponding to each chain Id.
    function retire(uint256[] memory chainIds, address[] memory stakingProxies) external {
        // Check array lengths
        if (chainIds.length == 0 || chainIds.length != stakingProxies.length) {
            revert WrongArrayLength();
        }

        // Traverse and delete retired models
        for (uint256 i = 0; i < chainIds.length; ++i) {
            // Push a pair of key defining variables into one key: chainId | stakingProxy
            // stakingProxy occupies first 160 bits, chainId occupies next bits as they both fit well in uint256
            uint256 stakingModelId = uint256(uint160(stakingProxies[i]));
            stakingModelId |= chainIds[i] << 160;

            StakingModel memory stakingModel = mapStakingModels[stakingModelId];
            // Check for retired model status
            if (stakingModel.status != StakingModelStatus.Retired) {
                revert WrongStakingModel(stakingModelId);
            }

            // Check for model existence and remainder as Staking Proxy must be fully unstaked
            if (stakingModel.supply == 0 || stakingModel.remainder != stakingModel.supply) {
                revert WrongStakingModel(stakingModelId);
            }

            // Remove staking model
            delete mapStakingModels[stakingModelId];
        }

        emit Retired(chainIds, stakingProxies);
    }

    /// @dev Gets number of all staking models that have been activated.
    function getNumStakingModels() external view returns (uint256) {
        return setStakingModelIds.length;
    }

    /// @dev Gets set of staking model Ids.
    function getSetStakingModelIds() external view returns (uint256[] memory) {
        return setStakingModelIds;
    }

    /// @dev Gets staking model Id by provided chain Id and staking proxy address.
    /// @param chainId Chain Id.
    /// @param stakingProxy Staking proxy address.
    function getStakingModelId(uint256 chainId, address stakingProxy) external pure returns (uint256) {
        return uint256(uint160(stakingProxy)) | (chainId << 160);
    }

    /// @dev Gets chain Id and staking proxy address by provided staking model Id.
    /// @param stakingModelId Staking model Id.
    function getChainIdAndStakingProxy(uint256 stakingModelId) external pure returns (uint256, address) {
        return ((stakingModelId >> 160), address(uint160(stakingModelId)));
    }
}