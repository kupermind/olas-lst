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
    let ve;
    let st;
    let gnosisSafe;
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
    let activityModule;
    let stakingManager;
    let stakingTokenImplementation;
    let stakingTokenInstance;
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
    const lockFactor = 100;
    const chainId = 31337;
    const gnosisChainId = 100;
    const stakingSupply = ethers.utils.parseEther("10000");

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

        const ERC20Token = await ethers.getContractFactory("ERC20Token");
        olas = await ERC20Token.deploy();
        await olas.deployed();

        const VE = await ethers.getContractFactory("MockVE");
        ve = await VE.deploy(olas.address);
        await ve.deployed();

        const SToken = await ethers.getContractFactory("stOLAS");
        st = await SToken.deploy(olas.address);
        await st.deployed();

        const GnosisSafe = await ethers.getContractFactory("GnosisSafe");
        gnosisSafe = await GnosisSafe.deploy();
        await gnosisSafe.deployed();

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
        serviceParams.proxyHash = bytecodeHash;

        const GnosisSafeMultisig = await ethers.getContractFactory("GnosisSafeMultisig");
        gnosisSafeMultisig = await GnosisSafeMultisig.deploy(gnosisSafe.address, gnosisSafeProxyFactory.address);
        await gnosisSafeMultisig.deployed();

        const GnosisSafeSameAddressMultisig = await ethers.getContractFactory("GnosisSafeSameAddressMultisig");
        gnosisSafeSameAddressMultisig = await GnosisSafeSameAddressMultisig.deploy(bytecodeHash);
        await gnosisSafeSameAddressMultisig.deployed();

        const Depository = await ethers.getContractFactory("Depository");
        depository = await Depository.deploy(olas.address, AddressZero);
        await depository.deployed();

        const Lock = await ethers.getContractFactory("Lock");
        lock = await Lock.deploy(olas.address, ve.address, depository.address);
        await lock.deployed();

        const Treasury = await ethers.getContractFactory("Treasury");
        treasury = await Treasury.deploy(olas.address, ve.address, st.address, depository.address, lock.address, lockFactor);
        await treasury.deployed();

        // Change treasury address in depository
        await depository.changeTreasury(treasury.address);

        // Only Treasury contract can mint proxy OLAS
        await st.changeMinter(treasury.address);

        const StakingVerifier = await ethers.getContractFactory("StakingVerifier");
        stakingVerifier = await StakingVerifier.deploy(olas.address, serviceRegistry.address,
            serviceRegistryTokenUtility.address, minStakingDeposit, timeForEmissions, maxNumServices, apyLimit);
        await stakingVerifier.deployed();

        const StakingFactory = await ethers.getContractFactory("StakingFactory");
        stakingFactory = await StakingFactory.deploy(stakingVerifier.address);
        await stakingFactory.deployed();

        const Collector = await ethers.getContractFactory("Collector");
        collector = await Collector.deploy(olas.address, AddressZero);
        await collector.deployed();

        const ActivityModule = await ethers.getContractFactory("ActivityModule");
        activityModule = await ActivityModule.deploy(olas.address, collector.address);
        await activityModule.deployed();

        const Beacon = await ethers.getContractFactory("Beacon");
        beacon = await Beacon.deploy(activityModule.address);
        await beacon.deployed();

        const StakingManager = await ethers.getContractFactory("StakingManager");
        stakingManager = await StakingManager.deploy(olas.address, serviceManager.address,
            stakingFactory.address, gnosisSafeMultisig.address, gnosisSafeSameAddressMultisig.address,
            beacon.address, safeModuleInitializer.address, fallbackHandler.address, collector.address, agentId, defaultHash);
        await stakingManager.deployed();

        const BridgeRelayer = await ethers.getContractFactory("BridgeRelayer");
        bridgeRelayer = await BridgeRelayer.deploy(olas.address);
        await bridgeRelayer.deployed();

        const GnosisDepositProcessorL1 = await ethers.getContractFactory("GnosisDepositProcessorL1");
        gnosisDepositProcessorL1 = await GnosisDepositProcessorL1.deploy(olas.address, depository.address,
            bridgeRelayer.address, bridgeRelayer.address, gnosisChainId);
        await gnosisDepositProcessorL1.deployed();

        const GnosisStakingProcessorL2 = await ethers.getContractFactory("GnosisStakingProcessorL2");
        gnosisStakingProcessorL2 = await GnosisStakingProcessorL2.deploy(olas.address, stakingManager.address,
            bridgeRelayer.address, bridgeRelayer.address, gnosisDepositProcessorL1.address, chainId);
        await gnosisStakingProcessorL2.deployed();

        // Change collector address
        await collector.changeStakingProcessorL2(gnosisStakingProcessorL2.address);

        // Set the gnosisStakingProcessorL2 address in gnosisDepositProcessorL1
        await gnosisDepositProcessorL1.setL2StakingProcessor(gnosisStakingProcessorL2.address);

        const ActivityChecker = await ethers.getContractFactory("MockActivityChecker");
        activityChecker = await ActivityChecker.deploy(livenessRatio);
        await activityChecker.deployed();
        serviceParams.activityChecker = activityChecker.address;

        const StakingTokenLocked = await ethers.getContractFactory("StakingTokenLocked");
        stakingTokenImplementation = await StakingTokenLocked.deploy();
        const initPayload = stakingTokenImplementation.interface.encodeFunctionData("initialize",
            [serviceParams, serviceRegistryTokenUtility.address, olas.address, stakingManager.address]);
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

        // Mint tokens to the deployer
        await olas.mint(deployer.address, initSupply);

        // Fund the staking contract
        await olas.approve(stakingTokenAddress, stakingSupply);
        await stakingTokenInstance.deposit(stakingSupply);

        // Add agent as a guardian on L1 and L2
        await depository.setGuardianServiceStatuses([agent.address], [true]);
        await stakingManager.setGuardianServiceStatuses([agent.address], [true]);

        // Add model to L1
        await depository.createAndActivateStakingModels([gnosisChainId], [stakingTokenAddress], [stakingSupply]);
    });

    context("Staking", function () {
        it.only("E2E liquid staking", async function () {
            // Take a snapshot of the current state of the blockchain
            const snapshot = await helpers.takeSnapshot();
            return;

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

            console.log("OLAS rewards available on L2 staking contract:", (await stakingTokenInstance.availableRewards()).toString());
            console.log("Picking up event on L2 by an agent");

            // Create and stake the service on L2
            console.log("Minting proxyOLAS and staking it by the agent");
            const depositId = 1;
            await stakingManager.connect(agent).stake(deployer.address, depositId, olasAmount, stakingTokenInstance.address, {value: 2});

            // Check the reward
            let serviceInfo = await stakingTokenInstance.mapServiceInfo(serviceId);
            console.log("Service multisig address:", serviceInfo.multisig);
            console.log("Reward before checkpoint", serviceInfo.reward.toString());

            // Increase the time for the livenessPeriod
            console.log("Wait for liveness period to pass");
            await helpers.time.increase(maxInactivity);

            // Call the checkpoint
            console.log("Calling checkpoint by the agent");
            await stakingTokenInstance.connect(agent).checkpoint();

            // Check the reward
            serviceInfo = await stakingTokenInstance.mapServiceInfo(serviceId);
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
            console.log("Withdraw from StakingManager contract by the agent");
            await stakingManager.connect(agent).withdraw(deployer.address, withdrawId, stBalance, olasIncrease,
                stakingTokenInstance.address);

            const multisigBalance = await olas.balanceOf(serviceInfo.multisig);
            console.log("Multisig balance", multisigBalance.toString());

            // Approve for corresponding multisig
            const multisig = await ethers.getContractAt("GnosisSafe", serviceInfo.multisig);
            let nonce = await multisig.nonce();
            let txHashData = await safeContracts.buildContractCall(olas, "approve",
                [stakingManager.address, serviceInfo.reward], nonce, 0, 0);
            let signMessageData = await safeContracts.safeSignMessage(agent, multisig, txHashData, 0);
            await safeContracts.executeTx(multisig, txHashData, [signMessageData], 0);

            // Bridge
            console.log("Bridge transfer of OLAS from L2 to L1");
            await stakingManager.connect(agent).bridgeTransfer(multisig.address, depository.address);

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
