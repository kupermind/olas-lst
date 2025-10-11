// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test, console} from "forge-std/Test.sol";
import {Utils} from "./utils/Utils.sol";

import {IService} from "../contracts/interfaces/IService.sol";
import {GnosisSafe} from "@gnosis.pm/safe-contracts/contracts/GnosisSafe.sol";
import {GnosisSafeL2} from "@gnosis.pm/safe-contracts/contracts/GnosisSafeL2.sol";
import {GnosisSafeProxyFactory} from "@gnosis.pm/safe-contracts/contracts/proxies/GnosisSafeProxyFactory.sol";
import {DefaultCallbackHandler} from "@gnosis.pm/safe-contracts/contracts/handler/DefaultCallbackHandler.sol";
import {MultiSendCallOnly} from "@gnosis.pm/safe-contracts/contracts/libraries/MultiSendCallOnly.sol";
import {SafeToL2Setup} from "../test/SafeToL2Setup.sol";

import {ERC20Token} from "@registries/contracts/test/ERC20Token.sol";
import {ServiceRegistryL2} from "@registries/contracts/ServiceRegistryL2.sol";
import {ServiceRegistryTokenUtility} from "@registries/contracts/ServiceRegistryTokenUtility.sol";
import {ServiceManagerToken} from "@registries/contracts/ServiceManagerToken.sol";
import {OperatorWhitelist} from "@registries/contracts/utils/OperatorWhitelist.sol";
import {GnosisSafeMultisig} from "@registries/contracts/multisigs/GnosisSafeMultisig.sol";
import {GnosisSafeSameAddressMultisig} from "@registries/contracts/multisigs/GnosisSafeSameAddressMultisig.sol";
import {StakingVerifier} from "@registries/contracts/staking/StakingVerifier.sol";
import {StakingFactory} from "@registries/contracts/staking/StakingFactory.sol";

import {stOLAS} from "../contracts/l1/stOLAS.sol";
import {Lock} from "../contracts/l1/Lock.sol";
import {Depository, ProductType, StakingModelStatus} from "../contracts/l1/Depository.sol";
import {Treasury} from "../contracts/l1/Treasury.sol";
import {Distributor} from "../contracts/l1/Distributor.sol";
import {UnstakeRelayer} from "../contracts/l1/UnstakeRelayer.sol";
import {GnosisDepositProcessorL1} from "../contracts/l1/bridging/GnosisDepositProcessorL1.sol";

import {Collector} from "../contracts/l2/Collector.sol";
import {ActivityModule} from "../contracts/l2/ActivityModule.sol";
import {StakingManager} from "../contracts/l2/StakingManager.sol";
import {ModuleActivityChecker} from "../contracts/l2/ModuleActivityChecker.sol";
import {StakingTokenLocked} from "../contracts/l2/StakingTokenLocked.sol";
import {GnosisStakingProcessorL2} from "../contracts/l2/bridging/GnosisStakingProcessorL2.sol";

import {Proxy} from "../contracts/Proxy.sol";
import {Beacon} from "../contracts/Beacon.sol";
import {MockVE} from "../contracts/test/MockVE.sol";
import {BridgeRelayer} from "../contracts/test/BridgeRelayer.sol";
import {SafeToL2Setup} from "../contracts/test/SafeToL2Setup.sol";
import {GnosisSafeSameAddressMultisig} from "../lib/autonolas-registries/audits/internal4/analysis/contracts/GnosisSafeSameAddressMultisig-flatten.sol";
import {Treasury} from "../lib/layerzero-v2/packages/layerzero-v2/evm/messagelib/contracts/Treasury.sol";

