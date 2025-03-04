/*global describe, context, beforeEach, it*/
const { expect } = require("chai");
const { ethers } = require("hardhat");

const main = async () => {
    let serviceRegistry;
    let serviceRegistryTokenUtility;
    let operatorWhitelist;
    let serviceManager;
    let olas;
    let ve;
    let st;
    let gnosisSafe;
    let gnosisSafeL2;
    let gnosisSafeProxyFactory;
    let safeModuleInitializer;
    let fallbackHandler;
    let gnosisSafeMultisig;
    let gnosisSafeSameAddressMultisig;
    let activityChecker;
    let stakingFactory;
    let stakingVerifier;
    let lock;
    let depository;
    let treasury;
    let collector;
    let beacon;
    let bridgeRelayer;
    let activityModule;
    let stakingManager;
    let stakingTokenImplementation;
    let stakingTokenInstance;
    let gnosisDepositProcessorL1;
    let gnosisStakingProcessorL2;
    let signers;
    let deployer;
    let agent;
    let bytecodeHash;
    const AddressZero = ethers.constants.AddressZero;
    const HashZero = ethers.constants.HashZero;
    const oneDay = 86400;
    const defaultHash = "0x" + "5".repeat(64);
    const regDeposit = ethers.utils.parseEther("10000");
    const serviceId = 1;
    const agentId = 1;
    const livenessPeriod = oneDay; // 24 hours
    const initSupply = "5" + "0".repeat(26);
    const livenessRatio = "11111111111111"; // 1 transaction per 25 hours
    const maxNumServices = 100;
    const minStakingDeposit = regDeposit;
    const timeForEmissions = oneDay * 30;
    let serviceParams = {
        maxNumServices,
        rewardsPerSecond: "5" + "0".repeat(14),
        minStakingDeposit,
        livenessPeriod,
        timeForEmissions,
        serviceRegistry: AddressZero,
        serviceRegistryTokenUtility: AddressZero,
        stakingToken: AddressZero,
        stakingManager: AddressZero,
        activityChecker: AddressZero
    };
    const apyLimit = ethers.utils.parseEther("3");
    const lockFactor = 100;
    const maxStakingLimit = ethers.utils.parseEther("20000");
    const gnosisChainId = 100;
    const stakingSupply = (regDeposit.mul(2)).mul(ethers.BigNumber.from(maxNumServices));
    const bridgePayload = "0x";

    signers = await ethers.getSigners();
    deployer = signers[0];
    agent = signers[0];

    const serviceRegistry = await ethers.getContractAt("ServiceRegistryL2", parsedData.serviceRegistryAddress);
    serviceParams.serviceRegistry = serviceRegistry.address;

    const ServiceRegistryTokenUtility = await ethers.getContractFactory("ServiceRegistryTokenUtility");
    serviceRegistryTokenUtility = await ServiceRegistryTokenUtility.deploy(serviceRegistry.address);
    await serviceRegistryTokenUtility.deployed();
    serviceParams.serviceRegistryTokenUtility = serviceRegistryTokenUtility.address;

    const OperatorWhitelist = await ethers.getContractFactory("OperatorWhitelist");
    operatorWhitelist = await OperatorWhitelist.deploy(serviceRegistry.address);
    await operatorWhitelist.deployed();

    const ServiceManagerToken = await ethers.getContractFactory("ServiceManagerToken");
    serviceManager = await ServiceManagerToken.deploy(serviceRegistry.address, serviceRegistryTokenUtility.address,
        operatorWhitelist.address);
    await serviceManager.deployed();

    const olas = await ethers.getContractAt("ERC20Token", parsedData.olasAddress);
    serviceParams.stakingToken = olas.address;

    // Mint tokens to the deployer
    await olas.mint(deployer.address, initSupply);

    const VE = await ethers.getContractFactory("MockVE");
    ve = await VE.deploy(olas.address);
    await ve.deployed();

    const SToken = await ethers.getContractFactory("stOLAS");
    st = await SToken.deploy(olas.address);
    await st.deployed();

    const GnosisSafe = await ethers.getContractFactory("GnosisSafe");
    gnosisSafe = await GnosisSafe.deploy();
    await gnosisSafe.deployed();

    const GnosisSafeL2 = await ethers.getContractFactory("GnosisSafeL2");
    gnosisSafeL2 = await GnosisSafeL2.deploy();
    await gnosisSafeL2.deployed();

    const GnosisSafeProxyFactory = await ethers.getContractFactory("GnosisSafeProxyFactory");
    gnosisSafeProxyFactory = await GnosisSafeProxyFactory.deploy();
    await gnosisSafeProxyFactory.deployed();

    const SafeToL2Setup = await ethers.getContractFactory("SafeToL2Setup");
    safeModuleInitializer = await SafeToL2Setup.deploy();
    await safeModuleInitializer.deployed();

    const FallbackHandler = await ethers.getContractFactory("DefaultCallbackHandler");
    fallbackHandler = await FallbackHandler.deploy();
    await fallbackHandler.deployed();

    const GnosisSafeProxy = await ethers.getContractFactory("GnosisSafeProxy");
    const gnosisSafeProxy = await GnosisSafeProxy.deploy(gnosisSafe.address);
    await gnosisSafeProxy.deployed();
    const bytecode = await ethers.provider.getCode(gnosisSafeProxy.address);
    bytecodeHash = ethers.utils.keccak256(bytecode);

    const GnosisSafeMultisig = await ethers.getContractFactory("GnosisSafeMultisig");
    gnosisSafeMultisig = await GnosisSafeMultisig.deploy(gnosisSafe.address, gnosisSafeProxyFactory.address);
    await gnosisSafeMultisig.deployed();

    const GnosisSafeSameAddressMultisig = await ethers.getContractFactory("GnosisSafeSameAddressMultisig");
    gnosisSafeSameAddressMultisig = await GnosisSafeSameAddressMultisig.deploy(bytecodeHash);
    await gnosisSafeSameAddressMultisig.deployed();

    const Lock = await ethers.getContractFactory("Lock");
    lock = await Lock.deploy(olas.address, ve.address);
    await lock.deployed();

    const LockProxy = await ethers.getContractFactory("Proxy");
    let initPayload = lock.interface.encodeFunctionData("initialize", []);
    const lockProxy = await LockProxy.deploy(lock.address, initPayload);
    await lockProxy.deployed();
    lock = await ethers.getContractAt("Lock", lockProxy.address);

    // Approve initial lock
    await olas.approve(lock.address, ethers.utils.parseEther("1"));
    // Set governor and create first lock
    // Governor address is irrelevant for testing
    await lock.setGovernorAndCreateFirstLock(deployer.address);

    const Depository = await ethers.getContractFactory("Depository");
    depository = await Depository.deploy(olas.address, st.address, ve.address, lock.address);
    await depository.deployed();

    const DepositoryProxy = await ethers.getContractFactory("Proxy");
    initPayload = depository.interface.encodeFunctionData("initialize", [lockFactor, maxStakingLimit]);
    const depositoryProxy = await DepositoryProxy.deploy(depository.address, initPayload);
    await depositoryProxy.deployed();
    depository = await ethers.getContractAt("Depository", depositoryProxy.address);

    const Treasury = await ethers.getContractFactory("Treasury");
    treasury = await Treasury.deploy(olas.address, st.address, depository.address);
    await treasury.deployed();

    const TreasuryProxy = await ethers.getContractFactory("Proxy");
    initPayload = treasury.interface.encodeFunctionData("initialize", []);
    const treasuryProxy = await TreasuryProxy.deploy(treasury.address, initPayload);
    await treasuryProxy.deployed();
    treasury = await ethers.getContractAt("Treasury", treasuryProxy.address);

    // Change managers for stOLAS
    // Only Treasury contract can mint OLAS
    await st.changeManagers(treasury.address, depository.address);

    // Change treasury address in depository
    await depository.changeTreasury(treasury.address);

    const StakingVerifier = await ethers.getContractFactory("StakingVerifier");
    stakingVerifier = await StakingVerifier.deploy(olas.address, serviceRegistry.address,
        serviceRegistryTokenUtility.address, minStakingDeposit, timeForEmissions, maxNumServices, apyLimit);
    await stakingVerifier.deployed();

    const StakingFactory = await ethers.getContractFactory("StakingFactory");
    stakingFactory = await StakingFactory.deploy(stakingVerifier.address);
    await stakingFactory.deployed();

    const Collector = await ethers.getContractFactory("Collector");
    collector = await Collector.deploy(olas.address, st.address);
    await collector.deployed();

    const CollectorProxy = await ethers.getContractFactory("Proxy");
    initPayload = collector.interface.encodeFunctionData("initialize", []);
    const collectorProxy = await CollectorProxy.deploy(collector.address, initPayload);
    await collectorProxy.deployed();
    collector = await ethers.getContractAt("Collector", collectorProxy.address);

    const ActivityModule = await ethers.getContractFactory("ActivityModule");
    activityModule = await ActivityModule.deploy(olas.address, collector.address);
    await activityModule.deployed();

    const Beacon = await ethers.getContractFactory("Beacon");
    beacon = await Beacon.deploy(activityModule.address);
    await beacon.deployed();

    const StakingManager = await ethers.getContractFactory("StakingManager");
    stakingManager = await StakingManager.deploy(olas.address, treasury.address, serviceManager.address,
        stakingFactory.address, safeModuleInitializer.address, gnosisSafeL2.address, beacon.address,
        collector.address, agentId, defaultHash);
    await stakingManager.deployed();

    // Initialize stakingManager
    const StakingManagerProxy = await ethers.getContractFactory("Proxy");
    initPayload = stakingManager.interface.encodeFunctionData("initialize", [gnosisSafeMultisig.address,
        gnosisSafeSameAddressMultisig.address, fallbackHandler.address]);
    const stakingManagerProxy = await StakingManagerProxy.deploy(stakingManager.address, initPayload);
    await stakingManagerProxy.deployed();
    stakingManager = await ethers.getContractAt("StakingManager", stakingManagerProxy.address);
    serviceParams.stakingManager = stakingManager.address;

    // Fund staking manager with native to support staking creation
    await deployer.sendTransaction({to: stakingManager.address, value: ethers.utils.parseEther("1")});

    const BridgeRelayer = await ethers.getContractFactory("BridgeRelayer");
    bridgeRelayer = await BridgeRelayer.deploy(olas.address);
    await bridgeRelayer.deployed();

    const GnosisDepositProcessorL1 = await ethers.getContractFactory("GnosisDepositProcessorL1");
    gnosisDepositProcessorL1 = await GnosisDepositProcessorL1.deploy(olas.address, depository.address,
        bridgeRelayer.address, bridgeRelayer.address, gnosisChainId);
    await gnosisDepositProcessorL1.deployed();

    const GnosisStakingProcessorL2 = await ethers.getContractFactory("GnosisStakingProcessorL2");
    gnosisStakingProcessorL2 = await GnosisStakingProcessorL2.deploy(olas.address, stakingManager.address,
        bridgeRelayer.address, bridgeRelayer.address, gnosisDepositProcessorL1.address, gnosisChainId);
    await gnosisStakingProcessorL2.deployed();

    // changeStakingProcessorL2 for collector
    await collector.changeStakingProcessorL2(gnosisStakingProcessorL2.address);

    // changeStakingProcessorL2 for stakingManager
    await stakingManager.changeStakingProcessorL2(gnosisStakingProcessorL2.address);

    // Set the gnosisStakingProcessorL2 address in gnosisDepositProcessorL1
    await gnosisDepositProcessorL1.setL2StakingProcessor(gnosisStakingProcessorL2.address);

    // Whitelist deposit processors
    await depository.setDepositProcessorChainIds([gnosisDepositProcessorL1.address], [gnosisChainId]);

    const ActivityChecker = await ethers.getContractFactory("ModuleActivityChecker");
    activityChecker = await ActivityChecker.deploy(livenessRatio);
    await activityChecker.deployed();
    serviceParams.activityChecker = activityChecker.address;

    const StakingTokenLocked = await ethers.getContractFactory("StakingTokenLocked");
    stakingTokenImplementation = await StakingTokenLocked.deploy();
    await stakingTokenImplementation.deployed();

    // Whitelist implementation
    await stakingVerifier.setImplementationsStatuses([stakingTokenImplementation.address], [true], true);

    initPayload = stakingTokenImplementation.interface.encodeFunctionData("initialize", [serviceParams]);
    const tx = await stakingFactory.createStakingInstance(stakingTokenImplementation.address, initPayload);
    const res = await tx.wait();
    // Get staking contract instance address from the event
    const stakingTokenAddress = "0x" + res.logs[0].topics[2].slice(26);
    stakingTokenInstance = await ethers.getContractAt("StakingTokenLocked", stakingTokenAddress);

    // Set service manager
    await serviceRegistry.changeManager(serviceManager.address);
    await serviceRegistryTokenUtility.changeManager(serviceManager.address);

    // Whitelist gnosis multisig implementations
    await serviceRegistry.changeMultisigPermission(gnosisSafeMultisig.address, true);
    await serviceRegistry.changeMultisigPermission(gnosisSafeSameAddressMultisig.address, true);

    // Fund the staking contract
    await olas.approve(stakingTokenAddress, stakingSupply);
    await stakingTokenInstance.deposit(stakingSupply);

    // Add model to L1
    await depository.createAndActivateStakingModels([gnosisChainId], [stakingTokenAddress], [stakingSupply]);
};

main()
    .then(() => process.exit(0))
    .catch(error => {
        console.error(error);
        process.exit(1);
    });
