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

    /// @dev Calculates reserve and stake balances, and top-ups stOLAS or address(this).
    /// @param reserveAmount Additional reserve OLAS amount.
    /// @param stakeAmount Additional stake OLAS amount.
    /// @param topUp Top up amount to be sent or received.
    /// @param direction To stOLAS, if true, and to address(this) otherwise
    function syncStakeBalances(uint256 reserveAmount, uint256 stakeAmount, uint256 topUp, bool direction) external;

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

/// @dev Product type deposit overflow.
/// @param productType Current product type.
/// @param depositAmount Deposit amount.
error ProductTypeDepositOverflow(uint8 productType, uint256 depositAmount);

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

/// @dev Contract is paused.
error Paused();


// Product type enum
enum ProductType {
    Alpha,
    Beta,
    Final
}

// Staking model status enum
enum StakingModelStatus {
    Retired,
    Active,
    Inactive
}

// Staking model struct
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


/// @title Depository - Smart contract for the stOLAS Depository.
contract Depository is Implementation {
    event TreasuryUpdated(address indexed treasury);
    event LzOracleUpdated(address indexed lzOracle);
    event ProductTypeUpdated(ProductType productType);
    event SetDepositProcessorChainIds(address[] depositProcessors, uint256[] chainIds);
    event StakingModelActivated(uint256 indexed chainId, address indexed stakingProxy, uint256 stakeLimitPerSlots,
        uint256 numSlots);
    event StakingModelStatusSet(uint256 indexed chainId, address indexed stakingProxy, StakingModelStatus status);
    event Deposit(address indexed sender, uint256 stakeAmount, uint256 stAmount, uint256[] chainIds,
        address[] stakingProxies, uint256[] amounts);
    event Unstake(address indexed sender, uint256 unstakeAmount, uint256[] chainIds, address[] stakingProxies,
        uint256[] amounts);
    event Retired(uint256[] chainIds, address[] stakingProxies);
    event PausedDepository();
    event UnpausedDepository();

    // Depository version
    string public constant VERSION = "0.1.0";
    // Stake operation
    bytes32 public constant STAKE = 0x1bcc0f4c3fad314e585165815f94ecca9b96690a26d6417d7876448a9a867a69;
    // Unstake operation
    bytes32 public constant UNSTAKE = 0x8ca9a95e41b5eece253c93f5b31eed1253aed6b145d8a6e14d913fdf8e732293;
    // Unstake-retired operation
    bytes32 public constant UNSTAKE_RETIRED = 0x9065ad15d9673159e4597c86084aff8052550cec93c5a6e44b3f1dba4c8731b3;
    // Alpha product type deposit amount limit
    uint256 public constant ALPHA_DEPOSIT_LIMIT = 1_000 ether;
    // Beta product type deposit amount limit
    uint256 public constant BETA_DEPOSIT_LIMIT = 10_000 ether;

    // OLAS contract address
    address public immutable olas;
    // stOLAS contract address
    address public immutable st;

    // Treasury contract address
    address public treasury;
    // Layer Zero oracle
    address public lzOracle;

    // Lock factor in 10_000 value
    uint256 public lockFactor;
    // Contract pause status
    bool public paused;
    // Product type value
    ProductType public productType;

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

    /// @dev Creates and activates staking model.
    /// @param chainId Chain Id.
    /// @param stakingProxy Corresponding staking proxy address.
    /// @param stakeLimitPerSlot Corresponding staking limit per each staking slot.
    /// @param numSlots Corresponding number of staking slots.
    function _createAndActivateStakingModel(
        uint256 chainId,
        address stakingProxy,
        uint256 stakeLimitPerSlot,
        uint256 numSlots
    ) internal {
        uint256 supply = stakeLimitPerSlot * numSlots;

        // Check for overflow
        if (supply > type(uint96).max) {
            revert Overflow(supply, type(uint96).max);
        }

        // Check for zero value
        if (supply == 0) {
            revert ZeroValue();
        }

        // Check for zero address
        if (stakingProxy == address(0)) {
            revert ZeroAddress();
        }

        // Push a pair of key defining variables into one key: chainId | stakingProxy
        // stakingProxy occupies first 160 bits, chainId occupies next bits as they both fit well in uint256
        uint256 stakingModelId = uint256(uint160(stakingProxy));
        stakingModelId |= chainId << 160;

        // Get staking model struct
        StakingModel storage stakingModel = mapStakingModels[stakingModelId];

        // Check for existing staking model
        if (stakingModel.supply > 0) {
            revert StakingModelAlreadyExists(stakingModelId);
        }

        // Set supply and activate
        stakingModel.supply = uint96(supply);
        stakingModel.remainder = uint96(supply);
        stakingModel.stakeLimitPerSlot = uint96(stakeLimitPerSlot);
        stakingModel.status = StakingModelStatus.Active;

        // Add into global staking model set
        setStakingModelIds.push(stakingModelId);

        emit StakingModelActivated(chainId, stakingProxy, stakeLimitPerSlot, numSlots);
    }

    /// @dev Sets staking model status.
    /// @param chainId Chain Id.
    /// @param stakingProxy Corresponding staking proxy address.
    /// @param status Corresponding staking model status.
    function _setStakingModelStatus(uint256 chainId, address stakingProxy, StakingModelStatus status) internal {
        // Get staking model Id
        // Push a pair of key defining variables into one key: chainId | stakingProxy
        // stakingProxy occupies first 160 bits, chainId occupies next bits as they both fit well in uint256
        uint256 stakingModelId = uint256(uint160(stakingProxy));
        stakingModelId |= chainId << 160;

        // Check for staking model existence
        if (mapStakingModels[stakingModelId].supply == 0) {
            revert WrongStakingModel(stakingModelId);
        }

        mapStakingModels[stakingModelId].status = status;

        emit StakingModelStatusSet(chainId, stakingProxy, status);
    }

    /// @dev Sends message according to the required operation: stake, unstake, etc.
    /// @param chainIds Set of chain Ids with staking proxies.
    /// @param stakingProxies Set of staking proxies corresponding to each chain Id.
    /// @param amounts Corresponding OLAS amounts for each staking proxy.
    /// @param bridgePayloads Bridge payloads corresponding to each chain Id.
    /// @param values Value amounts for each bridge interaction, if applicable.
    /// @param operation Operation type.
    function _operationSendMessage(
        uint256[] memory chainIds,
        address[] memory stakingProxies,
        uint256[] memory amounts,
        bytes[] memory bridgePayloads,
        uint256[] memory values,
        bytes32 operation
    ) private {
        for (uint256 i = 0; i < chainIds.length; ++i) {
            if (amounts[i] == 0) continue;

            // Get corresponding deposit processor
            address depositProcessor = mapChainIdDepositProcessors[chainIds[i]];

            // Check for zero address
            if (depositProcessor == address(0)) {
                revert ZeroAddress();
            }

            // Stake related only
            if (operation == STAKE) {
                // Transfer OLAS to depositProcessor
                IToken(olas).transfer(depositProcessor, amounts[i]);
            }

            // Perform operation on corresponding Staker on L2
            IDepositProcessor(depositProcessor).sendMessage{value: values[i]}(stakingProxies[i], amounts[i],
                bridgePayloads[i], operation);
        }
    }

    /// @dev Depository initializer.
    function initialize() external{
        // Check for already initialized
        if (owner != address(0)) {
            revert AlreadyInitialized();
        }

        productType = ProductType.Alpha;
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

    /// @dev Changes Layer Zero oracle contract address.
    /// @param newLzOracle Address of a new lzOracle.
    function changeLzOracle(address newLzOracle) external {
        // Check for ownership
        if (msg.sender != owner) {
            revert OwnerOnly(msg.sender, owner);
        }

        // Check for zero address
        if (newLzOracle == address(0)) {
            revert ZeroAddress();
        }

        lzOracle = newLzOracle;
        emit LzOracleUpdated(newLzOracle);
    }

    /// @dev Changes product type.
    /// @param newProductType New product type.
    function changeProductType(ProductType newProductType) external {
        // Check for ownership
        if (msg.sender != owner) {
            revert OwnerOnly(msg.sender, owner);
        }
        
        productType = newProductType;
        emit ProductTypeUpdated(newProductType);
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

        // Traverse all staking models
        for (uint256 i = 0; i < chainIds.length; ++i) {
            // Create and activate staking model
            _createAndActivateStakingModel(chainIds[i], stakingProxies[i], stakeLimitPerSlots[i], numSlots[i]);
        }
    }

    /// @dev Creates and activates staking model via lzRead proofs.
    /// @param chainId Chain Id.
    /// @param stakingProxy Corresponding staking proxy address.
    /// @param stakeLimitPerSlot Corresponding staking limit per each staking slot.
    /// @param numSlots Corresponding number of staking slots.
    function LzCreateAndActivateStakingModel(
        uint256 chainId,
        address stakingProxy,
        uint256 stakeLimitPerSlot,
        uint256 numSlots
    ) external {
        if (msg.sender != lzOracle) {
            revert UnauthorizedAccount(msg.sender);
        }

        // Create and activate staking model
        _createAndActivateStakingModel(chainId, stakingProxy, stakeLimitPerSlot, numSlots);
    }

    /// @dev Closes staking model via lzRead proofs.
    /// @param chainId Chain Id.
    /// @param stakingProxy Corresponding staking proxy address.
    function LzCloseStakingModel(uint256 chainId, address stakingProxy) external {
        if (msg.sender != lzOracle) {
            revert UnauthorizedAccount(msg.sender);
        }

        // Retire staking model
        _setStakingModelStatus(chainId, stakingProxy, StakingModelStatus.Retired);
    }

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
            _setStakingModelStatus(chainIds[i], stakingProxies[i], statuses[i]);
        }
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

        // Check if contract is paused
        if (paused) {
            revert Paused();
        }

        // Check for contract product type and limits
        if ((productType == ProductType.Alpha && stakeAmount > ALPHA_DEPOSIT_LIMIT) ||
            (productType == ProductType.Beta && stakeAmount > BETA_DEPOSIT_LIMIT))
        {
            revert ProductTypeDepositOverflow(uint8(productType), stakeAmount);
        }

        // Check for overflow
        if (stakeAmount > type(uint96).max) {
            revert Overflow(stakeAmount, type(uint96).max);
        }

        // Check for array lengths
        if (chainIds.length == 0 || chainIds.length != stakingProxies.length ||
            chainIds.length != bridgePayloads.length || chainIds.length != values.length) {
            revert WrongArrayLength();
        }

        // Get stOLAS reserve balance for staking
        uint256 stReserveBalance = IST(st).reserveBalance();
        // Actual remainder is equal to stake amount plus reserve balance
        // If stakeAmount is zero, stakes are performed from reserves
        uint256 actualRemainder = stakeAmount + stReserveBalance;

        // Check for zero value
        if (actualRemainder == 0) {
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

            // Skip zero available funds model
            if (stakingModel.remainder == 0) {
                continue;
            }

            // Adjust staking amount to not overflow the max allowed one
            amounts[i] = actualRemainder;
            // Upper limit
            if (amounts[i] > stakingModel.stakeLimitPerSlot) {
                amounts[i] = stakingModel.stakeLimitPerSlot;
            }

            // Lower limit
            if (amounts[i] > stakingModel.remainder) {
                amounts[i] = stakingModel.remainder;
                // Update staking model remainder
                mapStakingModels[stakingModelId].remainder = 0;
            } else {
                // Update staking model remainder
                mapStakingModels[stakingModelId].remainder = stakingModel.remainder - uint96(amounts[i]);
            }

            // Adjust actualRemainder
            actualRemainder -= amounts[i];
            // Increase actual stake amount
            actualStakeAmount += amounts[i];

            if (actualRemainder == 0) {
                break;
            }
        }

        // Deposit provided stake amount
        if (stakeAmount > 0) {
            // Increase total account deposit amount
            mapAccountDeposits[msg.sender] += stakeAmount;

            // Calculates stAmount and mints stOLAS
            stAmount = IST(st).deposit(stakeAmount, msg.sender);

            // Get OLAS from sender
            IToken(olas).transferFrom(msg.sender, address(this), stakeAmount);
        }

        uint256 topUp;
        // If provided stake amount is not fully utilized for stake, approve it for transfer to stOLAS
        // The following holds true: actualRemainder + actualStakeAmount = stReserveBalance + stakeAmount
        // There are two cases possible
        if (actualRemainder > stReserveBalance) {
            // Since actualRemainder accounts for partial stakeAmount as well if it exceeds stReserveBalance,
            // that partial amount from stakeAmount must be deposited to stOLAS to cover that difference

            // Calculate OLAS leftovers that are not going to be staked now
            topUp = actualRemainder - stReserveBalance;
            IToken(olas).approve(st, topUp);

            // Top up stOLAS and record correct balances including leftovers for reserve and actual stake amount
            IST(st).syncStakeBalances(actualRemainder, actualStakeAmount, topUp, true);
        } else if (actualStakeAmount >= stakeAmount) {
            // Since actualStakeAmount accounts for partial stReserveBalance as well if it exceeds stakeAmount,
            // that partial amount from stReserveBalance must be deposited to address(this) to cover that difference
            // Note that actualStakeAmount == stakeAmount results in a zero topUp value, meaning OLAS is reserved
            // for sending to staking contracts, however st.stakedBalance must be updated

            // Calculate OLAS to be additionally deposited to address(this)
            topUp = actualStakeAmount - stakeAmount;

            // Pull required funds from stOLAS and record correct balances
            IST(st).syncStakeBalances(actualRemainder, actualStakeAmount, topUp, false);
        }
        // Note it is not possible such that actualRemainder > stReserveBalance && actualStakeAmount > stakeAmount,
        // as this would result in strict inequality: actualRemainder + actualStakeAmount >> stReserveBalance + stakeAmount

        // Send funds to staking via relevant deposit processors
        _operationSendMessage(chainIds, stakingProxies, amounts, bridgePayloads, values, STAKE);

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

            if (unstakeAmount == 0) {
                break;
            }
        }

        // Check if provided staking proxies result in necessary amount of tokens
        if (unstakeAmount > 0) {
            revert Overflow(unstakeAmount, 0);
        }

        // Request unstake via relevant deposit processors
        _operationSendMessage(chainIds, stakingProxies, amounts, bridgePayloads, values, UNSTAKE);

        emit Unstake(msg.sender, unstakeAmount, chainIds, stakingProxies, amounts);
    }

    /// @dev Calculates amounts and initiates cross-chain unstake request for specified retired models.
    /// @notice This action deducts reserves from their staked part and get them back as assets reserved for staking.
    /// @param chainIds Set of chain Ids with staking proxies.
    /// @param stakingProxies Set of staking proxies corresponding to each chain Id.
    /// @param bridgePayloads Bridge payloads corresponding to each chain Id.
    /// @param values Value amounts for each bridge interaction, if applicable.
    /// @return amounts Corresponding OLAS amounts for each staking proxy.
    function unstakeRetired(
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

        // Check array lengths
        if (chainIds.length == 0 || chainIds.length != stakingProxies.length ||
            chainIds.length != bridgePayloads.length || chainIds.length != values.length) {
            revert WrongArrayLength();
        }

        uint256 unstakeAmount;

        // Allocate arrays of max possible size
        amounts = new uint256[](chainIds.length);

        // Traverse and collect retired models amounts
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

            // Check for model existence
            if (stakingModel.supply == 0) {
                revert WrongStakingModel(stakingModelId);
            }

            // Skip if model is already fully unstaked
            if (stakingModel.remainder == stakingModel.supply) {
                continue;
            }

            // Adjust unstaking amount to not overflow the max allowed one
            amounts[i] = stakingModel.supply - stakingModel.remainder;
            if (amounts[i] > stakingModel.stakeLimitPerSlot) {
                amounts[i] = stakingModel.stakeLimitPerSlot;
            }

            // Update staking model remainder
            mapStakingModels[stakingModelId].remainder += uint96(amounts[i]);

            unstakeAmount += amounts[i];
        }

        // Request unstake for retired models via relevant deposit processors
        _operationSendMessage(chainIds, stakingProxies, amounts, bridgePayloads, values, UNSTAKE_RETIRED);

        emit Unstake(msg.sender, unstakeAmount, chainIds, stakingProxies, amounts);
    }

    /// @dev Close specified retired models.
    /// @notice This action is irreversible and clears up staking model info.
    /// @param chainIds Set of chain Ids with staking proxies.
    /// @param stakingProxies Set of staking proxies corresponding to each chain Id.
    function closeRetiredStakingModels(uint256[] memory chainIds, address[] memory stakingProxies) external {
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

    /// @dev Pauses contract.
    function pause() external {
        // Check for ownership
        if (msg.sender != owner) {
            revert OwnerOnly(msg.sender, owner);
        }

        paused = true;
        emit PausedDepository();
    }

    /// @dev Unpauses contract.
    function unpause() external {
        // Check for ownership
        if (msg.sender != owner) {
            revert OwnerOnly(msg.sender, owner);
        }

        paused = false;
        emit UnpausedDepository();
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