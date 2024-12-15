// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {ActivityModuleProxy} from "../l2/LockProxy.sol";
import "hardhat/console.sol";

interface IDepositProcessor {
    /// @dev Sends a single message to the L2 side via a corresponding bridge.
    /// @param target Staking target addresses.
    /// @param stakingShare Corresponding staking amount.
    /// @param bridgePayload Bridge payload necessary (if required) for a specific bridge relayer.
    /// @param transferAmount Actual OLAS amount to be transferred.
    function sendMessage(address target, uint256 stakingShare, bytes memory bridgePayload, uint256 transferAmount) external payable;
}

interface ITreasury {
    /// @dev Stakes OLAS to treasury for vault and veOLAS lock.
    /// @notice Tokens are taken from `msg.sender`'s balance.
    /// @param olasAmount OLAS amount.
    function stakeFunds(address account, uint256 olasAmount) external;
}

interface IToken {
    /// @dev Sets `amount` as the allowance of `spender` over the caller's tokens.
    /// @param spender Account address that will be able to transfer tokens on behalf of the caller.
    /// @param amount Token amount.
    /// @return True if the function execution is successful.
    function approve(address spender, uint256 amount) external returns (bool);

    /// @dev Transfers the token amount.
    /// @param to Address to transfer to.
    /// @param amount The amount to transfer.
    /// @return True if the function execution is successful.
    function transfer(address to, uint256 amount) external returns (bool);

    /// @dev Transfers the token amount that was previously approved up until the maximum allowance.
    /// @param from Account address to transfer from.
    /// @param to Account address to transfer to.
    /// @param amount Amount to transfer to.
    /// @return True if the function execution is successful.
    function transferFrom(address from, address to, uint256 amount) external returns (bool);

    /// @dev Mints tokens.
    /// @param account Account address.
    /// @param amount Token amount.
    function mint(address account, uint256 amount) external;

