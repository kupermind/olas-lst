/*global describe, context, beforeEach, it*/
const { expect } = require("chai");
const { ethers } = require("hardhat");
const helpers = require("@nomicfoundation/hardhat-network-helpers");
const safeContracts = require("@gnosis.pm/safe-contracts");

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
            [serviceParams, serviceRegistryTokenUtility.address, proxyOlas.address, olas.address]);
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

            console.log("L1");

            // Get OLAS amount to stake
            const olasAmount = minStakingDeposit.mul(3);

            // Approve OLAS for depository
            console.log("User approves OLAS for depository:", olasAmount.toString());
            await olas.approve(depository.address, olasAmount);

            // Stake OLAS on L1
            console.log("User deposits OLAS for stOLAS");
            await depository.deposit(modelId, olasAmount);
            let stBalance = await st.balanceOf(deployer.address);
            console.log("User stOLAS balance now:", stBalance.toString());

            console.log("\nL2");

            console.log("OLAS rewards available on L2 staking contract:", (await stakingProxyToken.availableRewards()).toString());
            console.log("Picking up event on L2 by an agent");

            // Create and stake the service on L2
            console.log("Minting proxyOLAS and staking it by the agent");
            const depositId = 1;
            await stakerL2.connect(agent).stake(deployer.address, depositId, olasAmount, stakingProxyToken.address, {value: 2});

            // Check the reward
            let serviceInfo = await stakingProxyToken.mapServiceInfo(serviceId);
            console.log("Service multisig address:", serviceInfo.multisig);
            console.log("Reward before checkpoint", serviceInfo.reward.toString());

            // Increase the time for the livenessPeriod
            console.log("Wait for liveness period to pass");
            await helpers.time.increase(maxInactivity);

            // Call the checkpoint
            console.log("Calling checkpoint by the agent");
            await stakingProxyToken.connect(agent).checkpoint();

            // Check the reward
            serviceInfo = await stakingProxyToken.mapServiceInfo(serviceId);
            console.log("Reward after checkpoint", serviceInfo.reward.toString());

            console.log("\nL1");

            const stakingTerm = await depository.mapStakingTerms(deployer.address);
            let veBalance = await ve.getVotes(stakingTerm.lockProxy);

            //const lockProxy = await ethers.getContractAt("Lock", lockProxyAddress);
            //console.log(await lockProxy.depository());

            console.log("User current veOLAS balance:", veBalance.toString());

            console.log("User approves stOLAS for depository:", stBalance.toString());
            await st.approve(depository.address, stBalance);

            console.log("User requests stOLAS to get OLAS");
            await depository.requestToWithdraw(stBalance);
            const olasIncrease = await depository.getOLASAmount(stBalance);

            console.log("\nL2");

            console.log("Picking up event on L2 by the agent");
            const withdrawId = 1;
            console.log("Withdraw from StakerL2 contract by the agent");
            await stakerL2.connect(agent).withdraw(deployer.address, withdrawId, stBalance, olasIncrease,
                stakingProxyToken.address);

            const multisigBalance = await olas.balanceOf(serviceInfo.multisig);
            console.log("Multisig balance", multisigBalance.toString());

            // Approve for corresponding multisig
            const multisig = await ethers.getContractAt("GnosisSafe", serviceInfo.multisig);
            let nonce = await multisig.nonce();
            let txHashData = await safeContracts.buildContractCall(olas, "approve",
                [stakerL2.address, serviceInfo.reward], nonce, 0, 0);
            let signMessageData = await safeContracts.safeSignMessage(agent, multisig, txHashData, 0);
            await safeContracts.executeTx(multisig, txHashData, [signMessageData], 0);

            // Bridge
            console.log("Bridge transfer of OLAS from L2 to L1");
            await stakerL2.connect(agent).bridgeTransfer(multisig.address, depository.address);

            console.log("\nL1");

            console.log("For testing purposes only: stOLAS for OLAS is possible after veOLAS unlock");
            //await depository.unlock();

            const olasBalance = await olas.balanceOf(depository.address);
            console.log("OLAS balance in Depository on L1 before the unlock:", olasBalance.toString());

            console.log("veOLAS unlock");
            console.log("User gives back stOLAS to get OLAS");
            await depository.withdraw(stBalance);

            console.log("Increased User OLAS balance:", olasIncrease.toString());

            // Check updated veOLAS
            veBalance = await ve.getVotes(stakingTerm.lockProxy);
            console.log("User veOLAS balance now:", veBalance.toString());

            // Restore a previous state of blockchain
            snapshot.restore();
        });
    });
});
