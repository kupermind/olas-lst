// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IService} from "./interfaces/IService.sol";
import {IStaking} from "./interfaces/IStaking.sol";
import {IToken, INFToken} from "./interfaces/IToken.sol";

/// @dev Only `owner` has a privilege, but the `sender` was provided.
/// @param sender Sender address.
/// @param owner Required sender address as an owner.
error OwnerOnly(address sender, address owner);

/// @dev Zero address.
error ZeroAddress();

/// @dev Zero value.
error ZeroValue();

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

/// @dev Caught reentrancy violation.
error ReentrancyGuard();

/// @dev Wrong staking instance.
/// @param stakingProxy Staking proxy address.
error WrongStakingInstance(address stakingProxy);

/// @dev Service is not found.
/// @param serviceId Service Id.
error ServiceNotFound(uint256 serviceId);

/// @dev Request Id already processed.
/// @param requestId Request Id.
error AlreadyProcessed(uint256 requestId);

/// @title StakerL2 - Smart contract for staking OLAS on L2.
contract StakerL2 {
    event OwnerUpdated(address indexed owner);
    event SetGuardianServiceStatuses(address[] guardianServices, bool[] statuses);
    event Stake(address indexed sender, address indexed account, uint256 indexed depositCounter, uint256 olasAmount);
    event CreateAndStake(address indexed stakingProxy, uint256 indexed serviceId, address indexed multisig);
    event Unstake(address indexed sender, address indexed stakingProxy, uint256 indexed serviceId);

    // Number of agent instances
    uint256 public constant NUM_AGENT_INSTANCES = 1;
    // Threshold
    uint256 public constant THRESHOLD = 1;
    // Contributor agent Id
    uint256 public immutable agentId;
    // Contributor service config hash
    bytes32 public immutable configHash;
    // Contributors proxy address
    address public immutable contributorsProxy;
    // Service manager address
    address public immutable serviceManager;
    // OLAS token address
    address public immutable olas;
    // OLAS proxy token address
    address public immutable proxyOlas;
    // Service registry address
    address public immutable serviceRegistry;
    // Service registry token utility address
    address public immutable serviceRegistryTokenUtility;
    // Staking factory address
    address public immutable stakingFactory;
    // Safe multisig processing contract address
    address public immutable safeMultisig;
    // Safe fallback handler
    address public immutable fallbackHandler;

    address public owner;

    // Nonce
    uint256 internal _nonce;
    // Reentrancy lock
    uint256 internal _locked = 1;

    mapping(address => bool) public mapGuardianAgents;
    mapping(uint256 => bool) public mapDeposits;
    mapping(address => uint256) public balanceOf;
    mapping(address => uint256) public mapStakingProxyBalances;
    mapping(uint256 => bool) public mapDepositCounters;
    mapping(address => uint256) public mapLastStakedServiceIds;

    /// @dev StakerL2 constructor.
    /// @param _serviceManager Service manager address.
    /// @param _olas OLAS token address.
    /// @param _proxyOlas OLAS proxy token address.
    /// @param _stakingFactory Staking factory address.
    /// @param _safeMultisig Safe multisig address.
    /// @param _fallbackHandler Multisig fallback handler address.
    /// @param _agentId Contributor agent Id.
    /// @param _configHash Contributor service config hash.
    constructor(
        address _serviceManager,
        address _olas,
        address _proxyOlas,
        address _stakingFactory,
        address _safeMultisig,
        address _fallbackHandler,
        uint256 _agentId,
        bytes32 _configHash
    ) {
        // Check for zero addresses
        if (_serviceManager == address(0) || _olas == address(0) || _proxyOlas == address(0) ||
            _stakingFactory == address(0) || _safeMultisig == address(0) || _fallbackHandler == address(0)) {
            revert ZeroAddress();
        }

        // Check for zero values
        if (_agentId == 0 || _configHash == 0) {
            revert ZeroValue();
        }

        agentId = _agentId;
        configHash = _configHash;

        serviceManager = _serviceManager;
        olas = _olas;
        proxyOlas = _proxyOlas;
        stakingFactory = _stakingFactory;
        safeMultisig = _safeMultisig;
        fallbackHandler = _fallbackHandler;
        serviceRegistry = IService(serviceManager).serviceRegistry();
        serviceRegistryTokenUtility = IService(serviceManager).serviceRegistryTokenUtility();

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

    /// @dev Creates and deploys a service.
    /// @param token Staking token address.
    /// @param minStakingDeposit Min staking deposit value.
    /// @return serviceId Minted service Id.
    /// @return multisig Service multisig.
    function _createAndDeploy(
        address token,
        uint256 minStakingDeposit
    ) internal returns (uint256 serviceId, address multisig) {
        // Set agent params
        IService.AgentParams[] memory agentParams = new IService.AgentParams[](NUM_AGENT_INSTANCES);
        agentParams[0] = IService.AgentParams(uint32(NUM_AGENT_INSTANCES), uint96(minStakingDeposit));

        // Set agent Ids
        uint32[] memory agentIds = new uint32[](NUM_AGENT_INSTANCES);
        agentIds[0] = uint32(agentId);

        // Set agent instances as [msg.sender]
        address[] memory instances = new address[](NUM_AGENT_INSTANCES);
        instances[0] = msg.sender;

        // Create a service owned by this contract
        serviceId = IService(serviceManager).create(address(this), token, configHash, agentIds,
            agentParams, uint32(THRESHOLD));

        // Activate registration (1 wei as a deposit wrapper)
        IService(serviceManager).activateRegistration{value: 1}(serviceId);

        // Register msg.sender as an agent instance (numAgentInstances wei as a bond wrapper)
        IService(serviceManager).registerAgents{value: NUM_AGENT_INSTANCES}(serviceId, instances, agentIds);

        // Prepare Safe multisig data
        uint256 localNonce = _nonce;
        uint256 randomNonce = uint256(keccak256(abi.encodePacked(block.timestamp, msg.sender, localNonce)));
        bytes memory data = abi.encodePacked(address(0), fallbackHandler, address(0), address(0), uint256(0),
            randomNonce, "0x");
        // Deploy the service
        multisig = IService(serviceManager).deploy(serviceId, safeMultisig, data);

        // Update the nonce
        _nonce = localNonce + 1;
    }

    /// @dev Stakes the already deployed service.
    /// @param serviceId Service Id.
    /// @param multisig Corresponding service multisig.
    /// @param stakingProxy Staking proxy address.
    function _stake(uint256 serviceId, address multisig, address stakingProxy) internal {
        // Approve service NFT for the staking instance
        INFToken(serviceRegistry).approve(stakingProxy, serviceId);

        // Stake the service
        IStaking(stakingProxy).stake(serviceId);
    }
    
    /// @dev Creates and deploys a service, and stakes it with a specified staking contract.
    /// @notice The service cannot be registered again if it is currently staked.
    /// @param stakingProxy Corresponding staking instance address.
    function _createAndStake(address stakingProxy, uint256 minStakingDeposit) internal {
        // Create and deploy service
        (uint256 serviceId, address multisig) = _createAndDeploy(proxyOlas, minStakingDeposit);

        // Stake the service
        _stake(serviceId, multisig, stakingProxy);

        // TODO create a cyclic map of service Ids?
        mapLastStakedServiceIds[stakingProxy] = serviceId;

        emit CreateAndStake(stakingProxy, serviceId, multisig);
    }

    /// @dev Finds the lasst staked service and unstakes it.
    /// @param stakingProxy Staking proxy address.
    function _unstake(address stakingProxy) internal {
        uint256 serviceId = mapLastStakedServiceIds[stakingProxy];

        if (serviceId == 0) {
            revert ServiceNotFound(serviceId);
        }

        // Unstake the service
        IStaking(stakingProxy).unstake(serviceId);

        emit Unstake(msg.sender, stakingProxy, serviceId);
    }
    
    // TODO: arrays
    function stake(address account, uint256 depositCounter, uint256 olasAmount, address stakingProxy) external payable {
        // Reentrancy guard
        if (_locked > 1) {
            revert ReentrancyGuard();
        }
        _locked = 2;

        // Check for whitelisted guardian agent
        if (!mapGuardianAgents[msg.sender]) {
            revert UnauthorizedAccount(msg.sender);
        }

        // Check for deposit counter
        if (mapDepositCounters[depositCounter]) {
            revert AlreadyProcessed(depositCounter);
        }
        mapDepositCounters[depositCounter] = true;

        // TODO: check that stakingProxy is able to host another service
        if (!isAbleStake(stakingProxy, olasAmount)) {
            revert();
        }

        balanceOf[account] += olasAmount;
        // Mint stOLASL2
        IToken(proxyOlas).mint(address(this), olasAmount);

        uint256 balance = mapStakingProxyBalances[stakingProxy];
        uint256 minStakingDeposit = IStaking(stakingProxy).minStakingDeposit();
        uint256 stakeDeposit = minStakingDeposit * (1 + NUM_AGENT_INSTANCES);

        balance += olasAmount;
        if (balance >= stakeDeposit) {
            // Approve token for the serviceRegistryTokenUtility contract
            IToken(proxyOlas).approve(serviceRegistryTokenUtility, stakeDeposit);

            // TODO Find if there's a service for this stake already
            
            _createAndStake(stakingProxy, minStakingDeposit);

            balance -= stakeDeposit;
        }
        mapStakingProxyBalances[stakingProxy] = balance;

        emit Stake(msg.sender, account, depositCounter, olasAmount);

        _locked = 1;
    }

    // TODO arrays
    function withdraw(address account, uint256 withdrawCounter, uint256 olasAmount, address stakingProxy) external {
        // Reentrancy guard
        if (_locked > 1) {
            revert ReentrancyGuard();
        }
        _locked = 2;

        // Check for whitelisted guardian agent
        if (!mapGuardianAgents[msg.sender]) {
            revert UnauthorizedAccount(msg.sender);
        }

        uint256 balance = balanceOf[account];
        if (balance < olasAmount) {
            revert();
        }
        balanceOf[account] -= olasAmount;

        balance = mapStakingProxyBalances[stakingProxy];
        if (balance > olasAmount) {
            balance -= olasAmount;
        } else {
            if (!isAbleWithdraw(stakingProxy, olasAmount)) {
                revert();
            }

            _unstake(stakingProxy);
            uint256 unstakeAmount = (1 + NUM_AGENT_INSTANCES) * IStaking(stakingProxy).minStakingDeposit();
            balance = unstakeAmount - (olasAmount - balance);
        }
        mapStakingProxyBalances[stakingProxy] = balance;

        // Burn stOLASL2
        IToken(proxyOlas).burn(olasAmount);

        _locked = 1;
    }

    function isAbleStake(address stakingProxy, uint256 olasAmount) public view returns (bool) {
        // Check for staking instance validity
        if(!IStaking(stakingFactory).verifyInstance(stakingProxy)) {
            revert WrongStakingInstance(stakingProxy);
        }

        // Get the token info from the staking contract
        // If this call fails, it means the staking contract does not have a token and is not compatible
        address token = IStaking(stakingProxy).stakingToken();
        // Check the token address
        if (token != proxyOlas) {
            revert WrongStakingInstance(stakingProxy);
        }

        // Get other service info for staking
        uint256 minStakingDeposit = IStaking(stakingProxy).minStakingDeposit();
        uint256 numAgentInstances = IStaking(stakingProxy).numAgentInstances();
        uint256 threshold = IStaking(stakingProxy).threshold();
        // Check for number of agent instances that must be equal to one,
        // since msg.sender is the only service multisig owner
        if ((numAgentInstances > 0 &&  numAgentInstances != NUM_AGENT_INSTANCES) ||
            (threshold > 0 && threshold != THRESHOLD)) {
            revert WrongStakingInstance(stakingProxy);
        }

        return true;
    }

    function isAbleWithdraw(address stakingProxy, uint256 olasAmount) public view returns (bool) {
        return true;
    }
}