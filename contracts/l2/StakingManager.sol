// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {ERC721TokenReceiver} from "../../lib/autonolas-registries/lib/solmate/src/tokens/ERC721.sol";
import {ActivityModuleProxy} from "./ActivityModuleProxy.sol";
import {IService} from "../interfaces/IService.sol";
import {IStaking} from "../interfaces/IStaking.sol";
import {IToken, INFToken} from "../interfaces/IToken.sol";
import "hardhat/console.sol";

// Multisig interface
interface IMultisig {
    /// @dev Returns array of owners.
    /// @return Array of Safe owners.
    function getOwners() external view returns (address[] memory);
}

interface ITokenRelayer {
    function relayToL1(uint256 olasAmount) external payable;
}

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

/// @dev Request Id already processed.
/// @param requestId Request Id.
error AlreadyProcessed(uint256 requestId);

/// @title StakingManager - Smart contract for OLAS staking management
contract StakingManager is ERC721TokenReceiver {
    event OwnerUpdated(address indexed owner);
    event TokenRelayerUpdated(address indexed l2StakingProcessor);
    event SetGuardianServiceStatuses(address[] guardianServices, bool[] statuses);
    event StakingBalanceUpdated(address indexed stakingProxy, uint256 balance);
    event CreateAndStake(address indexed stakingProxy, uint256 indexed serviceId, address indexed multisig);
    event DeployAndStake(address indexed stakingProxy, uint256 indexed serviceId, address indexed multisig);
    event Unstake(address indexed sender, address indexed stakingProxy, uint256 indexed serviceId);

    // Safe module payload
    bytes public constant SAFE_MODULE_PAYLOAD = 0xfe51f64300000000000000000000000029fcb43b46531bca003ddc8fcb67ffe91900c762;
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
    // Service registry address
    address public immutable serviceRegistry;
    // Service registry token utility address
    address public immutable serviceRegistryTokenUtility;
    // Staking factory address
    address public immutable stakingFactory;
    // Safe multisig processing contract address
    address public immutable safeMultisig;
    // Safe same address multisig processing contract address
    address public immutable safeSameAddressMultisig;
    /// Safe module initializer address
    address public immutable safeModuleInitializer;
    // Safe fallback handler
    address public immutable fallbackHandler;
    // OLAS collector address
    address public immutable collector;
    // Activity module beacon
    address public immutable beacon;

    // L2 staking processor address
    address public l2StakingProcessor;
    // Owner address
    address public owner;

    // Nonce
    uint256 internal _nonce;
    // Reentrancy lock
    uint256 internal _locked = 1;

    mapping(address => bool) public mapGuardianAgents;
    mapping(uint256 => bool) public mapDeposits;
    mapping(address => uint256) public balanceOf;
    mapping(address => uint256) public mapStakingProxyBalances;
    mapping(address => uint256[]) public mapStakedServiceIds;
    mapping(uint256 => address) public mapServiceIdActivityModules;
    mapping(address => uint256) public mapLastStakedServiceIdxs;

    /// @dev StakerL2 constructor.
    /// @param _olas OLAS token address.
    /// @param _serviceManager Service manager address.
    /// @param _stakingFactory Staking factory address.
    /// @param _safeMultisig Safe multisig address.
    /// @param _safeSameAddressMultisig Safe multisig processing contract address.
    /// @param _beacon Activity module beacon.
    /// @param _safeModuleInitializer Safe module initializer address.
    /// @param _fallbackHandler Multisig fallback handler address.
    /// @param _collector OLAS collector address.
    /// @param _agentId Contributor agent Id.
    /// @param _configHash Contributor service config hash.
    constructor(
        address _olas,
        address _serviceManager,
        address _stakingFactory,
        address _safeMultisig,
        address _safeSameAddressMultisig,
        address _beacon,
        address _safeModuleInitializer,
        address _fallbackHandler,
        address _collector,
        uint256 _agentId,
        bytes32 _configHash
    ) {
        // Check for zero addresses
        if (_serviceManager == address(0) || _olas == address(0) || _stakingFactory == address(0) ||
            _safeMultisig == address(0) || _safeSameAddressMultisig == address(0) || _beacon ==address(0) ||
            _safeModuleInitializer ==address(0) || _fallbackHandler == address(0) || _collector == address(0)) {
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
        stakingFactory = _stakingFactory;
        safeMultisig = _safeMultisig;
        safeSameAddressMultisig = _safeSameAddressMultisig;
        beacon = _beacon;
        safeModuleInitializer = _safeModuleInitializer;
        fallbackHandler = _fallbackHandler;
        collector = _collector;
        serviceRegistry = IService(serviceManager).serviceRegistry();
        serviceRegistryTokenUtility = IService(serviceManager).serviceRegistryTokenUtility();

        owner = msg.sender;
    }

    function initialize(address _l2StakingProcessor) external {
        if (owner != address(0)) {
            revert AlreadyInitialized();
        }

        if (_l2StakingProcessor == address(0)) {
            revert ZeroAddress();
        }
        l2StakingProcessor = _l2StakingProcessor;
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

    /// @dev Changes token relayer address.
    /// @param newTokenRelayer Address of a new owner.
    function changeTokenRelayer(address newTokenRelayer) external {
        // Check for the ownership
        if (msg.sender != owner) {
            revert OwnerOnly(msg.sender, owner);
        }

        // Check for the zero address
        if (newTokenRelayer == address(0)) {
            revert ZeroAddress();
        }

        l2StakingProcessor = newTokenRelayer;
        emit TokenRelayerUpdated(newTokenRelayer);
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

        // Create activity module proxy
        ActivityModuleProxy activityModuleProxy = new ActivityModuleProxy(olas, beacon);
        // Assign address as agent instance
        instances[0] = address(activityModuleProxy);//msg.sender; // new ActivityModuleProxy

        // Create a service owned by this contract
        serviceId = IService(serviceManager).create(address(this), token, configHash, agentIds,
            agentParams, uint32(THRESHOLD));

        // Initialize activity module
        IActivityModule(instances[0]).initialize();
        // Record activity module
        mapServiceIdActivityModules[serviceId] = instances[0];

        // Activate registration (1 wei as a deposit wrapper)
        IService(serviceManager).activateRegistration{value: 1}(serviceId);

        // Register msg.sender as an agent instance (numAgentInstances wei as a bond wrapper)
        IService(serviceManager).registerAgents{value: NUM_AGENT_INSTANCES}(serviceId, instances, agentIds);

        // Prepare Safe multisig data
        uint256 localNonce = _nonce;
        uint256 randomNonce = uint256(keccak256(abi.encodePacked(block.timestamp, msg.sender, localNonce)));
        bytes memory data = abi.encodePacked(safeModuleInitializer, fallbackHandler, address(0), address(0), uint256(0),
            randomNonce, SAFE_MODULE_PAYLOAD);
        // Deploy the service
        multisig = IService(serviceManager).deploy(serviceId, safeMultisig, data);

        // Update the nonce
        _nonce = localNonce + 1;
    }

    /// @dev Stakes the already deployed service.
    /// @param stakingProxy Staking proxy address.
    /// @param serviceId Service Id.
    function _stake(address stakingProxy, uint256 serviceId) internal {
        // Approve service NFT for the staking instance
        INFToken(serviceRegistry).approve(stakingProxy, serviceId);

        // Stake the service
        IStaking(stakingProxy).stake(serviceId);

        // Record last service Id index
        mapLastStakedServiceIdxs[stakingProxy] = mapStakedServiceIds[stakingProxy].length;
        mapStakedServiceIds[stakingProxy].push(serviceId);
    }
    
    /// @dev Creates and deploys a service, and stakes it with a specified staking contract.
    /// @notice The service cannot be registered again if it is currently staked.
    /// @param stakingProxy Corresponding staking instance address.
    function _createAndStake(address stakingProxy, uint256 minStakingDeposit) internal {
        // Create and deploy service
        (uint256 serviceId, address multisig) = _createAndDeploy(olas, minStakingDeposit);

        // TODO Initialize ActivityModuleProxy

        // Stake the service
        _stake(stakingProxy, serviceId);

        emit CreateAndStake(stakingProxy, serviceId, multisig);
    }

    /// @dev Stakes the already deployed service.
    /// @param stakingProxy Staking proxy address.
    /// @param serviceId Service Id.
    function _deployAndStake(address stakingProxy, uint256 serviceId) internal {
        // Get the service multisig
        (, address multisig, , , , , ) = IService(serviceRegistry).mapServices(serviceId);

        // Activate registration (1 wei as a deposit wrapper)
        IService(serviceManager).activateRegistration{value: 1}(serviceId);

        address[] memory instances = IMultisig(multisig).getOwners();
        // Get agent Ids
        uint32[] memory agentIds = new uint32[](NUM_AGENT_INSTANCES);
        agentIds[0] = uint32(agentId);

        // Register msg.sender as an agent instance (numAgentInstances wei as a bond wrapper)
        IService(serviceManager).registerAgents{value: NUM_AGENT_INSTANCES}(serviceId, instances, agentIds);

        // Re-deploy the service
        bytes memory data = abi.encodePacked(multisig);
        IService(serviceManager).deploy(serviceId, safeSameAddressMultisig, data);

        // Stake the service
        _stake(stakingProxy, serviceId);

        emit DeployAndStake(stakingProxy, serviceId, multisig);
    }

    /// @dev Finds the last staked Id service and unstakes it.
    /// @param stakingProxy Staking proxy address.
    /// @return unstakeAmount Unstake amount for service termination and unbond.
    function _unstake(address stakingProxy) internal returns (uint256 unstakeAmount) {
        // Get the last staked Service Id index
        uint256 lastIdx = mapLastStakedServiceIdxs[stakingProxy];
        uint256 serviceId = mapStakedServiceIds[stakingProxy][lastIdx];
        if (lastIdx > 0) {
            mapLastStakedServiceIdxs[stakingProxy] = lastIdx - 1;
        }

        // Unstake the service
        uint256 reward = IStaking(stakingProxy).unstake(serviceId);

        // Terminate and unbond
        (, unstakeAmount) = IService(serviceManager).terminate(serviceId);
        (, uint256 refund) = IService(serviceManager).unbond(serviceId);
        unstakeAmount += reward + refund;

        emit Unstake(msg.sender, stakingProxy, serviceId);
    }
    
    function stake(address[] memory stakingProxies, uint256[] memory amounts, uint256 totalAmount) external virtual {
        // Reentrancy guard
        if (_locked > 1) {
            revert ReentrancyGuard();
        }
        _locked = 2;

        // Check for StakingProcessor access
        if (msg.sender != l2StakingProcessor) {
            revert UnauthorizedAccount(msg.sender);
        }

        IToken(olas).transferFrom(l2StakingProcessor, address(this), totalAmount);

        for (uint256 i = 0; i < stakingProxies.length; ++i) {
            // TODO: check that stakingProxy is able to host another service
            if (!isAbleStake(stakingProxies[i], amounts[i])) {
                revert();
            }

            // TODO How many stakes are needed?

            uint256 balance = mapStakingProxyBalances[stakingProxies[i]];
            uint256 lastBalance = balance;
            uint256 minStakingDeposit = IStaking(stakingProxies[i]).minStakingDeposit();
            uint256 stakeDeposit = minStakingDeposit * (1 + NUM_AGENT_INSTANCES);

            balance += amounts[i];
            // Check if the balance is enough to create another stake
            if (balance >= stakeDeposit) {
                // Approve token for the serviceRegistryTokenUtility contract
                IToken(olas).approve(serviceRegistryTokenUtility, stakeDeposit);

                // Get already existent service or create a new one
                uint256 lastIdx = mapLastStakedServiceIdxs[stakingProxies[i]] + 1;
                uint256 serviceId;
                if (lastIdx < mapStakedServiceIds[stakingProxies[i]].length) {
                    serviceId = mapStakedServiceIds[stakingProxies[i]][lastIdx];
                }

                // Deploy and stake already existent service or create a new one first
                if (serviceId > 0) {
                    _deployAndStake(stakingProxies[i], serviceId);
                } else {
                    _createAndStake(stakingProxies[i], minStakingDeposit);
                }

                balance -= stakeDeposit;
            }
            mapStakingProxyBalances[stakingProxies[i]] = balance;

            emit StakingBalanceUpdated(stakingProxies[i], balance);
        }

        _locked = 1;
    }

    // TODO Re-stake if services are evicted by any reason
    function reStake(address stakingProxy, uint256[] memory serviceIds) external {

    }

    /// @dev Unstakes, if needed, and withdraws specified amounts from specified staking contracts.
    /// @notice Unstakes services if needed to satisfy withdraw requests.
    ///         Call this to unstake definitely terminated staking contracts - deactivated on L1 and / or ran out of funds.
    ///         The majority of discovered chains does not need any value to process token bridge transfer.
    function unstake(address[] memory stakingProxies, uint256[] amounts) external virtual {
        // Reentrancy guard
        if (_locked > 1) {
            revert ReentrancyGuard();
        }
        _locked = 2;

        // Check for treasury requesting withdraw
        if (msg.sender != l2StakingProcessor) {
            revert UnauthorizedAccount(msg.sender);
        }

        // TODO Overflow sanity checks? On L1 side as well?
        uint256 totalAmount;
        // Traverse all staking proxies
        for (uint256 i = 0; i < stakingProxies.length; ++i) {
            uint256 balance = mapStakingProxyBalances[stakingProxies[i]];
            if (balance > amounts[i]) {
                balance -= amounts[i];
            } else {
                if (!isAbleWithdraw(stakingProxies[i], amounts[i])) {
                    revert();
                }

                uint256 unstakeAmount = _unstake(stakingProxies[i]);
                balance = balance + unstakeAmount - amounts[i];
            }
            mapStakingProxyBalances[stakingProxies[i]] = balance;
            totalAmount += amounts[i];
        }

        // Send OLAS to collector to initiate L1 transfer for all the balances at this time
        IToken(olas).transfer(collector, totalAmount);
        // TODO: Make sure once again no value is needed to send tokens back
        ICollector(collector).relayTokens(0);

        _locked = 1;
    }

    function isAbleStake(address stakingProxy, uint256 olasAmount) public view returns (bool) {
        // Check for staking instance validity
        if(!IStaking(stakingFactory).verifyInstance(stakingProxy)) {
            revert WrongStakingInstance(stakingProxy);
        }

        // TODO Check number of staked services
        //

        // Get other service info for staking
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
        uint256 numServices = mapStakedServiceIds[stakingProxy].length;
        if (numServices == 0) {
            revert ZeroValue();
        }

        return true;
    }
}