    /// @dev Burns tokens.
    /// @param amount Token amount.
    function burn(uint256 amount) external;
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

/// @dev Account is unauthorized.
/// @param account Account address.
error UnauthorizedAccount(address account);

error WrongStakingModel(uint256 modelId);

struct StakingModel {
    address stakingProxy;
    // TODO supply is renewable supposedly every epoch
    uint96 supply;
    uint96 remainder;
    uint64 chainId;
    bool active;
}

/// @title Depository - Smart contract for the stOLAS Depository.
contract Depository {
    event ImplementationUpdated(address indexed implementation);
    event OwnerUpdated(address indexed owner);
    event SetDepositProcessorChainIds(address[] depositProcessors, uint256[] chainIds);
    event SetGuardianServiceStatuses(address[] guardianServices, bool[] statuses);
    event AddStakingModels(address indexed sender, StakingModel[] stakingModels);
    event ChangeModelStatuses(uint256[] modelIds, bool[] statuses);
    event Deposit(address indexed sender, uint256 indexed modelId, uint256 olasAmount, uint256 stAmount);

    // Code position in storage is keccak256("DEPOSITORY_PROXY") = "0x40f951bb727bcaf251807e38aa34e1b3f20d890f9f3286454f4c473c60a21cdc"
    bytes32 public constant DEPOSITORY_PROXY = 0x40f951bb727bcaf251807e38aa34e1b3f20d890f9f3286454f4c473c60a21cdc;

    address public immutable olas;
    address public immutable st;
    address public immutable treasury;

    uint256 public numStakingModels;
    uint256 public depositCounter;
    uint256 public withdrawCounter;
    address public owner;
    address public oracle;

    uint256 internal _nonce;

    mapping(uint256 => StakingModel) public mapStakingModels;
    mapping(address => bool) public mapGuardianAgents;
    // Mapping for L2 chain Id => dedicated deposit processors
    mapping(uint256 => address) public mapChainIdDepositProcessors;

    // TODO change to initialize in prod
    constructor(address _olas, address _st, address _treasury, address _oracle) {
        olas = _olas;
        st = _st;
        treasury = _treasury;
        oracle = _oracle;

        owner = msg.sender;
    }

    /// @dev Contributors initializer.
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

    /// @dev Adds staking models.
    /// @param stakingModels Staking models.
    function addStakingModels(StakingModel[] memory stakingModels) external {
        // Check for ownership
        if (msg.sender != owner) {
            revert OwnerOnly(msg.sender, owner);
        }

        // TODO Check inputs or trust agent?

        uint256 localNum = numStakingModels;
        for (uint256 i = 0; i < stakingModels.length; ++i) {
            mapStakingModels[localNum] = stakingModels[i];
            ++localNum;
        }

        numStakingModels = localNum;

        emit AddStakingModels(msg.sender, stakingModels);
    }

    function changeModelStatuses(uint256[] memory modelIds, bool[] memory statuses) external {
        // Check for ownership
        if (msg.sender != owner) {
            revert OwnerOnly(msg.sender, owner);
        }

        // Check for array lengths
        if (modelIds.length == 0 || modelIds.length != statuses.length) {
            revert WrongArrayLength(modelIds.length, statuses.length);
        }

        uint256 localNum = numStakingModels;
        for (uint256 i = 0; i < modelIds.length; ++i) {
            if (modelIds[i] >= localNum) {
                revert Overflow(modelIds[i], localNum);
            }
            mapStakingModels[modelIds[i]].active = statuses[i];
        }
        
        emit ChangeModelStatuses(modelIds, statuses);
    }

    // TODO: array of modelId-s and olasAmount-s as on stake might not fit into one model
    function deposit(
        uint256 modelId,
        uint256 olasAmount,
        bytes memory bridgePayload
    ) external payable returns (uint256 stAmount) {
        // Get staking model
        StakingModel storage stakingModel = mapStakingModels[modelId];
        // Check for model existence and activity
        if (stakingModel.supply == 0 || !stakingModel.active) {
            revert WrongStakingModel(modelId);
        }

        if (olasAmount > type(uint96).max) {
            revert Overflow(olasAmount, uint256(type(uint96).max));
        }

        // Check for staking model remainder
        if (olasAmount > stakingModel.remainder) {
            revert Overflow(olasAmount, stakingModel.remainder);
        }

        // TODO This might be not needed
        stakingTerm.userSupply = uint96(olasAmount);

        // Update staking model remainder
        stakingModel.remainder = stakingModel.remainder - uint96(olasAmount);

        // Get stOLAS amount from the provided OLAS amount
        stAmount = getStAmount(olasAmount);

        // Get OLAS from sender
        IToken(olas).transferFrom(msg.sender, address(this), olasAmount);

        // Mint stOLAS
        IToken(st).mint(msg.sender, stAmount);

        // Transfer OLAS via the bridge
        address depositProcessor = mapChainIdDepositProcessors[stakingModel.chainId];
        IDepositProcessor(depositProcessor).sendMessage(stakingModel.stakingProxy, olasAmount, bridgePayload, olasAmount);

        emit Deposit(msg.sender, modelId, olasAmount, stAmount);
    }

    // TODO: renew lock, withdraw, evict by agent if not renewed? Then need to lock from the proxy controlled by the agent as well

    // Unlock veOLAS
    function unlock() public {
        uint256 userSupply = mapStakingTerms[msg.sender].userSupply;
        if (userSupply == 0) {
            revert ZeroValue();
        }

        ILock(mapStakingTerms[msg.sender].lockProxy).unlock(msg.sender, userSupply);
        mapStakingTerms[msg.sender].userSupply = 0;
    }

    function requestToWithdraw(uint256 stAmount) external {
        // TODO Math
        //IToken(st).transferFrom(msg.sender, address(this), stAmount);
    }

    function withdraw(uint256 stAmount) external {
        IToken(st).transferFrom(msg.sender, address(this), stAmount);

        // TODO For testing purposes now before the stOLAS math is fixed
        unlock();

        // Change for OLAS
        uint256 olasAmount = getOLASAmount(stAmount);

        // Burn stOLAS
        IToken(st).burn(stAmount);

        // Transfer OLAS
        IToken(olas).transfer(msg.sender, olasAmount);
    }

    function getStAmount(uint256 olasAmount) public view returns (uint256 stAmount) {
        stAmount = olasAmount;
    }

    // TODO: Fix math
    function getOLASAmount(uint256 stAmount) public view returns (uint256 olasAmount) {
        olasAmount = (stAmount * 1.00000001 ether) / 1 ether;
    }
}