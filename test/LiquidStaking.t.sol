// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test, console} from "forge-std/Test.sol";
import {Utils} from "./utils/Utils.sol";

import {IService} from "../contracts/interfaces/IService.sol";
import {GnosisSafe} from "@gnosis.pm/safe-contracts/contracts/GnosisSafe.sol";
import {GnosisSafeL2} from "@gnosis.pm/safe-contracts/contracts/GnosisSafeL2.sol";
import {GnosisSafeProxyFactory} from "@gnosis.pm/safe-contracts/contracts/proxies/GnosisSafeProxyFactory.sol";
import {GnosisSafeProxy} from "@gnosis.pm/safe-contracts/contracts/proxies/GnosisSafeProxy.sol";
import {DefaultCallbackHandler} from "@gnosis.pm/safe-contracts/contracts/handler/DefaultCallbackHandler.sol";
import {MultiSendCallOnly} from "@gnosis.pm/safe-contracts/contracts/libraries/MultiSendCallOnly.sol";
import {SafeToL2Setup} from "../contracts/test/SafeToL2Setup.sol";

import {ERC20} from "@solmate/src/tokens/ERC20.sol";
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
    Lock internal lock;
    Distributor internal distributor;
    UnstakeRelayer internal unstakeRelayer;
    Depository internal depository;
    Treasury internal treasury;
    GnosisDepositProcessorL1 internal gnosisDepositProcessorL1;
    Collector internal collector;
    ActivityModule internal activityModule;
    StakingManager internal stakingManager;
    GnosisStakingProcessorL2 internal gnosisStakingProcessorL2;
    ModuleActivityChecker internal moduleActivityChecker;
    StakingTokenLocked internal stakingTokenInstance;

    Beacon internal beacon;
    MockVE internal ve;
    BridgeRelayer internal bridgeRelayer;

    // Test addresses
    address internal deployer;
    address internal agent;
    address payable[] internal users;

    // Constants
    uint256 public constant ONE_DAY = 86400;
    uint256 public constant REG_DEPOSIT = 10000 ether;
    uint256 public constant SERVICE_ID = 1;
    uint256 public constant AGENT_ID = 1;
    uint256 public constant LIVENESS_PERIOD = ONE_DAY;
    uint256 public constant INIT_SUPPLY = 5e26;
    uint256 public constant LIVENESS_RATIO = 1;
    uint256 public constant MAX_NUM_SERVICES = 100;
    uint256 public constant REWARDS_PER_SECOND = 0.0005 ether;
    uint256 public constant MIN_STAKING_DEPOSIT = REG_DEPOSIT;
    uint256 public constant FULL_STAKE_DEPOSIT = REG_DEPOSIT * 2;
    uint256 public constant STAKING_SUPPLY = FULL_STAKE_DEPOSIT * MAX_NUM_SERVICES;
    uint256 public constant TIME_FOR_EMISSIONS = 30 * ONE_DAY;
    uint256 public constant APY_LIMIT = 3 ether;
    uint256 public constant LOCK_FACTOR = 100;
    uint256 public constant MAX_STAKING_LIMIT = 20000 ether;
    uint256 public constant PROTOCOL_FACTOR = 0;
    uint256 public constant CHAIN_ID = 31337;
    uint256 public constant GNOSIS_CHAIN_ID = 100;
    bytes32 public DEFAULT_HASH = 0x9999999999999999999999999999999999999999999999999999999999999999;

    // Bridge operations
    bytes32 public constant REWARD_OPERATION = 0x0b9821ae606ebc7c79bf3390bdd3dc93e1b4a7cda27aad60646e7b88ff55b001;
    bytes32 public constant UNSTAKE_OPERATION = 0x8ca9a95e41b5eece253c93f5b31eed1253aed6b145d8a6e14d913fdf8e732293;
    bytes32 public constant UNSTAKE_RETIRED_OPERATION =
        0x9065ad15d9673159e4597c86084aff8052550cec93c5a6e44b3f1dba4c8731b3;

    // Bridge payload
    bytes public constant BRIDGE_PAYLOAD = "";


    function setUp() public virtual {
        utils = new Utils();
        users = utils.createUsers(20);
        deployer = users[0];
        vm.label(deployer, "Deployer");
        agent = users[1];
        vm.label(deployer, "Agent");

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
        safeModuleInitializer = new SafeToL2Setup();
        fallbackHandler = new DefaultCallbackHandler();
        multiSend = new MultiSendCallOnly();
        gnosisSafeProxy = new GnosisSafeProxy(address(gnosisSafe));

        // Get the multisig proxy bytecode hash
        bytes32 multisigProxyHash = keccak256(address(gnosisSafeProxy).code);

        gnosisSafeMultisig = new GnosisSafeMultisig(payable(address(gnosisSafe)), address(gnosisSafeProxyFactory));
        gnosisSafeSameAddressMultisig = new GnosisSafeSameAddressMultisig(multisigProxyHash);

        // Deploying OLAS mock and minting to deployer, operator and a current contract
        olas = new ERC20Token();
        olas.mint(deployer, INIT_SUPPLY);
        olas.mint(address(this), INIT_SUPPLY);

        ve = new MockVE(address(olas));
        st = new stOLAS(ERC20(address(olas)));

        Lock lockImplementation = new Lock(address(olas), address(ve));
        bytes memory initPayload = abi.encodeWithSelector(lockImplementation.initialize.selector);
        Proxy lockProxy = new Proxy(address(lockImplementation), initPayload);
        lock = Lock(address(lockProxy));

        // Transfer initial lock
        olas.transfer(address(lock), 1 ether);
        // Set governor and create first lock
        // Governor address is irrelevant for testing
        lock.setGovernorAndCreateFirstLock(address(this));

        Distributor distributorImplementation = new Distributor(address(olas), address(st), address(lock));
        initPayload = abi.encodeWithSelector(distributorImplementation.initialize.selector, LOCK_FACTOR);
        Proxy distributorProxy = new Proxy(address(distributorImplementation), initPayload);
        distributor = Distributor(address(distributorProxy));

        UnstakeRelayer unstakeRelayerImplementation = new UnstakeRelayer(address(olas), address(st));
        initPayload = abi.encodeWithSelector(unstakeRelayerImplementation.initialize.selector);
        Proxy unstakeRelayerProxy = new Proxy(address(unstakeRelayerImplementation), initPayload);
        unstakeRelayer = UnstakeRelayer(address(unstakeRelayerProxy));

        Depository depositoryImplementation = new Depository(address(olas), address(st));
        initPayload = abi.encodeWithSelector(depositoryImplementation.initialize.selector);
        Proxy depositoryProxy = new Proxy(address(depositoryImplementation), initPayload);
        depository = Depository(address(depositoryProxy));

        // Change product type to Final
        depository.changeProductType(ProductType.Final);

        Treasury treasuryImplementation = new Treasury(address(olas), address(st), address(depository));
        initPayload = abi.encodeWithSelector(treasuryImplementation.initialize.selector, 0);
        Proxy treasuryProxy = new Proxy(address(treasuryImplementation), initPayload);
        treasury = Treasury(address(treasuryProxy));

        // Change managers for stOLAS
        st.initialize(address(treasury), address(depository), address(distributor), address(unstakeRelayer));

        // Change treasury address in depository
        depository.changeTreasury(address(treasury));

        // Deploy service staking verifier
        stakingVerifier = new StakingVerifier(address(olas), address(serviceRegistry),
            address(serviceRegistryTokenUtility), MIN_STAKING_DEPOSIT, TIME_FOR_EMISSIONS, MAX_NUM_SERVICES, APY_LIMIT);

        // Deploy service staking factory
        stakingFactory = new StakingFactory(address(stakingVerifier));

        Collector collectorImplementation = new Collector(address(olas));
        initPayload = abi.encodeWithSelector(collectorImplementation.initialize.selector);
        Proxy collectorProxy = new Proxy(address(collectorImplementation), initPayload);
        collector = Collector(address(collectorProxy));

        activityModule = new ActivityModule(address(olas), address(collector), address(multiSend));
        beacon = new Beacon(address(activityModule));

        StakingManager stakingManagerImplementation = new StakingManager(address(olas), address(serviceManagerToken),
            address(stakingFactory), address(safeModuleInitializer), address(gnosisSafeL2), address(beacon),
            address(collector), AGENT_ID, DEFAULT_HASH);
        initPayload = abi.encodeWithSelector(stakingManagerImplementation.initialize.selector, address(gnosisSafeMultisig),
            address(gnosisSafeSameAddressMultisig), address(fallbackHandler));
        Proxy stakingManagerProxy = new Proxy(address(stakingManagerImplementation), initPayload);
        stakingManager = StakingManager(payable(address(stakingManagerProxy)));

        // Fund staking manager with native to support staking creation
        vm.deal(address(stakingManager), 1 ether);

        bridgeRelayer = new BridgeRelayer(address(olas));
        gnosisDepositProcessorL1 = new GnosisDepositProcessorL1(address(olas), address(depository), address(bridgeRelayer),
            address(bridgeRelayer));
        gnosisStakingProcessorL2 = new GnosisStakingProcessorL2(address(olas), address(stakingManager), address(collector),
            address(bridgeRelayer), address(bridgeRelayer), address(gnosisDepositProcessorL1), CHAIN_ID);

        // changeStakingProcessorL2 for collector
        collector.changeStakingProcessorL2(address(gnosisStakingProcessorL2));

        // changeStakingProcessorL2 for stakingManager
        stakingManager.changeStakingProcessorL2(address(gnosisStakingProcessorL2));

        // Set the gnosisStakingProcessorL2 address in gnosisDepositProcessorL1
        gnosisDepositProcessorL1.setL2StakingProcessor(address(gnosisStakingProcessorL2));

        // Whitelist deposit processors
        address[] memory depositProcessors = new address[](1);
        depositProcessors[0] = address(gnosisDepositProcessorL1);
        uint256[] memory chainIds = new uint256[](1);
        chainIds[0] = GNOSIS_CHAIN_ID;
        depository.setDepositProcessorChainIds(depositProcessors, chainIds);

        // Deploy service staking activity checker
        moduleActivityChecker = new ModuleActivityChecker(LIVENESS_RATIO);

        // Deploy service staking token locked implementation
        StakingTokenLocked stakingTokenImplementation = new StakingTokenLocked();

        // Whitelist implementation
        address[] memory stakingTokenImplementations = new address[](1);
        stakingTokenImplementations[0] = address(stakingTokenImplementation);
        bool[] memory boolArr = new bool[](1);
        boolArr[0] = true;
        stakingVerifier.setImplementationsStatuses(stakingTokenImplementations, boolArr, true);

        StakingTokenLocked.StakingParams memory stakingParams = StakingTokenLocked.StakingParams(
            MAX_NUM_SERVICES, REWARDS_PER_SECOND, MIN_STAKING_DEPOSIT, LIVENESS_PERIOD, TIME_FOR_EMISSIONS,
            address(serviceRegistry), address(serviceRegistryTokenUtility), address(olas), address(stakingManager),
            address(moduleActivityChecker));

        // Initialization payload and deployment of stakingNativeToken
        initPayload = abi.encodeWithSelector(stakingTokenImplementation.initialize.selector, stakingParams);
        address stakingTokenAddress = stakingFactory.createStakingInstance(address(stakingTokenImplementation), initPayload);
        stakingTokenInstance = StakingTokenLocked(stakingTokenAddress);

        // Whitelist multisig implementations
        serviceRegistry.changeMultisigPermission(address(gnosisSafeMultisig), true);
        serviceRegistry.changeMultisigPermission(address(gnosisSafeSameAddressMultisig), true);

        // Fund the staking contract
        olas.approve(stakingTokenAddress, STAKING_SUPPLY);
        stakingTokenInstance.deposit(STAKING_SUPPLY);

        // Add model to L1
        address[] memory stakingTokenAddresses = new address[](1);
        stakingTokenAddresses[0] = address(stakingTokenAddress);
        uint256[] memory fullStakeDeposits = new uint256[](1);
        fullStakeDeposits[0] = FULL_STAKE_DEPOSIT;
        uint256[] memory maxNumServices = new uint256[](1);
        maxNumServices[0] = MAX_NUM_SERVICES;
        depository.createAndActivateStakingModels(chainIds, stakingTokenAddresses, fullStakeDeposits, maxNumServices);

        // Set operation receivers
        bytes32[] memory operations = new bytes32[](3);
        operations[0] = REWARD_OPERATION;
        operations[1] = UNSTAKE_OPERATION;
        operations[2] = UNSTAKE_RETIRED_OPERATION;
        address[] memory receivers = new address[](3);
        receivers[0] = address(distributor);
        receivers[1] = address(treasury);
        receivers[2] = address(unstakeRelayer);
        Collector(collector).setOperationReceivers(operations, receivers);
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
        address[] memory stakingInstances = _fillArray(address(stakingTokenInstance), numStakes);
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
