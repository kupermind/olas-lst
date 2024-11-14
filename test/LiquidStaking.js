/*global describe, context, beforeEach, it*/
const { expect } = require("chai");
const { ethers } = require("hardhat");
const helpers = require("@nomicfoundation/hardhat-network-helpers");

describe("Liquid Staking", function () {
    let serviceRegistry;
    let serviceRegistryTokenUtility;
    let operatorWhitelist;
    let serviceManager;
    let olas;
    let proxyOlas;
    let ve;
    let st;
    let gnosisSafe;
    let gnosisSafeProxyFactory;
    let fallbackHandler;
    let gnosisSafeMultisig;
    let gnosisSafeSameAddressMultisig;
    let activityChecker;
    let stakingFactory;
    let stakingVerifier;
    let lock;
    let depository;
    let stakerL2;
    let stakingTokenImplementation;
    let stakingProxyToken;
    let signers;
    let deployer;
    let agent;
    let agentInstances;
    let bytecodeHash;
    const AddressZero = ethers.constants.AddressZero;
    const HashZero = ethers.constants.HashZero;
    const oneDay = 86400;
    const defaultHash = "0x" + "5".repeat(64);
    const regDeposit = ethers.utils.parseEther("500");
    const regBond = regDeposit;
    const serviceId = 1;
    const agentId = 1;
    const modelId = 0;
    const agentIds = [1];
    const agentParams = [[1, regBond]];
    const threshold = 1;
    const livenessPeriod = 10; // Ten seconds
    const initSupply = "5" + "0".repeat(26);
    const payload = "0x";
    const livenessRatio = "1" + "0".repeat(16); // 0.01 transaction per second (TPS)
    maxNumServices = 100;
    minStakingDeposit = regDeposit;
    timeForEmissions = oneDay * 30;
    let serviceParams = {
        metadataHash: defaultHash,
        maxNumServices,
        rewardsPerSecond: "1" + "0".repeat(13),
        minStakingDeposit,
        minNumStakingPeriods: 3,
        maxNumInactivityPeriods: 3,
        livenessPeriod,
        timeForEmissions,
        numAgentInstances: 1,
        agentIds,
        threshold,
        configHash: HashZero,
        proxyHash: HashZero,
        serviceRegistry: AddressZero,
        activityChecker: AddressZero
    };
    const maxInactivity = serviceParams.maxNumInactivityPeriods * livenessPeriod + 1;
    const apyLimit = ethers.utils.parseEther("3");
    const vesting = oneDay;

    let stakingModel = {
        stakingProxy: AddressZero,
        supply: 0,
        remainder: 0,
        chainId: 0,
        active: true
    }

    beforeEach(async function () {
        signers = await ethers.getSigners();
        deployer = signers[0];
        agent = signers[0];
        agentInstances = [signers[2], signers[3], signers[4]];

        const ServiceRegistry = await ethers.getContractFactory("ServiceRegistryL2");
        serviceRegistry = await ServiceRegistry.deploy("Service Registry L2", "SERVICE", "https://localhost/service/");
        await serviceRegistry.deployed();
        serviceParams.serviceRegistry = serviceRegistry.address;

        const ServiceRegistryTokenUtility = await ethers.getContractFactory("ServiceRegistryTokenUtility");
        serviceRegistryTokenUtility = await ServiceRegistryTokenUtility.deploy(serviceRegistry.address);
        await serviceRegistry.deployed();

        const OperatorWhitelist = await ethers.getContractFactory("OperatorWhitelist");
        operatorWhitelist = await OperatorWhitelist.deploy(serviceRegistry.address);
        await operatorWhitelist.deployed();

        const ServiceManagerToken = await ethers.getContractFactory("ServiceManagerToken");
        serviceManager = await ServiceManagerToken.deploy(serviceRegistry.address, serviceRegistryTokenUtility.address,
            operatorWhitelist.address);
        await serviceManager.deployed();

        const Token = await ethers.getContractFactory("proxyOLAS");
        olas = await Token.deploy();
        await olas.deployed();

        proxyOlas = await Token.deploy();
        await proxyOlas.deployed();

        const VE = await ethers.getContractFactory("MockVE");
        ve = await VE.deploy(olas.address);
        await ve.deployed();

        const SToken = await ethers.getContractFactory("stOLAS");
        st = await SToken.deploy();
        await st.deployed();

        const GnosisSafe = await ethers.getContractFactory("GnosisSafe");
        gnosisSafe = await GnosisSafe.deploy();
        await gnosisSafe.deployed();

        const GnosisSafeProxyFactory = await ethers.getContractFactory("GnosisSafeProxyFactory");
        gnosisSafeProxyFactory = await GnosisSafeProxyFactory.deploy();
        await gnosisSafeProxyFactory.deployed();

        const FallbackHandler = await ethers.getContractFactory("DefaultCallbackHandler");
        fallbackHandler = await FallbackHandler.deploy();
        await fallbackHandler.deployed();

        const GnosisSafeProxy = await ethers.getContractFactory("GnosisSafeProxy");
        const gnosisSafeProxy = await GnosisSafeProxy.deploy(gnosisSafe.address);
        await gnosisSafeProxy.deployed();
        const bytecode = await ethers.provider.getCode(gnosisSafeProxy.address);
        bytecodeHash = ethers.utils.keccak256(bytecode);
        serviceParams.proxyHash = bytecodeHash;

        const GnosisSafeMultisig = await ethers.getContractFactory("GnosisSafeMultisig");
        gnosisSafeMultisig = await GnosisSafeMultisig.deploy(gnosisSafe.address, gnosisSafeProxyFactory.address);
        await gnosisSafeMultisig.deployed();

        const GnosisSafeSameAddressMultisig = await ethers.getContractFactory("GnosisSafeSameAddressMultisig");
        gnosisSafeSameAddressMultisig = await GnosisSafeSameAddressMultisig.deploy(bytecodeHash);
        await gnosisSafeSameAddressMultisig.deployed();

        const Depository = await ethers.getContractFactory("Depository");
        depository = await Depository.deploy(olas.address, ve.address, st.address, AddressZero, vesting);
        await depository.deployed();

        // Only Depository contract can mint proxy OLAS
        await st.changeMinter(depository.address);

        const Lock = await ethers.getContractFactory("Lock");
        lock = await Lock.deploy(olas.address, ve.address, depository.address);
        await lock.deployed();
        await depository.changeLockImplementation(lock.address);

        const StakingVerifier = await ethers.getContractFactory("StakingVerifier");
        stakingVerifier = await StakingVerifier.deploy(olas.address, proxyOlas.address, serviceRegistry.address,
            serviceRegistryTokenUtility.address, minStakingDeposit, timeForEmissions, maxNumServices, apyLimit);
        await stakingVerifier.deployed();

        const StakingFactory = await ethers.getContractFactory("StakingFactory");
        stakingFactory = await StakingFactory.deploy(stakingVerifier.address);
        await stakingFactory.deployed();

        const StakerL2 = await ethers.getContractFactory("StakerL2");
        stakerL2 = await StakerL2.deploy(olas.address, proxyOlas.address, serviceManager.address,
            stakingFactory.address, gnosisSafeMultisig.address, gnosisSafeSameAddressMultisig.address,
            fallbackHandler.address, agentId, defaultHash);
        await stakerL2.deployed();

        // Only stakerL2 contract can mint proxy OLAS
        await proxyOlas.changeMinter(stakerL2.address);

        const ActivityChecker = await ethers.getContractFactory("MockActivityChecker");
        activityChecker = await ActivityChecker.deploy(livenessRatio);
        await activityChecker.deployed();
        serviceParams.activityChecker = activityChecker.address;

        const StakingProxyToken = await ethers.getContractFactory("StakingProxyToken");
        stakingTokenImplementation = await StakingProxyToken.deploy();
        const initPayload = stakingTokenImplementation.interface.encodeFunctionData("initialize",
            [serviceParams, serviceRegistryTokenUtility.address, olas.address, proxyOlas.address]);
        const tx = await stakingFactory.createStakingInstance(stakingTokenImplementation.address, initPayload);
        const res = await tx.wait();
        // Get staking contract instance address from the event
        const stakingTokenAddress = "0x" + res.logs[0].topics[2].slice(26);
        stakingProxyToken = await ethers.getContractAt("StakingProxyToken", stakingTokenAddress);

        // Set service manager
        await serviceRegistry.changeManager(serviceManager.address);
        await serviceRegistryTokenUtility.changeManager(serviceManager.address);

        // Whitelist gnosis multisig implementations
        await serviceRegistry.changeMultisigPermission(gnosisSafeMultisig.address, true);
        await serviceRegistry.changeMultisigPermission(gnosisSafeSameAddressMultisig.address, true);

        // Mint tokens to the deployer
        await olas.mint(deployer.address, initSupply);

        // Fund the staking contract
        await olas.approve(stakingTokenAddress, ethers.utils.parseEther("10000"));
        await stakingProxyToken.deposit(ethers.utils.parseEther("10000"));

        // Add agent as a guardian on L1 and L2
        await depository.setGuardianServiceStatuses([agent.address], [true]);
        await stakerL2.setGuardianServiceStatuses([agent.address], [true]);

        // Add model to L1
        stakingModel.stakingToken = stakingTokenAddress;
        stakingModel.supply = await stakingProxyToken.emissionsAmount();
        stakingModel.remainder = stakingModel.supply;
        await depository.addStakingModels([stakingModel]);
    });

    context("Staking", function () {
        it("E2E liquid staking", async function () {
            // Take a snapshot of the current state of the blockchain
            const snapshot = await helpers.takeSnapshot();

            // Get OLAS amount to stake
            const olasAmount = minStakingDeposit.mul(3);

            // Approve OLAS for depository
            await olas.approve(depository.address, olasAmount);

            // Stake OLAS on L1
            await depository.deposit(modelId, olasAmount);

            const depositId = 1;

            // Create and stake the service on L2
            await stakerL2.connect(agent).stake(deployer.address, depositId, olasAmount, stakingProxyToken.address, {value: 2});

            // Increase the time for the livenessPeriod
            await helpers.time.increase(livenessPeriod + 10);

            // Call the checkpoint
            await stakingProxyToken.connect(agent).checkpoint();

            // Check the reward
            const serviceInfo = await stakingProxyToken.mapServiceInfo(serviceId);
            console.log(serviceInfo.reward.toString());

            // const lockProxy = await ethers.getContractAt("Lock", lockProxy.address);

            // Restore a previous state of blockchain
            snapshot.restore();
        });
    });
});
