// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {StakingBase} from "../lib/autonolas-registries/contracts/staking/StakingBase.sol";
import {SafeTransferLib} from "../lib/autonolas-registries/contracts/utils/SafeTransferLib.sol";

/// @dev Provided zero token address.
error ZeroTokenAddress();

// Service Registry Token Utility interface
interface IServiceTokenUtility {
    /// @dev Gets the service security token info.
    /// @param serviceId Service Id.
    /// @return Token address.
    /// @return Token security deposit.
    function mapServiceIdTokenDeposit(uint256 serviceId) external view returns (address, uint96);

    /// @dev Gets the agent Id bond in a specified service.
    /// @param serviceId Service Id.
    /// @param serviceId Agent Id.
    /// @return bond Agent Id bond in a specified service Id.
    function getAgentBond(uint256 serviceId, uint256 agentId) external view returns (uint256 bond);
}

/// @dev The staking token is wrong.
/// @param expected Expected staking token.
/// @param provided Provided staking token.
error WrongStakingToken(address expected, address provided);

/// @dev Received lower value than the expected one.
/// @param provided Provided value is lower.
/// @param expected Expected value.
error ValueLowerThan(uint256 provided, uint256 expected);

/// @title StakingProxyToken - Smart contract for staking a service with a proxy token stake
contract StakingProxyToken is StakingBase {
    // ServiceRegistryTokenUtility address
    address public serviceRegistryTokenUtility;
    // Security proxy token address for staking the proxy token
    address public stakingToken;
    // Rewards token address for staking the proxy token
    address public rewardToken;

    /// @dev StakingToken initialization.
    /// @param _stakingParams Service staking parameters.
    /// @param _serviceRegistryTokenUtility ServiceRegistryTokenUtility contract address.
    /// @param _stakingToken Address of a staking rewards token.
    /// @param _rewardToken Address of a service staking proxy token.
    function initialize(
        StakingParams memory _stakingParams,
        address _serviceRegistryTokenUtility,
        address _stakingToken,
        address _rewardToken
    ) external
    {
        _initialize(_stakingParams);

        // Initial checks
        if (_serviceRegistryTokenUtility == address(0) || _stakingToken == address(0) || _rewardToken == address(0)) {
            revert ZeroTokenAddress();
        }

        serviceRegistryTokenUtility = _serviceRegistryTokenUtility;
        stakingToken = _stakingToken;
        rewardToken = _rewardToken;
    }

    /// @dev Checks proxy token staking deposit.
    /// @param serviceId Service Id.
    /// @param serviceAgentIds Service agent Ids.
    function _checkTokenStakingDeposit(uint256 serviceId, uint256, uint32[] memory serviceAgentIds)
        internal virtual view override
    {
        // Get the service staking token and deposit
        (address token, uint96 stakingDeposit) =
            IServiceTokenUtility(serviceRegistryTokenUtility).mapServiceIdTokenDeposit(serviceId);

        // The staking token must match the contract token
        if (stakingToken != token) {
            revert WrongStakingToken(stakingToken, token);
        }

        uint256 minDeposit = minStakingDeposit;

        // The staking deposit must be greater or equal to the minimum defined one
        if (stakingDeposit < minDeposit) {
            revert ValueLowerThan(stakingDeposit, minDeposit);
        }

        // Check agent Id bonds to be not smaller than the minimum required deposit
        for (uint256 i = 0; i < serviceAgentIds.length; ++i) {
            uint256 bond = IServiceTokenUtility(serviceRegistryTokenUtility).getAgentBond(serviceId, serviceAgentIds[i]);
            if (bond < minDeposit) {
                revert ValueLowerThan(bond, minDeposit);
            }
        }
    }

    /// @dev Withdraws the reward amount to a service owner.
    /// @notice The balance is always greater or equal the amount, as follows from the Base contract logic.
    /// @param to Address to.
    /// @param amount Amount to withdraw.
    function _withdraw(address to, uint256 amount) internal virtual override {
        // Update the contract balance
        balance -= amount;

        SafeTransferLib.safeTransfer(rewardToken, to, amount);

        emit Withdraw(to, amount);
    }

    /// @dev Deposits funds for staking.
    /// @param amount Token amount to deposit.
    function deposit(uint256 amount) external {
        // Add to the contract and available rewards balances
        uint256 newBalance = balance + amount;
        uint256 newAvailableRewards = availableRewards + amount;

        // Record the new actual balance and available rewards
        balance = newBalance;
        availableRewards = newAvailableRewards;

        // Add to the overall balance
        SafeTransferLib.safeTransferFrom(rewardToken, msg.sender, address(this), amount);

        emit Deposit(msg.sender, amount, newBalance, newAvailableRewards);
    }
}