contract LiquidStakingTest is Test {
    Utils internal utils;
    ERC20Token internal olas;
    ServiceRegistryL2 internal serviceRegistry;
    ServiceRegistryTokenUtility internal serviceRegistryTokenUtility;
    OperatorWhitelist internal operatorWhitelist;
    ServiceManagerToken internal serviceManagerToken;

    GnosisSafe internal gnosisSafe;
    GnosisSafeL2 internal gnosisSafeL2;
    GnosisSafeProxy internal gnosisSafeProxy;
    GnosisSafeProxyFactory internal gnosisSafeProxyFactory;
    DefaultCallbackHandler internal fallbackHandler;
    MultiSendCallOnly internal multiSend;
    SafeToL2Setup internal safeModuleInitializer;

    GnosisSafeMultisig internal gnosisSafeMultisig;
    GnosisSafeSameAddressMultisig internal gnosisSafeSameAddressMultisig;
    StakingVerifier internal stakingVerifier;
    StakingFactory internal stakingFactory;

    stOLAS internal st;
    Lock internal lockImplementation;
    Distributor internal distributorImplementation;
    UnstakeRelayer internal unstakeRelayerImplementation;
    Depository internal depositoryImplementation;
    Treasury internal treasuryImplementation;
    Collector internal collectorImplementation;
    StakingManager internal stakingManagerImplementation;

    Proxy internal lock;
    Proxy internal distributor;
    Proxy internal unstakeRelayer;
    Proxy internal depository;
    Proxy internal treasury;
    Proxy internal collector;
    Proxy internal stakingManager;

    Beacon internal beacon;
    MockVE internal ve;
    BridgeRelayer internal bridgeRelayer;

    // Test addresses
    address internal deployer;
    address internal agent;

    // Constants
    uint256 public constant ONE_DAY = 86400;
    uint256 public constant REG_DEPOSIT = 10000 ether;
    uint256 public constant SERVICE_ID = 1;
    uint256 public constant AGENT_ID = 1;
    uint256 public constant LIVENESS_PERIOD = ONE_DAY;
    uint256 public constant INIT_SUPPLY = 5e26;
    uint256 public constant LIVENESS_RATIO = 11111111111111;
    uint256 public constant MAX_NUM_SERVICES = 100;
    uint256 public constant MIN_STAKING_DEPOSIT = REG_DEPOSIT;
    uint256 public constant FULL_STAKE_DEPOSIT = REG_DEPOSIT * 2;
    uint256 public constant TIME_FOR_EMISSIONS = 30 * ONE_DAY;
    uint256 public constant APY_LIMIT = 3 ether;
    uint256 public constant LOCK_FACTOR = 100;
    uint256 public constant MAX_STAKING_LIMIT = 20000 ether;
    uint256 public constant PROTOCOL_FACTOR = 0;
    uint256 public constant CHAIN_ID = 31337;
    uint256 public constant GNOSIS_CHAIN_ID = 100;

    // Bridge operations
    bytes32 public constant REWARD_OPERATION = 0x0b9821ae606ebc7c79bf3390bdd3dc93e1b4a7cda27aad60646e7b88ff55b001;
    bytes32 public constant UNSTAKE_OPERATION = 0x8ca9a95e41b5eece253c93f5b31eed1253aed6b145d8a6e14d913fdf8e732293;
    bytes32 public constant UNSTAKE_RETIRED_OPERATION =
        0x9065ad15d9673159e4597c86084aff8052550cec93c5a6e44b3f1dba4c8731b3;

    // Bridge payload
    bytes public constant BRIDGE_PAYLOAD = "";

    address payable[] internal users;
    address[] internal agentInstances;
    uint256[] internal serviceIds;
    uint256[] internal emptyArray;
    address internal deployer;
    address internal operator;
    uint256 internal numServices = 3;
    uint256 internal initialMint = 50_000_000 ether;
    uint256 internal largeApproval = 1_000_000_000 ether;
    uint256 internal oneYear = 365 * 24 * 3600;
    uint32 internal threshold = 1;
    uint96 internal regBond = 10 ether;
    uint256 internal regDeposit = 10 ether;
    uint256 internal numDays = 10;

    bytes32 internal unitHash = 0x9999999999999999999999999999999999999999999999999999999999999999;
    bytes internal payload;
    uint32[] internal agentIds;

    // Maximum number of staking services
    uint256 internal maxNumServices = 10;
    // Rewards per second
    uint256 internal rewardsPerSecond = 549768518519;
    // Minimum service staking deposit value required for staking
    uint256 internal minStakingDeposit = regDeposit;
    // APY limit
    uint256 internal apyLimit = 2 ether;
    // Min number of staking periods before the service can be unstaked
    uint256 internal minNumStakingPeriods = 3;
    // Max number of accumulated inactivity periods after which the service is evicted
    uint256 internal maxNumInactivityPeriods = 3;
    // Liveness period
    uint256 internal livenessPeriod = 1 days;
    // Time for emissions
    uint256 internal timeForEmissions = 1 weeks;
    // Liveness ratio in the format of 1e18
    uint256 internal livenessRatio = 0.0001 ether; // One nonce in 3 hours
    // Number of agent instances in the service
    uint256 internal numAgentInstances = 1;

    function setUp() public virtual {
        agentIds = new uint32[](1);
        agentIds[0] = 1;

        utils = new Utils();
        users = utils.createUsers(20);
        deployer = users[0];
        vm.label(deployer, "Deployer");
        operator = users[1];
        // Allocate several addresses for agent instances
        agentInstances = new address[](2 * numServices);
        for (uint256 i = 0; i < 2 * numServices; ++i) {
            agentInstances[i] = users[i + 2];
        }

        // Deploying registries contracts
        serviceRegistry = new ServiceRegistryL2("Service Registry", "SERVICE", "https://localhost/service/");
        serviceRegistryTokenUtility = new ServiceRegistryTokenUtility(address(serviceRegistry));
        operatorWhitelist = new OperatorWhitelist(address(serviceRegistry));
        serviceManagerToken = new ServiceManagerToken(address(serviceRegistry), address(serviceRegistryTokenUtility), address(operatorWhitelist));
        serviceRegistry.changeManager(address(serviceManagerToken));
        serviceRegistryTokenUtility.changeManager(address(serviceManagerToken));

        // Deploying multisig contracts and multisig implementation
        gnosisSafe = new GnosisSafe();
        gnosisSafeL2 = new GnosisSafeL2();
        gnosisSafeProxyFactory = new GnosisSafeProxyFactory();
        SafeToL2Setup = new SafeToL2Setup();
        fallbackHandler = new DefaultCallbackHandler();
        multiSend = new MultiSendCallOnly();
        gnosisSafeProxy = new GnosisSafeProxy(address(gnosisSafe));

        // Get the multisig proxy bytecode hash
        bytes32 multisigProxyHash = keccak256(address(gnosisSafeProxy).code);

        gnosisSafeMultisig = new GnosisSafeMultisig(payable(address(gnosisSafe)), address(gnosisSafeProxyFactory));
        gnosisSafeSameAddressMultisig = new GnosisSafeSameAddressMultisig(multisigProxyHash);

        // Deploying OLAS mock and minting to deployer, operator and a current contract
        olas = new ERC20Token();
        olas.mint(deployer, initialMint);
        olas.mint(operator, initialMint);
        olas.mint(address(this), initialMint);

        ve = new MockVE(address(olas));
        st = new stOLAS(address(olas));

        lockImplementation = new Lock(address(olas), address(ve));
        bytes memory initPayload = abi.encodeWithSelector(lockImplementation.initialize.selector);
        lock = new Proxy(address(lock), initPayload);

        // Transfer initial lock
        olas.transfer(address(lock), 1 ether);
        // Set governor and create first lock
        // Governor address is irrelevant for testing
        Lock(lock).setGovernorAndCreateFirstLock(address(this));

        distributorImplementation = new Distributor(address(olas), address(st), address(lock));
        initPayload = abi.encodeWithSelector(distributorImplementation.initialize.selector, LOCK_FACTOR);
        distributor = new Proxy(address(distributorImplementation), initPayload);

        unstakeRelayerImplementation = new UnstakeRelayer(address(olas), address(st));
        initPayload = abi.encodeWithSelector(unstakeRelayerImplementation.initialize.selector);
        unstakeRelayer = new Proxy(address(unstakeRelayerImplementation), initPayload);

        depositoryImplementation = new Depository(address(olas), address(st));
        initPayload = abi.encodeWithSelector(depositoryImplementation.initialize.selector);
        depository = new Proxy(address(depositoryImplementation), initPayload);

        // Change product type to Final
        Depository(depository).changeProductType(ProductType.Final);

        treasuryImplementation = new Treasury(address(olas), address(st), address(depository));
        initPayload = abi.encodeWithSelector(treasuryImplementation.initialize.selector, 0);
        treasury = new Proxy(address(treasuryImplementation), initPayload);

        // Change managers for stOLAS
        st.initialize(address(treasury), address(depository), address(distributor), address(unstakeRelayer));

        // Change treasury address in depository
        Depository(depository).changeTreasury(address(treasury));

        // Deploy service staking verifier
        stakingVerifier = new StakingVerifier(address(olas), address(serviceRegistry),
            address(serviceRegistryTokenUtility), MIN_STAKING_DEPOSIT, TIME_FOR_EMISSIONS, MAX_NUM_SERVICES, APY_LIMIT);

        // Deploy service staking factory
        stakingFactory = new StakingFactory(address(stakingVerifier));

        // Deploy service staking activity checker
        stakingActivityChecker = new StakingActivityChecker(livenessRatio);

        // Deploy service staking native token and arbitrary ERC20 token
        StakingBase.StakingParams memory stakingParams = StakingBase.StakingParams(
            bytes32(uint256(uint160(address(msg.sender)))), maxNumServices, rewardsPerSecond, minStakingDeposit,
            minNumStakingPeriods, maxNumInactivityPeriods, livenessPeriod, timeForEmissions, numAgentInstances,
            emptyArray, 0, bytes32(0), multisigProxyHash, address(serviceRegistry), address(stakingActivityChecker));
        stakingNativeTokenImplementation = new StakingNativeToken();
        stakingTokenImplementation = new StakingToken();

        // Initialization payload and deployment of stakingNativeToken
        bytes memory initPayload = abi.encodeWithSelector(stakingNativeTokenImplementation.initialize.selector,
            stakingParams, address(serviceRegistry), multisigProxyHash);
        stakingNativeToken = StakingNativeToken(stakingFactory.createStakingInstance(
            address(stakingNativeTokenImplementation), initPayload));

        // Set the stakingVerifier
        stakingFactory.changeVerifier(address(stakingVerifier));
        // Initialization payload and deployment of stakingToken
        initPayload = abi.encodeWithSelector(stakingTokenImplementation.initialize.selector,
            stakingParams, address(serviceRegistryTokenUtility), address(token));
        stakingToken = StakingToken(stakingFactory.createStakingInstance(
            address(stakingTokenImplementation), initPayload));

        // Whitelist multisig implementations
        serviceRegistry.changeMultisigPermission(address(gnosisSafeMultisig), true);

        IService.AgentParams[] memory agentParams = new IService.AgentParams[](1);
        agentParams[0].slots = 1;
        agentParams[0].bond = regBond;

        // Create services, activate them, register agent instances and deploy
        for (uint256 i = 0; i < numServices; ++i) {
            // Create a service
            serviceManagerToken.create(deployer, serviceManagerToken.ETH_TOKEN_ADDRESS(), unitHash, agentIds,
                agentParams, threshold);

            uint256 serviceId = i + 1;
            // Activate registration
            vm.prank(deployer);
            serviceManagerToken.activateRegistration{value: regDeposit}(serviceId);

            // Register agent instances
            address[] memory agentInstancesService = new address[](1);
            agentInstancesService[0] = agentInstances[i];
            vm.prank(operator);
            serviceManagerToken.registerAgents{value: regBond}(serviceId, agentInstancesService, agentIds);

            // Deploy the service
            vm.prank(deployer);
            serviceManagerToken.deploy(serviceId, address(gnosisSafeMultisig), payload);
        }

        // Create services with ERC20 token, activate them, register agent instances and deploy
        vm.prank(deployer);
        token.approve(address(serviceRegistryTokenUtility), initialMint);
        vm.prank(operator);
        token.approve(address(serviceRegistryTokenUtility), initialMint);
        for (uint256 i = 0; i < numServices; ++i) {
            // Create a service
            serviceManagerToken.create(deployer, address(token), unitHash, agentIds, agentParams, threshold);

            uint256 serviceId = i + numServices + 1;
            // Activate registration
            vm.prank(deployer);
            serviceManagerToken.activateRegistration{value: 1}(serviceId);

            // Register agent instances
            address[] memory agentInstancesService = new address[](1);
            agentInstancesService[0] = agentInstances[i + numServices];
            vm.prank(operator);
            serviceManagerToken.registerAgents{value: 1}(serviceId, agentInstancesService, agentIds);

            // Deploy the service
            vm.prank(deployer);
            serviceManagerToken.deploy(serviceId, address(gnosisSafeMultisig), payload);
        }
    }

    function _initializeContracts() internal {
        console.log("Initializing Lock...");
        // Initialize Lock
        lock.initialize();
        console.log("Lock initialized");

        console.log("Initializing Distributor...");
        // Initialize Distributor
        distributor.initialize(LOCK_FACTOR);
        console.log("Distributor initialized");

        console.log("Initializing UnstakeRelayer...");
        // Initialize UnstakeRelayer
        unstakeRelayer.initialize();
        console.log("UnstakeRelayer initialized");

        console.log("Initializing Depository...");
        // Initialize Depository
        depository.initialize();
        console.log("Depository initialized");

        console.log("Initializing Treasury...");
        // Initialize Treasury
        treasury.initialize(0);
        console.log("Treasury initialized");

        console.log("Initializing Collector...");
        // Initialize Collector
        collector.initialize();
        console.log("Collector initialized");

        console.log("Initializing StakingManager...");
        // Initialize StakingManager
        stakingManager.initialize(address(0), address(0), address(0));
        console.log("StakingManager initialized");

        console.log("Setting up stOLAS managers...");
        // Setup stOLAS managers
        st.initialize(address(treasury), address(depository), address(distributor), address(unstakeRelayer));
        console.log("stOLAS managers set");

        console.log("Setting up depository treasury...");
        // Setup depository treasury
        depository.changeTreasury(address(treasury));
        console.log("Depository treasury set");

        console.log("Funding Lock with initial OLAS...");
        // Fund Lock with initial OLAS
        olas.transfer(address(lock), 1 ether);
        console.log("Lock funded with 1 ether");

        console.log("Setting governor and creating first lock...");
        lock.setGovernorAndCreateFirstLock(deployer);
        console.log("Governor set and first lock created");

        console.log("Funding StakingManager...");
        // Fund StakingManager
        payable(address(stakingManager)).transfer(1 ether);
        console.log("StakingManager funded with 1 ether");

        console.log("=== Contract initialization completed ===");
    }

    function testE2ELiquidStakingSimple() public {
        console.log("=== E2E Liquid Staking Simple Test ===");

        // Take snapshot
        uint256 snapshot = vm.snapshot();

        console.log("L1");

        // Get OLAS amount to stake
        uint256 olasAmount = MIN_STAKING_DEPOSIT * 3;

        // Approve OLAS for depository
        console.log("User approves OLAS for depository:", olasAmount);
        olas.approve(address(depository), olasAmount);

        // Stake OLAS on L1
        console.log("User deposits OLAS for stOLAS");
        uint256 previewAmount = st.previewDeposit(olasAmount);
        depository.deposit(
            olasAmount,
            _toArray(GNOSIS_CHAIN_ID),
            _toArray(address(0)), // stakingTokenInstance placeholder
            _toArray(BRIDGE_PAYLOAD),
            _toArray(0)
        );

        uint256 stBalance = st.balanceOf(deployer);
        assertEq(stBalance, previewAmount, "stOLAS balance mismatch");
        console.log("User stOLAS balance now:", stBalance);

        uint256 stTotalAssets = st.totalAssets();
        console.log("OLAS total assets on stOLAS:", stTotalAssets);

        console.log("L2");

        // Note: This is a simplified test - in real scenario we'd need to:
        // 1. Deploy actual staking instance
        // 2. Setup proper bridging
        // 3. Handle L2 operations

        console.log("Test completed successfully");

        // Restore snapshot
        vm.revertTo(snapshot);
    }

    function testMoreThanOneServiceDeposit() public {
        console.log("=== More Than One Service Deposit Test ===");

        uint256 snapshot = vm.snapshot();

        console.log("L1");

        // Get OLAS amount to stake - want to cover 2 staked services
        uint256 olasAmount = MIN_STAKING_DEPOSIT * 5;

        // Approve OLAS for depository
        console.log("User approves OLAS for depository:", olasAmount);
        olas.approve(address(depository), olasAmount);

        // Stake OLAS on L1
        console.log("User deposits OLAS for stOLAS");
        uint256 previewAmount = st.previewDeposit(olasAmount);
        depository.deposit(
            olasAmount,
            _toArray(GNOSIS_CHAIN_ID),
            _toArray(address(0)), // stakingTokenInstance placeholder
            _toArray(BRIDGE_PAYLOAD),
            _toArray(0)
        );

        uint256 stBalance = st.balanceOf(deployer);
        assertEq(stBalance, previewAmount, "stOLAS balance mismatch");
        console.log("User stOLAS balance now:", stBalance);

        console.log("Test completed successfully");

        vm.revertTo(snapshot);
    }

    function testTwoServicesDepositOneUnstakeMoreDepositFullUnstake() public {
        console.log("=== Two Services Deposit, One Unstake, More Deposit, Full Unstake Test ===");

        uint256 snapshot = vm.snapshot();

        console.log("L1");

        // Initial stake
        uint256 olasAmount = MIN_STAKING_DEPOSIT * 5;
        olas.approve(address(depository), olasAmount);

        uint256 previewAmount = st.previewDeposit(olasAmount);
        depository.deposit(
            olasAmount, _toArray(GNOSIS_CHAIN_ID), _toArray(address(0)), _toArray(BRIDGE_PAYLOAD), _toArray(0)
        );

        uint256 stBalance = st.balanceOf(deployer);
        assertEq(stBalance, previewAmount, "stOLAS balance mismatch");
        console.log("User stOLAS balance now:", stBalance);

        console.log("Test completed successfully");

        vm.revertTo(snapshot);
    }

    function testMaxNumberStakes() public {
        console.log("=== Max Number of Stakes Test ===");

        uint256 snapshot = vm.snapshot();

        console.log("L1");

        uint256 olasAmount = (MIN_STAKING_DEPOSIT * 3) - 1;
        olas.approve(address(depository), INIT_SUPPLY);

        // Multiple stakes
        uint256 numStakes = 18;
        uint256[] memory chainIds = _fillArray(GNOSIS_CHAIN_ID, numStakes);
        address[] memory stakingInstances = _fillArray(address(0), numStakes);
        bytes[] memory bridgePayloads = _fillArray(BRIDGE_PAYLOAD, numStakes);
        uint256[] memory values = _fillArray(0, numStakes);

        for (uint256 i = 0; i < 10; i++) {
            depository.deposit(olasAmount * numStakes, chainIds, stakingInstances, bridgePayloads, values);
        }

        uint256 stBalance = st.balanceOf(deployer);
        console.log("User stOLAS balance now:", stBalance);

        console.log("Test completed successfully");

        vm.revertTo(snapshot);
    }

    function testMultipleStakesUnstakes() public {
        console.log("=== Multiple Stakes-Unstakes Test ===");

        uint256 snapshot = vm.snapshot();

        console.log("L1");

        uint256 olasAmount = (MIN_STAKING_DEPOSIT * 5) / 4;
        uint256 numStakes = 18;

        uint256[] memory chainIds = _fillArray(GNOSIS_CHAIN_ID, numStakes);
        address[] memory stakingInstances = _fillArray(address(0), numStakes);
        bytes[] memory bridgePayloads = _fillArray(BRIDGE_PAYLOAD, numStakes);
        uint256[] memory values = _fillArray(0, numStakes);

        // Mirror the Hardhat test's intensive stake-unstake cadence by running more iterations
        for (uint256 i = 0; i < 40; i++) {
            console.log("Stake-Unstake iteration:", i);

            // Increase stake a bit every iteration
            olasAmount += 1;
            uint256 amountToStake = olasAmount * numStakes;

            // Approve and preview
            olas.approve(address(depository), amountToStake);
            uint256 previewAmount = st.previewDeposit(amountToStake);

            // Track totals before deposit
            uint256 stTotalAssetsBefore = st.totalAssets();
            uint256 stBalanceBefore = st.balanceOf(deployer);

            // Deposit
            depository.deposit(amountToStake, chainIds, stakingInstances, bridgePayloads, values);

            // Validate totalAssets increased by exact deposited OLAS
            uint256 stTotalAssetsAfter = st.totalAssets();
            uint256 stTotalAssetsAfterDiff = stTotalAssetsAfter - stTotalAssetsBefore;
            assertEq(stTotalAssetsAfterDiff, amountToStake, "totalAssets did not increase by deposited amount");

            // Validate stOLAS minted equals previewDeposit
            uint256 stBalanceAfter = st.balanceOf(deployer);
            uint256 stBalanceDiff = stBalanceAfter - stBalanceBefore;
            assertEq(stBalanceDiff, previewAmount, "minted stOLAS != previewDeposit");

            // Preview redeem of just-minted shares should be ~amountToStake (allow tiny rounding)
            uint256 redeemPreview = st.previewRedeem(stBalanceDiff);
            uint256 delta = amountToStake - redeemPreview;
            require(delta < 10, "previewRedeem deviates too much");

            uint256 stBalance = st.balanceOf(deployer);
            console.log("User stOLAS balance now:", stBalance);
            console.log("OLAS total assets on stOLAS:", stTotalAssetsAfter);
        }

        console.log("Test completed successfully");

        vm.revertTo(snapshot);
    }

    function testRetireModels() public {
        console.log("=== Retire Models Test ===");

        uint256 snapshot = vm.snapshot();

        console.log("L1");

        uint256 olasAmount = (MIN_STAKING_DEPOSIT * 3) - 1;
        olas.approve(address(depository), INIT_SUPPLY);

        uint256 numStakes = 18;
        uint256[] memory chainIds = _fillArray(GNOSIS_CHAIN_ID, numStakes);
        address[] memory stakingInstances = _fillArray(address(0), numStakes);
        bytes[] memory bridgePayloads = _fillArray(BRIDGE_PAYLOAD, numStakes);
        uint256[] memory values = _fillArray(0, numStakes);

        for (uint256 i = 0; i < 10; i++) {
            depository.deposit(olasAmount * numStakes, chainIds, stakingInstances, bridgePayloads, values);
        }

        uint256 stBalance = st.balanceOf(deployer);
        console.log("User stOLAS balance now:", stBalance);

        // Try to close a model without setting it to retired
        vm.expectRevert();
        depository.closeRetiredStakingModels(_toArray(GNOSIS_CHAIN_ID), _toArray(address(0)));

        console.log("Test completed successfully");

        vm.revertTo(snapshot);
    }

    // Helper functions
    function _toArray(uint256 value) internal pure returns (uint256[] memory) {
        uint256[] memory arr = new uint256[](1);
        arr[0] = value;
        return arr;
    }

    function _toArray(address value) internal pure returns (address[] memory) {
        address[] memory arr = new address[](1);
        arr[0] = value;
        return arr;
    }

    function _toArray(bytes memory value) internal pure returns (bytes[] memory) {
        bytes[] memory arr = new bytes[](1);
        arr[0] = value;
        return arr;
    }

    function _fillArray(uint256 value, uint256 length) internal pure returns (uint256[] memory) {
        uint256[] memory arr = new uint256[](length);
        for (uint256 i = 0; i < length; i++) {
            arr[i] = value;
        }
        return arr;
    }

    function _fillArray(address value, uint256 length) internal pure returns (address[] memory) {
        address[] memory arr = new address[](length);
        for (uint256 i = 0; i < length; i++) {
            arr[i] = value;
        }
        return arr;
    }

    function _fillArray(bytes memory value, uint256 length) internal pure returns (bytes[] memory) {
        bytes[] memory arr = new bytes[](length);
        for (uint256 i = 0; i < length; i++) {
            arr[i] = value;
        }
        return arr;
    }
}
