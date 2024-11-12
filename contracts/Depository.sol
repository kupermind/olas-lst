// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

interface IToken {
    /// @dev Sets `amount` as the allowance of `spender` over the caller's tokens.
    /// @param spender Account address that will be able to transfer tokens on behalf of the caller.
    /// @param amount Token amount.
    /// @return True if the function execution is successful.
    function approve(address spender, uint256 amount) external returns (bool);

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
}

interface IVotingEscrow {
    /// @dev Deposits `amount` tokens for `account` and locks for `unlockTime`.
    /// @notice Tokens are taken from `msg.sender`'s balance.
    /// @param account Account address.
    /// @param amount Amount to deposit.
    /// @param unlockTime Time when tokens unlock, rounded down to a whole week.
    function createLockFor(address account, uint256 amount, uint256 unlockTime) external;
}

/// @dev Only `owner` has a privilege, but the `sender` was provided.
/// @param sender Sender address.
/// @param owner Required sender address as an owner.
error OwnerOnly(address sender, address owner);

/// @dev Zero address.
error ZeroAddress();

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
    address stakingContract;
    uint96 supply;
    uint96 remainder;
    uint64 vesting;
    uint64 chainId;
    bool active;
}

/// @title Depository - Smart contract for the stOLAS Depository.
contract Depository {
    event ImplementationUpdated(address indexed implementation);
    event OwnerUpdated(address indexed owner);
    event SetGuardianServiceStatuses(address[] contributeServices, bool[] statuses);
    event AddStakingModels(address indexed sender, StakingModel[] stakingModels);
    event ChangeModelStatuses(uint256[] modelIds, bool[] statuses);
    event Deposit(address indexed sender, uint256 indexed modelId, uint256 olasAmount, uint256 stAmount);

    address public immutable olas;
    address public immutable ve;
    address public immutable st;

    uint256 public numStakingModels;
    address public owner;
    address public oracle;

    mapping(uint256 => StakingModel) public mapStakingModels;
    mapping(address => bool) public mapGuardianAgents;
    
    constructor(address _olas, address _ve, address _st, address _oracle) {
        olas = _olas;
        ve = _ve;
        st = _st;
        oracle = _oracle;

        owner = msg.sender;
    }

    /// @dev Changes contract owner address.
    /// @param newOwner Address of a new owner.
    function changeOwner(address newOwner) external {
        // Check for the ownership
        if (msg.sender != owner) {
            revert OwnerOnly(msg.sender, owner);
        }

        // Check for the zero address
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
        // Check for the ownership
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

    /// @dev Adds staking models.
    /// @param stakingModels Staking models.
    function addStakingModels(StakingModel[] memory stakingModels) external {
        // Check for whitelisted guardian agent
        if (!mapGuardianAgents[msg.sender]) {
            revert UnauthorizedAccount(msg.sender);
        }

        // TODO Check inputs or trust agent?

        uint256 localNum = numStakingModels;
        for(uint256 i = 0; i < stakingModels.length; ++i) {
            mapStakingModels[localNum] = stakingModels[i];
            ++localNum;
        }

        numStakingModels = localNum;

        emit AddStakingModels(msg.sender, stakingModels);
    }

    function changeModelStatuses(uint256[] memory modelIds, bool[] memory statuses) external {
        // Check for whitelisted guardian agent
        if (!mapGuardianAgents[msg.sender]) {
            revert UnauthorizedAccount(msg.sender);
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

    function deposit(uint256 modelId, uint256 olasAmount) external returns (uint256 stAmount) {
        // Get staking model
        StakingModel storage stakingModel = mapStakingModels[modelId];
        // Check for model existence and activity
        if (stakingModel.supply == 0 || !stakingModel.active) {
            revert WrongStakingModel(modelId);
        }

        // Get stOLAS amount from the provided OLAS amount
        stAmount = getStAmount(olasAmount);

        // Get OLAS from the sender
        IToken(olas).transferFrom(msg.sender, address(this), olasAmount);
        // Approve OLAS for veOLAS
        IToken(olas).approve(ve, olasAmount);
        // Lock OLAS for veOLAS
        IVotingEscrow(ve).createLockFor(msg.sender, olasAmount, stakingModel.vesting);
        // Mint stOLAS
        IToken(st).mint(msg.sender, stAmount);

        emit Deposit(msg.sender, modelId, olasAmount, stAmount);
    }

    // TODO: renew lock, withdraw, evict by agent if not renewed? Then need to lock from the proxy controlled by the agent as well

    function getStAmount(uint256 olasAmount) public view returns (uint256 stAmount) {
        stAmount = olasAmount;
    }
}