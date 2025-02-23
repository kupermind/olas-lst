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
    const regDeposit = ethers.utils.parseEther("50");
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
        rewardsPerSecond: "1" + "0".repeat(12),
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
    const protocolFactor = 0;
    const chainId = 31337;
    const gnosisChainId = 100;
    const stakingRewardsPerEpoch = ethers.BigNumber.from(serviceParams.rewardsPerSecond).mul(ethers.BigNumber.from(maxNumServices)).mul(timeForEmissions);
    const stakingSupply = (regDeposit.mul(2)).mul(ethers.BigNumber.from(maxNumServices));
    const bridgePayload = "0x";

    beforeEach(async function () {
        signers = await ethers.getSigners();
        deployer = signers[0];
        agent = signers[0];

        const ServiceRegistry = await ethers.getContractFactory("ServiceRegistryL2");
        serviceRegistry = await ServiceRegistry.deploy("Service Registry L2", "SERVICE", "https://localhost/service/");
        await serviceRegistry.deployed();
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

        const ERC20Token = await ethers.getContractFactory("ERC20Token");
        olas = await ERC20Token.deploy();
        await olas.deployed();
        serviceParams.stakingToken = olas.address;

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

        const Depository = await ethers.getContractFactory("Depository");
        depository = await Depository.deploy(olas.address, st.address, ve.address, AddressZero, lock.address, lockFactor);
        await depository.deployed();

        const Treasury = await ethers.getContractFactory("Treasury");
        treasury = await Treasury.deploy(olas.address, st.address, depository.address);
        await treasury.deployed();

        // Change managers for stOLAS
        // Only Treasury contract can mint OLAS
        await st.changeManagers(treasury.address, depository.address);

        // Initialize lock
        await lock.initialize(treasury.address, deployer.address);

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
            bridgeRelayer.address, bridgeRelayer.address, gnosisDepositProcessorL1.address, chainId);
        await gnosisStakingProcessorL2.deployed();

        // Initialize collector address
        await collector.initialize(gnosisStakingProcessorL2.address, protocolFactor);

        // Set the gnosisStakingProcessorL2 address in gnosisDepositProcessorL1
        await gnosisDepositProcessorL1.setL2StakingProcessor(gnosisStakingProcessorL2.address);

        // Whitelist deposit processors
        await depository.setDepositProcessorChainIds([gnosisDepositProcessorL1.address], [gnosisChainId]);

        // Set rest of contracts in stakingManager
        await stakingManager.initialize(gnosisSafeMultisig.address, gnosisSafeSameAddressMultisig.address,
            fallbackHandler.address, gnosisStakingProcessorL2.address);

        const ActivityChecker = await ethers.getContractFactory("ModuleActivityChecker");
        activityChecker = await ActivityChecker.deploy(livenessRatio);
        await activityChecker.deployed();
        serviceParams.activityChecker = activityChecker.address;

        const StakingTokenLocked = await ethers.getContractFactory("StakingTokenLocked");
        stakingTokenImplementation = await StakingTokenLocked.deploy();
        const initPayload = stakingTokenImplementation.interface.encodeFunctionData("initialize", [serviceParams]);
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
        it("E2E liquid staking simple", async function () {
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
            await depository.deposit(olasAmount, [gnosisChainId], [[stakingTokenInstance.address]], [bridgePayload], [0]);
            let stBalance = await st.balanceOf(deployer.address);
            console.log("User stOLAS balance now:", stBalance.toString());
            let stTotalAssets = await st.totalAssets();
            console.log("OLAS total assets on stOLAS:", stTotalAssets.toString());

            let veBalance = await ve.getVotes(lock.address);
            console.log("Protocol current veOLAS balance:", veBalance.toString());

            console.log("\nL2");

            console.log("OLAS rewards available on L2 staking contract:", (await stakingTokenInstance.availableRewards()).toString());

            // Check the reward
            let serviceInfo = await stakingTokenInstance.mapServiceInfo(serviceId);
            console.log("Reward before checkpoint", serviceInfo.reward.toString());

            // Increase the time for the livenessPeriod
            console.log("Wait for liveness period to pass");
            await helpers.time.increase(livenessPeriod);

            // Call the checkpoint
            console.log("Calling checkpoint by agent or manually");
            await stakingTokenInstance.connect(agent).checkpoint();

            // Check the reward
            serviceInfo = await stakingTokenInstance.mapServiceInfo(serviceId);
            console.log("Reward after checkpoint", serviceInfo.reward.toString());

            // Get multisig address
            const multisig = await ethers.getContractAt("GnosisSafe", serviceInfo.multisig);

            // Get activity module proxy address
            const owners = await multisig.getOwners();
            const activityModuleProxy = await ethers.getContractAt("ActivityModule", owners[0]);

            // Claim rewards
            console.log("Calling claim by agent or manually");
            await activityModuleProxy.claim();
            const multisigBalance = await olas.balanceOf(serviceInfo.multisig);
            console.log("Multisig balance after claim:", multisigBalance.toString());

            // Check collector balance
            const collectorBalance = await olas.balanceOf(collector.address);
            console.log("Collector balance:", collectorBalance.toString());

            // Relay rewards to L1
            console.log("Calling relay tokens to L1 by agent or manually");
            await collector.relayRewardTokens();

            console.log("\nL1");

            // Update st total assets
            console.log("Calling OLAS total assets on stOLAS update by agent or manually");
            await st.updateTotalAssets();

            stTotalAssets = await st.totalAssets();
            console.log("OLAS total assets on stOLAS now:", stTotalAssets.toString());

            console.log("User approves stOLAS for treasury:", stBalance.toString());
            await st.approve(treasury.address, stBalance);

            // Divide reward by 10 to definitely cover OLAS that is physically on stOLAS contract
            let stAmount = collectorBalance.div(10);
            // Request withdraw
            console.log("User requests withdraw of small amount of stOLAS:", stAmount.toString());
            let tx = await treasury.requestToWithdraw(stAmount, [gnosisChainId], [[stakingTokenInstance.address]],
                [bridgePayload], [0]);
            let res = await tx.wait();
            // Get withdraw request Id
            //console.log(res.logs);
            let requestId = ethers.BigNumber.from(res.logs[6].topics[3]);
            let data6909 = ethers.utils.defaultAbiCoder.decode(["uint256", "uint256"], res.logs[6].data);
            let olasWithdrawAmount = ethers.BigNumber.from(data6909[1]);
            console.log("Withdraw requestId:", requestId.toString());
            console.log("User is minted ERC6909 tokens corresponding to number of OLAS:", olasWithdrawAmount.toString());

            // Finalize withdraw
            console.log("User to finalize withdraw request after withdraw cool down period");
            console.log("Approve 6909 requestId tokens for treasury");
            await treasury.approve(treasury.address, requestId, await treasury.balanceOf(deployer.address, requestId));

            console.log("Finalize withdraw");
            let balanceBefore = await olas.balanceOf(deployer.address);
            await treasury.finalizeWithdrawRequests([requestId], [olasWithdrawAmount]);
            let balanceAfter = await olas.balanceOf(deployer.address);
            let balanceDiff = balanceAfter.sub(balanceBefore);
            expect(balanceDiff).to.equal(olasWithdrawAmount);
            console.log("User got OLAS:", olasWithdrawAmount.toString());

            console.log("\nL1 - L2 - L1");

            // Request withdraw of all the remaining stOLAS
            stBalance = await st.balanceOf(deployer.address);
            console.log("User requests withdraw of all remaining stOLAS:", stBalance.toString());
            tx = await treasury.requestToWithdraw(stBalance, [gnosisChainId], [[stakingTokenInstance.address]],
                [bridgePayload], [0]);
            res = await tx.wait();
            // Get withdraw request Id
            //console.log(res.logs);
            requestId = ethers.BigNumber.from(res.logs[6].topics[3]);
            data6909 = ethers.utils.defaultAbiCoder.decode(["uint256", "uint256"], res.logs[6].data);
            olasWithdrawAmount = ethers.BigNumber.from(data6909[1]);
            console.log("Withdraw requestId:", requestId.toString());
            console.log("User is minted ERC6909 tokens corresponding to number of OLAS:", olasWithdrawAmount.toString());
            console.log("OLAS is not enough on L1, sending request to L2 to unstake and transfer back to L1");

            console.log("\nL1");

            // Finalize withdraw
            console.log("User to finalize withdraw request after withdraw cool down period");

            console.log("Finalize withdraw");
            balanceBefore = await olas.balanceOf(deployer.address);
            await treasury.finalizeWithdrawRequests([requestId], [olasWithdrawAmount]);
            balanceAfter = await olas.balanceOf(deployer.address);
            balanceDiff = balanceAfter.sub(balanceBefore);
            expect(balanceDiff).to.equal(olasWithdrawAmount);
            console.log("User got OLAS:", olasWithdrawAmount.toString());

            stBalance = await st.balanceOf(deployer.address);
            console.log("Final user stOLAS remainder:", stBalance.toString());

            stBalance = await st.totalAssets();
            console.log("Final OLAS total assets on stOLAS:", stBalance.toString());

            // Restore a previous state of blockchain
            snapshot.restore();
        });

        it("More than one service deposit", async function () {
            // Take a snapshot of the current state of the blockchain
            const snapshot = await helpers.takeSnapshot();

            console.log("L1");

            // Get OLAS amount to stake - want to cover 2 staked services: 2 * 2 * minStakingDeposit
            const olasAmount = minStakingDeposit.mul(5);

            // Approve OLAS for depository
            console.log("User approves OLAS for depository:", olasAmount.toString());
            await olas.approve(depository.address, olasAmount);

            // Stake OLAS on L1
            console.log("User deposits OLAS for stOLAS");
            await depository.deposit(olasAmount, [gnosisChainId], [[stakingTokenInstance.address]], [bridgePayload], [0]);
            let stBalance = await st.balanceOf(deployer.address);
            console.log("User stOLAS balance now:", stBalance.toString());
            let stTotalAssets = await st.totalAssets();
            console.log("OLAS total assets on stOLAS:", stTotalAssets.toString());

            let veBalance = await ve.getVotes(lock.address);
            console.log("Protocol current veOLAS balance:", veBalance.toString());

            console.log("\nL2");

            console.log("OLAS rewards available on L2 staking contract:", (await stakingTokenInstance.availableRewards()).toString());

            // Check the reward
            let serviceInfo = await stakingTokenInstance.mapServiceInfo(serviceId);
            console.log("Reward before checkpoint", serviceInfo.reward.toString());

            // Increase the time for the livenessPeriod
            console.log("Wait for liveness period to pass");
            await helpers.time.increase(livenessPeriod);

            // Call the checkpoint
            console.log("Calling checkpoint by agent or manually");
            await stakingTokenInstance.connect(agent).checkpoint();

            const stakedServiceIds = await stakingManager.getStakedServiceIds(stakingTokenInstance.address);
            console.log("Number of staked services: ", stakedServiceIds.length);

            // Check rewards
            for (let i = 0; i < stakedServiceIds.length; ++i) {
                serviceInfo = await stakingTokenInstance.mapServiceInfo(stakedServiceIds[i]);
                console.log(`Reward after checkpoint ${stakedServiceIds[i]}:`, serviceInfo.reward.toString());
            }

            for (let i = 0; i < stakedServiceIds.length; ++i) {
                serviceInfo = await stakingTokenInstance.mapServiceInfo(stakedServiceIds[i]);
                // Get multisig addresses
                const multisig = await ethers.getContractAt("GnosisSafe", serviceInfo.multisig);

                // Get activity module proxy address
                const owners = await multisig.getOwners();
                const activityModuleProxy = await ethers.getContractAt("ActivityModule", owners[0]);

                // Claim rewards
                console.log("Calling claim by agent or manually");
                await activityModuleProxy.claim();
                const multisigBalance = await olas.balanceOf(serviceInfo.multisig);
                console.log("Multisig balance after claim:", multisigBalance.toString());
            }

            // Check collector balance
            const collectorBalance = await olas.balanceOf(collector.address);
            console.log("Collector balance:", collectorBalance.toString());

            // Relay rewards to L1
            console.log("Calling relay tokens to L1 by agent or manually");
            await collector.relayRewardTokens();

            console.log("\nL1");

            // Update st total assets
            console.log("Calling OLAS total assets on stOLAS update by agent or manually");
            await st.updateTotalAssets();

            stTotalAssets = await st.totalAssets();
            console.log("OLAS total assets on stOLAS now:", stTotalAssets.toString());

            console.log("User approves stOLAS for treasury:", stBalance.toString());
            await st.approve(treasury.address, stBalance);

            // Divide stOLAS by 2 in order to have unstake executed
            let stAmount = stBalance.div(2);
            // Request withdraw
            console.log("User requests withdraw of half of stOLAS:", stAmount.toString());
            let tx = await treasury.requestToWithdraw(stAmount, [gnosisChainId], [[stakingTokenInstance.address]],
                [bridgePayload], [0]);
            let res = await tx.wait();
            // Get withdraw request Id
            //console.log(res.logs);
            let requestId = ethers.BigNumber.from(res.logs[6].topics[3]);
            let data6909 = ethers.utils.defaultAbiCoder.decode(["uint256", "uint256"], res.logs[6].data);
            let olasWithdrawAmount = ethers.BigNumber.from(data6909[1]);
            console.log("Withdraw requestId:", requestId.toString());
            console.log("User is minted ERC6909 tokens corresponding to number of OLAS:", olasWithdrawAmount.toString());

            // Finalize withdraw
            console.log("User to finalize withdraw request after withdraw cool down period");
            console.log("Approve 6909 requestId tokens for treasury");
            await treasury.approve(treasury.address, requestId, await treasury.balanceOf(deployer.address, requestId));

            console.log("Finalize withdraw");
            let balanceBefore = await olas.balanceOf(deployer.address);
            await treasury.finalizeWithdrawRequests([requestId], [olasWithdrawAmount]);
            let balanceAfter = await olas.balanceOf(deployer.address);
            let balanceDiff = balanceAfter.sub(balanceBefore);
            expect(balanceDiff).to.equal(olasWithdrawAmount);
            console.log("User got OLAS:", olasWithdrawAmount.toString());

            console.log("\nL1 - L2 - L1");

            // Request withdraw of all the remaining stOLAS
            stBalance = await st.balanceOf(deployer.address);
            console.log("User requests withdraw of all remaining stOLAS:", stBalance.toString());
            tx = await treasury.requestToWithdraw(stBalance, [gnosisChainId], [[stakingTokenInstance.address]],
                [bridgePayload], [0]);
            res = await tx.wait();
            // Get withdraw request Id
            //console.log(res.logs);
            requestId = ethers.BigNumber.from(res.logs[6].topics[3]);
            data6909 = ethers.utils.defaultAbiCoder.decode(["uint256", "uint256"], res.logs[6].data);
            olasWithdrawAmount = ethers.BigNumber.from(data6909[1]);
            console.log("Withdraw requestId:", requestId.toString());
            console.log("User is minted ERC6909 tokens corresponding to number of OLAS:", olasWithdrawAmount.toString());
            console.log("OLAS is not enough on L1, sending request to L2 to unstake and transfer back to L1");

            console.log("\nL1");

            // Finalize withdraw
            console.log("User to finalize withdraw request after withdraw cool down period");

            console.log("Finalize withdraw");
            balanceBefore = await olas.balanceOf(deployer.address);
            await treasury.finalizeWithdrawRequests([requestId], [olasWithdrawAmount]);
            balanceAfter = await olas.balanceOf(deployer.address);
            balanceDiff = balanceAfter.sub(balanceBefore);
            expect(balanceDiff).to.equal(olasWithdrawAmount);
            console.log("User got OLAS:", olasWithdrawAmount.toString());

            stBalance = await st.balanceOf(deployer.address);
            console.log("Final user stOLAS remainder:", stBalance.toString());

            stBalance = await st.totalAssets();
            console.log("Final OLAS total assets on stOLAS:", stBalance.toString());

            // Restore a previous state of blockchain
            snapshot.restore();
        });

        it.only("Two services deposit, one unstake, more deposit, full unstake", async function () {
            // Take a snapshot of the current state of the blockchain
            const snapshot = await helpers.takeSnapshot();

            console.log("L1");

            // Get OLAS amount to stake - want to cover 2 staked services: 2 * 2 * minStakingDeposit
            let olasAmount = minStakingDeposit.mul(5);

            // Approve OLAS for depository
            console.log("User approves OLAS for depository:", olasAmount.toString());
            await olas.approve(depository.address, olasAmount);

            // Stake OLAS on L1
            console.log("User deposits OLAS for stOLAS");
            await depository.deposit(olasAmount, [gnosisChainId], [[stakingTokenInstance.address]], [bridgePayload], [0]);
            let stBalance = await st.balanceOf(deployer.address);
            console.log("User stOLAS balance now:", stBalance.toString());
            let stTotalAssets = await st.totalAssets();
            console.log("OLAS total assets on stOLAS:", stTotalAssets.toString());

            let veBalance = await ve.getVotes(lock.address);
            console.log("Protocol current veOLAS balance:", veBalance.toString());

            console.log("\nL2");

            console.log("OLAS rewards available on L2 staking contract:", (await stakingTokenInstance.availableRewards()).toString());

            // Check the reward
            let serviceInfo = await stakingTokenInstance.mapServiceInfo(serviceId);
            console.log("Reward before checkpoint", serviceInfo.reward.toString());

            // Increase the time for the livenessPeriod
            console.log("Wait for liveness period to pass");
            await helpers.time.increase(livenessPeriod);

            // Call the checkpoint
            console.log("Calling checkpoint by agent or manually");
            await stakingTokenInstance.connect(agent).checkpoint();

            let stakedServiceIds = await stakingManager.getStakedServiceIds(stakingTokenInstance.address);
            console.log("Number of staked services: ", stakedServiceIds.length);

            // Check rewards
            for (let i = 0; i < stakedServiceIds.length; ++i) {
                serviceInfo = await stakingTokenInstance.mapServiceInfo(stakedServiceIds[i]);
                console.log(`Reward after checkpoint ${stakedServiceIds[i]}:`, serviceInfo.reward.toString());
            }

            for (let i = 0; i < stakedServiceIds.length; ++i) {
                serviceInfo = await stakingTokenInstance.mapServiceInfo(stakedServiceIds[i]);
                // Get multisig addresses
                const multisig = await ethers.getContractAt("GnosisSafe", serviceInfo.multisig);

                // Get activity module proxy address
                const owners = await multisig.getOwners();
                const activityModuleProxy = await ethers.getContractAt("ActivityModule", owners[0]);

                // Claim rewards
                console.log("Calling claim by agent or manually");
                await activityModuleProxy.claim();
                const multisigBalance = await olas.balanceOf(serviceInfo.multisig);
                console.log("Multisig balance after claim:", multisigBalance.toString());
            }

            // Check collector balance
            let collectorBalance = await olas.balanceOf(collector.address);
            console.log("Collector balance:", collectorBalance.toString());

            // Relay rewards to L1
            console.log("Calling relay tokens to L1 by agent or manually");
            await collector.relayRewardTokens();

            console.log("\nL1");

            // Update st total assets
            console.log("Calling OLAS total assets on stOLAS update by agent or manually");
            await st.updateTotalAssets();

            stTotalAssets = await st.totalAssets();
            console.log("OLAS total assets on stOLAS now:", stTotalAssets.toString());

            console.log("User approves stOLAS for treasury:", stBalance.toString());
            await st.approve(treasury.address, stBalance);

            // Divide stOLAS by 2 in order to have unstake executed
            let stAmount = stBalance.div(2);
            // Request withdraw
            console.log("User requests withdraw of half of stOLAS:", stAmount.toString());
            let tx = await treasury.requestToWithdraw(stAmount, [gnosisChainId], [[stakingTokenInstance.address]],
                [bridgePayload], [0]);
            let res = await tx.wait();
            // Get withdraw request Id
            //console.log(res.logs);
            let requestId = ethers.BigNumber.from(res.logs[6].topics[3]);
            let data6909 = ethers.utils.defaultAbiCoder.decode(["uint256", "uint256"], res.logs[6].data);
            let olasWithdrawAmount = ethers.BigNumber.from(data6909[1]);
            console.log("Withdraw requestId:", requestId.toString());
            console.log("User is minted ERC6909 tokens corresponding to number of OLAS:", olasWithdrawAmount.toString());

            // Finalize withdraw
            console.log("User to finalize withdraw request after withdraw cool down period");
            const requestBalance = await treasury.balanceOf(deployer.address, requestId);
            console.log("Approve 6909 requestId tokens for treasury:", requestBalance.toString());
            await treasury.approve(treasury.address, requestId, requestBalance);

            console.log("Finalize withdraw");
            let balanceBefore = await olas.balanceOf(deployer.address);
            await treasury.finalizeWithdrawRequests([requestId], [olasWithdrawAmount]);
            let balanceAfter = await olas.balanceOf(deployer.address);
            let balanceDiff = balanceAfter.sub(balanceBefore);
            expect(balanceDiff).to.equal(olasWithdrawAmount);
            console.log("User got OLAS:", olasWithdrawAmount.toString());

            console.log("stakedBalance:", await st.stakedBalance());
            console.log("vaultBalance:", await st.vaultBalance());
            console.log("reserveBalance:", await st.reserveBalance());

            console.log("\nL1 - continue");

            // Stake more OLAS on L1
            // Get OLAS amount to stake - want to cover 1 more staked services: 1 * 2 * minStakingDeposit
            olasAmount = minStakingDeposit.mul(7);
            // Approve OLAS for depository
            console.log("User approves OLAS for depository:", olasAmount.toString());
            await olas.approve(depository.address, olasAmount);

            console.log("User deposits OLAS for stOLAS");
            await depository.deposit(olasAmount, [gnosisChainId], [[stakingTokenInstance.address]], [bridgePayload], [0]);
            stBalance = await st.balanceOf(deployer.address);
            console.log("User stOLAS balance now:", stBalance.toString());
            stTotalAssets = await st.totalAssets();
            console.log("OLAS total assets on stOLAS:", stTotalAssets.toString());

            veBalance = await ve.getVotes(lock.address);
            console.log("Protocol current veOLAS balance:", veBalance.toString());

            console.log("stakedBalance:", await st.stakedBalance());
            console.log("vaultBalance:", await st.vaultBalance());
            console.log("reserveBalance:", await st.reserveBalance());

            console.log("\nL2");

            console.log("OLAS rewards available on L2 staking contract:", (await stakingTokenInstance.availableRewards()).toString());

            // Check the reward
            serviceInfo = await stakingTokenInstance.mapServiceInfo(serviceId);
            console.log("Reward before checkpoint", serviceInfo.reward.toString());

            // Increase the time for the livenessPeriod
            console.log("Wait for liveness period to pass");
            await helpers.time.increase(livenessPeriod);

            // Call the checkpoint
            console.log("Calling checkpoint by agent or manually");
            await stakingTokenInstance.connect(agent).checkpoint();

            stakedServiceIds = await stakingManager.getStakedServiceIds(stakingTokenInstance.address);
            console.log("Number of staked services: ", stakedServiceIds.length);

            // Check rewards
            for (let i = 0; i < stakedServiceIds.length; ++i) {
                serviceInfo = await stakingTokenInstance.mapServiceInfo(stakedServiceIds[i]);
                console.log(`Reward after checkpoint ${stakedServiceIds[i]}:`, serviceInfo.reward.toString());
            }

            for (let i = 0; i < stakedServiceIds.length; ++i) {
                serviceInfo = await stakingTokenInstance.mapServiceInfo(stakedServiceIds[i]);
                // Get multisig addresses
                const multisig = await ethers.getContractAt("GnosisSafe", serviceInfo.multisig);
                console.log("Multisig address", multisig.address);

                // Get activity module proxy address
                const owners = await multisig.getOwners();
                const activityModuleProxy = await ethers.getContractAt("ActivityModule", owners[0]);

                // Claim rewards
                console.log("Calling claim by agent or manually");
                await activityModuleProxy.claim();
                const multisigBalance = await olas.balanceOf(serviceInfo.multisig);
                console.log("Multisig balance after claim:", multisigBalance.toString());
            }

            // Check collector balance
            collectorBalance = await olas.balanceOf(collector.address);
            console.log("Collector balance:", collectorBalance.toString());

            // Relay rewards to L1
            console.log("Calling relay tokens to L1 by agent or manually");
            await collector.relayRewardTokens();

            console.log("\nL1");

            // Update st total assets
            console.log("Calling OLAS total assets on stOLAS update by agent or manually");
            await st.updateTotalAssets();

            stTotalAssets = await st.totalAssets();
            console.log("OLAS total assets on stOLAS now:", stTotalAssets.toString());

            console.log("User approves stOLAS for treasury:", stBalance.toString());
            await st.approve(treasury.address, stBalance);

            console.log("\nL1 - L2 - L1");

            console.log("stOLAS amounts:");
            console.log("stakedBalance:", await st.stakedBalance());
            console.log("vaultBalance:", await st.vaultBalance());
            console.log("reserveBalance:", await st.reserveBalance());

            // Request withdraw of all the remaining stOLAS
            stBalance = await st.balanceOf(deployer.address);
            console.log("User requests withdraw of all remaining stOLAS:", stBalance.toString());
            tx = await treasury.requestToWithdraw(stBalance, [gnosisChainId], [[stakingTokenInstance.address]],
                [bridgePayload], [0]);
            res = await tx.wait();
            // Get withdraw request Id
            //console.log(res.logs);
            requestId = ethers.BigNumber.from(res.logs[6].topics[3]);
            data6909 = ethers.utils.defaultAbiCoder.decode(["uint256", "uint256"], res.logs[6].data);
            olasWithdrawAmount = ethers.BigNumber.from(data6909[1]);
            console.log("Withdraw requestId:", requestId.toString());
            console.log("User is minted ERC6909 tokens corresponding to number of OLAS:", olasWithdrawAmount.toString());
            console.log("OLAS is not enough on L1, sending request to L2 to unstake and transfer back to L1");

            console.log("\nL1");

            // Finalize withdraw
            console.log("User to finalize withdraw request after withdraw cool down period");

            console.log("Finalize withdraw");
            balanceBefore = await olas.balanceOf(deployer.address);
            await treasury.finalizeWithdrawRequests([requestId], [olasWithdrawAmount]);
            balanceAfter = await olas.balanceOf(deployer.address);
            balanceDiff = balanceAfter.sub(balanceBefore);
            expect(balanceDiff).to.equal(olasWithdrawAmount);
            console.log("User got OLAS:", olasWithdrawAmount.toString());

            stBalance = await st.balanceOf(deployer.address);
            console.log("Final user stOLAS remainder:", stBalance.toString());

            stBalance = await st.totalAssets();
            console.log("Final OLAS total assets on stOLAS:", stBalance.toString());

            // Restore a previous state of blockchain
            snapshot.restore();
        });
    });
});
