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
    let ve;
    let st;
    let gnosisSafe;
    let gnosisSafeL2;
    let gnosisSafeProxyFactory;
    let safeModuleInitializer;
    let fallbackHandler;
    let multiSend;
    let gnosisSafeMultisig;
    let gnosisSafeSameAddressMultisig;
    let activityChecker;
    let stakingFactory;
    let stakingVerifier;
    let lock;
    let distributor;
    let unstakeRelayer;
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
    const fullStakeDeposit = regDeposit.mul(2);
    const timeForEmissions = 30 * oneDay;
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
    const protocolFactor = 0;
    const chainId = 31337;
    const gnosisChainId = 100;
    const stakingRewardsPerEpoch = ethers.BigNumber.from(serviceParams.rewardsPerSecond).mul(ethers.BigNumber.from(maxNumServices)).mul(timeForEmissions);
    const stakingSupply = fullStakeDeposit.mul(ethers.BigNumber.from(maxNumServices));
    const bridgePayload = "0x";
    const rewardOperation = "0x0b9821ae606ebc7c79bf3390bdd3dc93e1b4a7cda27aad60646e7b88ff55b001";
    const unstakeOperation = "0x8ca9a95e41b5eece253c93f5b31eed1253aed6b145d8a6e14d913fdf8e732293";
    const unstakeRetiredOperation = "0x9065ad15d9673159e4597c86084aff8052550cec93c5a6e44b3f1dba4c8731b3";

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

        const MultiSend = await ethers.getContractFactory("MultiSendCallOnly");
        multiSend = await MultiSend.deploy();
        await multiSend.deployed();

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

        // Transfer initial lock
        await olas.transfer(lock.address, ethers.utils.parseEther("1"));
        // Set governor and create first lock
        // Governor address is irrelevant for testing
        await lock.setGovernorAndCreateFirstLock(deployer.address);

        const Distributor = await ethers.getContractFactory("Distributor");
        distributor = await Distributor.deploy(olas.address, st.address, lock.address);
        await distributor.deployed();

        const DistributorProxy = await ethers.getContractFactory("Proxy");
        initPayload = distributor.interface.encodeFunctionData("initialize", [lockFactor]);
        const distributorProxy = await DistributorProxy.deploy(distributor.address, initPayload);
        await distributorProxy.deployed();
        distributor = await ethers.getContractAt("Distributor", distributorProxy.address);

        const UnstakeRelayer = await ethers.getContractFactory("UnstakeRelayer");
        unstakeRelayer = await UnstakeRelayer.deploy(olas.address, st.address);
        await unstakeRelayer.deployed();

        const UnstakeRelayerProxy = await ethers.getContractFactory("Proxy");
        initPayload = unstakeRelayer.interface.encodeFunctionData("initialize", []);
        const unstakeRelayerProxy = await UnstakeRelayerProxy.deploy(unstakeRelayer.address, initPayload);
        await unstakeRelayerProxy.deployed();
        unstakeRelayer = await ethers.getContractAt("UnstakeRelayer", unstakeRelayerProxy.address);

        const Depository = await ethers.getContractFactory("Depository");
        depository = await Depository.deploy(olas.address, st.address);
        await depository.deployed();

        const DepositoryProxy = await ethers.getContractFactory("Proxy");
        initPayload = depository.interface.encodeFunctionData("initialize", []);
        const depositoryProxy = await DepositoryProxy.deploy(depository.address, initPayload);
        await depositoryProxy.deployed();
        depository = await ethers.getContractAt("Depository", depositoryProxy.address);

        // Change product type to Final
        await depository.changeProductType(2);

        const Treasury = await ethers.getContractFactory("Treasury");
        treasury = await Treasury.deploy(olas.address, st.address, depository.address);
        await treasury.deployed();

        const TreasuryProxy = await ethers.getContractFactory("Proxy");
        initPayload = treasury.interface.encodeFunctionData("initialize", [0]);
        const treasuryProxy = await TreasuryProxy.deploy(treasury.address, initPayload);
        await treasuryProxy.deployed();
        treasury = await ethers.getContractAt("Treasury", treasuryProxy.address);

        // Change managers for stOLAS
        // Only Treasury contract can mint OLAS
        await st.initialize(treasury.address, depository.address, distributor.address, unstakeRelayer.address);

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
        collector = await Collector.deploy(olas.address);
        await collector.deployed();

        const CollectorProxy = await ethers.getContractFactory("Proxy");
        initPayload = collector.interface.encodeFunctionData("initialize", []);
        const collectorProxy = await CollectorProxy.deploy(collector.address, initPayload);
        await collectorProxy.deployed();
        collector = await ethers.getContractAt("Collector", collectorProxy.address);

        const ActivityModule = await ethers.getContractFactory("ActivityModule");
        activityModule = await ActivityModule.deploy(olas.address, collector.address, multiSend.address);
        await activityModule.deployed();

        const Beacon = await ethers.getContractFactory("Beacon");
        beacon = await Beacon.deploy(activityModule.address);
        await beacon.deployed();

        const StakingManager = await ethers.getContractFactory("StakingManager");
        stakingManager = await StakingManager.deploy(olas.address, serviceManager.address, stakingFactory.address,
            safeModuleInitializer.address, gnosisSafeL2.address, beacon.address, collector.address, agentId, defaultHash);
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
            bridgeRelayer.address, bridgeRelayer.address);
        await gnosisDepositProcessorL1.deployed();

        const GnosisStakingProcessorL2 = await ethers.getContractFactory("GnosisStakingProcessorL2");
        gnosisStakingProcessorL2 = await GnosisStakingProcessorL2.deploy(olas.address, stakingManager.address,
            bridgeRelayer.address, bridgeRelayer.address, gnosisDepositProcessorL1.address, chainId);
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
        await depository.createAndActivateStakingModels([gnosisChainId], [stakingTokenAddress], [fullStakeDeposit],
            [maxNumServices]);

        // Set
        await collector.setOperationReceivers([rewardOperation, unstakeOperation, unstakeRetiredOperation],
            [distributor.address, treasury.address, unstakeRelayer.address]);
    });

    context("Staking", function () {
        it("E2E liquid staking simple", async function () {
            // Max timeout 1600 sec for coverage
            this.timeout(1600000);

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
            let previewAmount = await st.previewDeposit(olasAmount);
            await depository.deposit(olasAmount, [gnosisChainId], [stakingTokenInstance.address], [bridgePayload], [0]);
            let stBalance = await st.balanceOf(deployer.address);
            expect(stBalance).to.equal(previewAmount);
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
            //const multisigBalance = await olas.balanceOf(serviceInfo.multisig);
            //console.log("Multisig balance after claim:", multisigBalance.toString());

            // Check collector balance
            const collectorBalance = await olas.balanceOf(collector.address);
            console.log("Collector balance:", collectorBalance.toString());

            // Relay rewards to L1
            console.log("Calling relay rewards tokens to L1 by agent or manually");
            await collector.relayTokens(rewardOperation, bridgePayload);

            console.log("\nL1");

            // Distribute OLAS to veOLAS and stOLAS
            console.log("Calling distribute obtained L2 to L1 OLAS to veOLAS and stOLAS by agent or manually");
            await distributor.distribute();

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
            previewAmount = await st.previewRedeem(stAmount);
            let tx = await treasury.requestToWithdraw(stAmount, [gnosisChainId], [stakingTokenInstance.address],
                [bridgePayload], [0]);
            let res = await tx.wait();
            // Get withdraw request Id
            //console.log(res.logs);
            let requestId = ethers.BigNumber.from(res.logs[5].topics[3]);
            let data6909 = ethers.utils.defaultAbiCoder.decode(["uint256", "uint256"], res.logs[5].data);
            let olasWithdrawAmount = ethers.BigNumber.from(data6909[1]);
            expect(olasWithdrawAmount).to.equal(previewAmount);
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
            previewAmount = await st.previewRedeem(stBalance);
            tx = await treasury.requestToWithdraw(stBalance, [gnosisChainId], [stakingTokenInstance.address],
                [bridgePayload], [0]);
            res = await tx.wait();
            // Get withdraw request Id
            //console.log(res.logs);
            requestId = ethers.BigNumber.from(res.logs[5].topics[3]);
            data6909 = ethers.utils.defaultAbiCoder.decode(["uint256", "uint256"], res.logs[5].data);
            olasWithdrawAmount = ethers.BigNumber.from(data6909[1]);
            expect(olasWithdrawAmount).to.equal(previewAmount);
            console.log("Withdraw requestId:", requestId.toString());
            console.log("User is minted ERC6909 tokens corresponding to number of OLAS:", olasWithdrawAmount.toString());
            console.log("OLAS is not enough on L1, sending request to L2 to unstake and transfer back to L1");

            // Relay unstaked tokens to L1
            console.log("Calling relay usntaked tokens to L1 by agent or manually");
            await collector.relayTokens(unstakeOperation, bridgePayload);

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
            // Max timeout 1600 sec for coverage
            this.timeout(1600000);

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
            let previewAmount = await st.previewDeposit(olasAmount);
            await depository.deposit(olasAmount, [gnosisChainId], [stakingTokenInstance.address], [bridgePayload], [0]);
            let stBalance = await st.balanceOf(deployer.address);
            expect(stBalance).to.equal(previewAmount);
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
                //console.log(`Reward after checkpoint ${stakedServiceIds[i]}:`, serviceInfo.reward.toString());
            }

            for (let i = 0; i < stakedServiceIds.length; ++i) {
                serviceInfo = await stakingTokenInstance.mapServiceInfo(stakedServiceIds[i]);
                // Get multisig addresses
                const multisig = await ethers.getContractAt("GnosisSafe", serviceInfo.multisig);

                // Get activity module proxy address
                const owners = await multisig.getOwners();
                const activityModuleProxy = await ethers.getContractAt("ActivityModule", owners[0]);

                // Claim rewards
                //console.log("Calling claim by agent or manually");
                await activityModuleProxy.claim();
                //const multisigBalance = await olas.balanceOf(serviceInfo.multisig);
                //console.log("Multisig balance after claim:", multisigBalance.toString());
            }

            // Check collector balance
            const collectorBalance = await olas.balanceOf(collector.address);
            console.log("Collector balance:", collectorBalance.toString());

            // Relay rewards to L1
            console.log("Calling relay rewards tokens to L1 by agent or manually");
            await collector.relayTokens(rewardOperation, bridgePayload);

            console.log("\nL1");

            // Distribute OLAS to veOLAS and stOLAS
            console.log("Calling distribute obtained L2 to L1 OLAS to veOLAS and stOLAS by agent or manually");
            await distributor.distribute();

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
            previewAmount = await st.previewRedeem(stAmount);
            let tx = await treasury.requestToWithdraw(stAmount, [gnosisChainId], [stakingTokenInstance.address],
                [bridgePayload], [0]);
            let res = await tx.wait();
            // Get withdraw request Id
            //console.log(res.logs);
            let requestId = ethers.BigNumber.from(res.logs[5].topics[3]);
            let data6909 = ethers.utils.defaultAbiCoder.decode(["uint256", "uint256"], res.logs[5].data);
            let olasWithdrawAmount = ethers.BigNumber.from(data6909[1]);
            expect(olasWithdrawAmount).to.equal(previewAmount);
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
            previewAmount = await st.previewRedeem(stBalance);
            tx = await treasury.requestToWithdraw(stBalance, [gnosisChainId], [stakingTokenInstance.address],
                [bridgePayload], [0]);
            res = await tx.wait();
            // Get withdraw request Id
            //console.log(res.logs);
            requestId = ethers.BigNumber.from(res.logs[5].topics[3]);
            data6909 = ethers.utils.defaultAbiCoder.decode(["uint256", "uint256"], res.logs[5].data);
            olasWithdrawAmount = ethers.BigNumber.from(data6909[1]);
            expect(olasWithdrawAmount).to.equal(previewAmount);
            console.log("Withdraw requestId:", requestId.toString());
            console.log("User is minted ERC6909 tokens corresponding to number of OLAS:", olasWithdrawAmount.toString());
            console.log("OLAS is not enough on L1, sending request to L2 to unstake and transfer back to L1");

            // Deliver unstaked tokens from L2 to L1
            await collector.relayTokens(unstakeOperation, bridgePayload);

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

        it("Two services deposit, one unstake, more deposit, full unstake", async function () {
            // Max timeout 1600 sec for coverage
            this.timeout(1600000);

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
            let previewAmount = await st.previewDeposit(olasAmount);
            await depository.deposit(olasAmount, [gnosisChainId], [stakingTokenInstance.address], [bridgePayload], [0]);
            let stBalance = await st.balanceOf(deployer.address);
            expect(stBalance).to.equal(previewAmount);
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

            for (let i = 0; i < stakedServiceIds.length; ++i) {
                serviceInfo = await stakingTokenInstance.mapServiceInfo(stakedServiceIds[i]);
                // Get multisig addresses
                const multisig = await ethers.getContractAt("GnosisSafe", serviceInfo.multisig);

                // Get activity module proxy address
                const owners = await multisig.getOwners();
                const activityModuleProxy = await ethers.getContractAt("ActivityModule", owners[0]);

                // Claim rewards
                //console.log("Calling claim by agent or manually");
                await activityModuleProxy.claim();
                //const multisigBalance = await olas.balanceOf(serviceInfo.multisig);
                //console.log("Multisig balance after claim:", multisigBalance.toString());
            }

            // Check collector balance
            let collectorBalance = await olas.balanceOf(collector.address);
            console.log("Collector balance:", collectorBalance.toString());

            // Relay rewards to L1
            console.log("Calling relay rewards tokens to L1 by agent or manually");
            await collector.relayTokens(rewardOperation, bridgePayload);

            console.log("\nL1");

            // Distribute OLAS to veOLAS and stOLAS
            console.log("Calling distribute obtained L2 to L1 OLAS to veOLAS and stOLAS by agent or manually");
            await distributor.distribute();

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
            previewAmount = await st.previewRedeem(stAmount);
            let tx = await treasury.requestToWithdraw(stAmount, [gnosisChainId], [stakingTokenInstance.address],
                [bridgePayload], [0]);
            let res = await tx.wait();
            // Get withdraw request Id
            //console.log(res.logs);
            let requestId = ethers.BigNumber.from(res.logs[5].topics[3]);
            let data6909 = ethers.utils.defaultAbiCoder.decode(["uint256", "uint256"], res.logs[5].data);
            let olasWithdrawAmount = ethers.BigNumber.from(data6909[1]);
            expect(olasWithdrawAmount).to.equal(previewAmount);
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
            // Get OLAS amount to stake - want to cover 3 more staked services: 3 * 2 * minStakingDeposit
            olasAmount = minStakingDeposit.mul(7);
            // Approve OLAS for depository
            console.log("User approves OLAS for depository:", olasAmount.toString());
            await olas.approve(depository.address, olasAmount);

            console.log("User deposits OLAS for stOLAS");
            // Note that previewDeposit and actual deposit() from Depository might not be exact
            // as balances could change in the deposit() function depending on the number of provided staking contracts
            // and over-funding with unlimited olasAmount parameter
            //previewAmount = await st.previewDeposit(olasAmount);
            //balanceBefore = await st.balanceOf(deployer.address);
            await depository.deposit(olasAmount, [gnosisChainId], [stakingTokenInstance.address], [bridgePayload], [0]);
            //balanceAfter = await st.balanceOf(deployer.address);
            //balanceDiff = balanceAfter.sub(balanceBefore);
            //expect(balanceDiff).to.equal(previewAmount);
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

            for (let i = 0; i < stakedServiceIds.length; ++i) {
                serviceInfo = await stakingTokenInstance.mapServiceInfo(stakedServiceIds[i]);
                // Get multisig addresses
                const multisig = await ethers.getContractAt("GnosisSafe", serviceInfo.multisig);
                //console.log("Multisig address", multisig.address);

                // Get activity module proxy address
                const owners = await multisig.getOwners();
                const activityModuleProxy = await ethers.getContractAt("ActivityModule", owners[0]);

                // Claim rewards
                //console.log("Calling claim by agent or manually");
                await activityModuleProxy.claim();
                //const multisigBalance = await olas.balanceOf(serviceInfo.multisig);
                //console.log("Multisig balance after claim:", multisigBalance.toString());
            }

            // Check collector balance
            collectorBalance = await olas.balanceOf(collector.address);
            console.log("Collector balance:", collectorBalance.toString());

            // Relay rewards to L1
            console.log("Calling relay rewards tokens to L1 by agent or manually");
            await collector.relayTokens(rewardOperation, bridgePayload);

            console.log("\nL1");

            // Distribute OLAS to veOLAS and stOLAS
            console.log("Calling distribute obtained L2 to L1 OLAS to veOLAS and stOLAS by agent or manually");
            await distributor.distribute();

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
            // There must be no more than 5 unstakes
            const numUnstakes = 5;
            let chainIds = new Array(numUnstakes).fill(gnosisChainId);
            let stakingInstances = new Array(numUnstakes).fill(stakingTokenInstance.address);
            let bridgePayloads = new Array(numUnstakes).fill(bridgePayload);
            let values = new Array(numUnstakes).fill(0);
            previewAmount = await st.previewRedeem(stBalance);
            tx = await treasury.requestToWithdraw(stBalance, chainIds, stakingInstances,bridgePayloads, values);
            res = await tx.wait();
            // Get withdraw request Id
            //console.log(res.logs);
            requestId = ethers.BigNumber.from(res.logs[5].topics[3]);
            data6909 = ethers.utils.defaultAbiCoder.decode(["uint256", "uint256"], res.logs[5].data);
            olasWithdrawAmount = ethers.BigNumber.from(data6909[1]);
            expect(olasWithdrawAmount).to.equal(previewAmount);
            console.log("Withdraw requestId:", requestId.toString());
            console.log("User is minted ERC6909 tokens corresponding to number of OLAS:", olasWithdrawAmount.toString());
            console.log("OLAS is not enough on L1, sending request to L2 to unstake and transfer back to L1");

            // Relay unstaked tokens to L1
            console.log("Calling relay unstaked tokens to L1 by agent or manually");
            await collector.relayTokens(unstakeOperation, bridgePayload);

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

        it("Max number of stakes", async function () {
            // Max timeout 1600 sec for coverage
            this.timeout(1600000);

            // Take a snapshot of the current state of the blockchain
            const snapshot = await helpers.takeSnapshot();

            console.log("L1");

            // Get OLAS amount to stake - want to cover 19 and 20 full staked services: 2 * 20 * minStakingDeposit - veOLAS lock
            //let olasAmount = minStakingDeposit.mul(40);
            let olasAmount = (minStakingDeposit.mul(3)).sub(1);

            const numStakes = 18;
            const amountToStake = olasAmount.mul(numStakes);

            // Stake OLAS on L1
            console.log("User deposits OLAS for stOLAS");
            let numIters = 10;
            let chainIds = new Array(numStakes).fill(gnosisChainId);
            let stakingInstances = new Array(numStakes).fill(stakingTokenInstance.address);
            let bridgePayloads = new Array(numStakes).fill(bridgePayload);
            let values = new Array(numStakes).fill(0);
            for (let i = 0; i < numIters; i++) {
                await olas.approve(depository.address, amountToStake);
                await depository.deposit(amountToStake, chainIds, stakingInstances, bridgePayloads, values);
            }

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

            // Check rewards and claim
            for (let i = 0; i < stakedServiceIds.length; ++i) {
                serviceInfo = await stakingTokenInstance.mapServiceInfo(stakedServiceIds[i]);
                // Get multisig addresses
                const multisig = await ethers.getContractAt("GnosisSafe", serviceInfo.multisig);

                // Get activity module proxy address
                const owners = await multisig.getOwners();
                const activityModuleProxy = await ethers.getContractAt("ActivityModule", owners[0]);

                // Claim rewards
                //console.log("Calling claim by agent or manually");
                await activityModuleProxy.claim();
                //const multisigBalance = await olas.balanceOf(serviceInfo.multisig);
                //console.log("Multisig balance after claim:", multisigBalance.toString());
            }

            // Check collector balance
            let collectorBalance = await olas.balanceOf(collector.address);
            console.log("Collector balance:", collectorBalance.toString());

            // Relay rewards to L1
            console.log("Calling relay rewards tokens to L1 by agent or manually");
            await collector.relayTokens(rewardOperation, bridgePayload);

            console.log("\nL1");

            // Distribute OLAS to veOLAS and stOLAS
            console.log("Calling distribute obtained L2 to L1 OLAS to veOLAS and stOLAS by agent or manually");
            await distributor.distribute();

            // Update st total assets
            console.log("Calling OLAS total assets on stOLAS update by agent or manually");
            await st.updateTotalAssets();

            let stakedBalanceAfter = await st.stakedBalance();
            let vaultBalanceAfter = await st.vaultBalance();
            let reserveBalanceAfter = await st.reserveBalance();

            console.log("stakedBalance:", stakedBalanceAfter.toString());
            console.log("vaultBalance:", vaultBalanceAfter.toString());
            console.log("reserveBalance:", reserveBalanceAfter.toString());
            let totalComputedAssets = stakedBalanceAfter.add(vaultBalanceAfter).add(reserveBalanceAfter);

            stTotalAssets = await st.totalAssets();
            console.log("OLAS total assets on stOLAS now:", stTotalAssets.toString());
            expect(stTotalAssets).to.equal(totalComputedAssets);

            console.log("User approves stOLAS for treasury:", stBalance.toString());
            await st.approve(treasury.address, stBalance);

            // Full stOLAS withdraw
            // Request withdraw
            console.log("User requests full withdraw of stOLAS:", stBalance.toString());
            numIters = 10;
            const stAmount = stBalance.div(numIters);
            const numUnstakes = 30;
            chainIds = new Array(numUnstakes).fill(gnosisChainId);
            stakingInstances = new Array(numUnstakes).fill(stakingTokenInstance.address);
            bridgePayloads = new Array(numUnstakes).fill(bridgePayload);
            values = new Array(numUnstakes).fill(0);
            let totalOLASBalance = ethers.BigNumber.from(0);
            for (let i = 0; i < numIters; i++) {
                console.log("Iteration:", i);
                const previewAmount = await st.previewRedeem(stAmount);
                console.log("previewAmount:", previewAmount.toString());
                let tx = await treasury.requestToWithdraw(stAmount, chainIds, stakingInstances, bridgePayloads, values);
                let res = await tx.wait();
                // Get withdraw request Id
                //console.log(res.logs);
                let requestId = ethers.BigNumber.from(res.logs[5].topics[3]);
                let data6909 = ethers.utils.defaultAbiCoder.decode(["uint256", "uint256"], res.logs[5].data);
                let olasWithdrawAmount = ethers.BigNumber.from(data6909[1]);
                expect(olasWithdrawAmount).to.equal(previewAmount);
                console.log("Withdraw requestId:", requestId.toString());
                console.log("User is minted ERC6909 tokens corresponding to number of OLAS:", olasWithdrawAmount.toString());

                // Relay unstaked tokens to L1
                const receiverBalance = await collector.mapOperationReceiverBalances(unstakeOperation);
                const minOlasBalance = await collector.MIN_OLAS_BALANCE();
                if (receiverBalance.balance.gte(minOlasBalance)) {
                    console.log("Calling relay unstaked tokens to L1 by agent or manually");
                    await collector.relayTokens(unstakeOperation, bridgePayload);
                }

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

                totalOLASBalance = totalOLASBalance.add(balanceDiff);
                console.log("User total OLAS balance after withdraw:", totalOLASBalance.toString());

                stakedBalanceAfter = await st.stakedBalance();
                vaultBalanceAfter = await st.vaultBalance();
                reserveBalanceAfter = await st.reserveBalance();

                console.log("stakedBalance:", stakedBalanceAfter.toString());
                console.log("vaultBalance:", vaultBalanceAfter.toString());
                console.log("reserveBalance:", reserveBalanceAfter.toString());
                totalComputedAssets = stakedBalanceAfter.add(vaultBalanceAfter).add(reserveBalanceAfter);

                stTotalAssets = await st.totalAssets();
                console.log("OLAS total assets on stOLAS now:", stTotalAssets.toString());
                expect(stTotalAssets).to.equal(totalComputedAssets);
            }

            console.log("stakedBalance:", await st.stakedBalance());
            console.log("vaultBalance:", await st.vaultBalance());
            console.log("reserveBalance:", await st.reserveBalance());

            stBalance = await st.balanceOf(deployer.address);
            console.log("Final user stOLAS remainder:", stBalance.toString());

            stBalance = await st.totalAssets();
            console.log("Final OLAS total assets on stOLAS:", stBalance.toString());

            // Restore a previous state of blockchain
            snapshot.restore();
        });

        it("Multiple stakes-unstakes", async function () {
            // Max timeout 1600 sec for coverage
            this.timeout(1600000);

            // Take a snapshot of the current state of the blockchain
            const snapshot = await helpers.takeSnapshot();

            console.log("L1");

            // Get initial OLAS amount to stake
            let olasAmount = (minStakingDeposit.mul(5)).div(4);

            let numIters = 40;
            const numStakes = 18;
            let chainIds = new Array(numStakes).fill(gnosisChainId);
            let stakingInstances = new Array(numStakes).fill(stakingTokenInstance.address);
            let bridgePayloads = new Array(numStakes).fill(bridgePayload);
            let values = new Array(numStakes).fill(0);
            for (let i = 0; i < numIters; i++) {
                console.log("\n\n STAKE-UNSTAKE ITERATION:", i);

                // Increase every iteration by a factor of 4 - first one is to cover 2 staked services: 2 * 2 * minStakingDeposit
                olasAmount = olasAmount.add(1);
                const amountToStake = olasAmount.mul(numStakes);

                // Approve OLAS for depository
                console.log("User approves OLAS for depository:", amountToStake.toString());
                await olas.approve(depository.address, amountToStake);

                // Stake OLAS on L1
                console.log("User deposits OLAS for stOLAS");
                let previewAmount = await st.previewDeposit(amountToStake);
                let stTotalAssetsBefore = await st.totalAssets();
                let stBalanceBefore = await st.balanceOf(deployer.address);
                await depository.deposit(amountToStake, chainIds, stakingInstances, bridgePayloads, values);
                console.log("stakedBalanceL1", await st.stakedBalance());
                let stTotalAssetsAfter = await st.totalAssets();
                let stTotalAssetsAfterDiff = stTotalAssetsAfter.sub(stTotalAssetsBefore);
                // Check deposited OLAS accounts in totalAssets
                expect(stTotalAssetsAfterDiff).to.equal(amountToStake);
                let stBalanceAfter = await st.balanceOf(deployer.address);
                let stBalanceDiff = stBalanceAfter.sub(stBalanceBefore);
                // Check calculated stOLAS is equal to stOLAS additionally minted amount
                expect(stBalanceDiff).to.equal(previewAmount);

                // Estimate redeem if deployer were to redeem the obtained amount of stOLAS right away
                previewAmount = await st.previewRedeem(stBalanceDiff);
                // Preview amount could be just slightly different due to rounding error
                let delta = amountToStake.sub(previewAmount);
                expect(Number(delta)).to.lessThan(10);

                let stBalance = await st.balanceOf(deployer.address);
                console.log("User stOLAS balance now:", stBalance.toString());
                console.log("OLAS total assets on stOLAS:", stTotalAssetsAfter.toString());

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
                console.log("Number of staked services in StakingManager:", stakedServiceIds.length);
                let numStakedServices = await stakingTokenInstance.getNumServiceIds();
                expect(numStakedServices).to.equal(stakedServiceIds.length);

                // Check sync of staked balances on both chains
                let stakedBalanceL1 = await st.stakedBalance();
                let stakedBalanceL2 = minStakingDeposit.mul(2).mul(stakedServiceIds.length);
                let stakeBalanceRemainder = await stakingManager.mapStakingProxyBalances(stakingTokenInstance.address);
                stakedBalanceL2 = stakedBalanceL2.add(stakeBalanceRemainder);
                expect(stakedBalanceL1).to.equal(stakedBalanceL2);

                // Check rewards and claim
                for (let i = 0; i < stakedServiceIds.length; ++i) {
                    serviceInfo = await stakingTokenInstance.mapServiceInfo(stakedServiceIds[i]);
                    // Get multisig addresses
                    const multisig = await ethers.getContractAt("GnosisSafe", serviceInfo.multisig);

                    // Get activity module proxy address
                    const owners = await multisig.getOwners();
                    const activityModuleProxy = await ethers.getContractAt("ActivityModule", owners[0]);

                    // Claim rewards
                    //console.log("Calling claim by agent or manually");
                    await activityModuleProxy.claim();
                    //const multisigBalance = await olas.balanceOf(serviceInfo.multisig);
                    //console.log("Multisig balance after claim:", multisigBalance.toString());
                }

                // Check collector balance
                let collectorBalance = await olas.balanceOf(collector.address);
                console.log("Collector balance:", collectorBalance.toString());

                // Relay rewards to L1
                console.log("Calling relay rewards tokens to L1 by agent or manually");
                await collector.relayTokens(rewardOperation, bridgePayload);

                console.log("\nL1");
                const distributorBalance = await olas.balanceOf(distributor.address);
                console.log("Distributor balance now:", distributorBalance.toString());
                // Distribute OLAS to veOLAS and stOLAS
                console.log("Calling distribute obtained L2 to L1 OLAS to veOLAS and stOLAS by agent or manually");
                await distributor.distribute();

                // Update st total assets
                console.log("Calling OLAS total assets on stOLAS update by agent or manually");
                await st.updateTotalAssets();

                console.log("stakedBalance after distribute:", await st.stakedBalance());
                console.log("vaultBalance after distribute:", await st.vaultBalance());
                console.log("reserveBalance after distribute:", await st.reserveBalance());

                let stTotalAssets = await st.totalAssets();
                console.log("OLAS total assets on stOLAS now:", stTotalAssets.toString());

                console.log("User approves stOLAS for treasury:", stBalance.toString());
                await st.approve(treasury.address, stBalance);

                // Unstake minStakingDeposit * i as stOLAS amount will always be smaller than OLAS amount
                let stAmount = stBalance.div(10);
                const numUnstakes = 25;
                chainIds = new Array(numUnstakes).fill(gnosisChainId);
                stakingInstances = new Array(numUnstakes).fill(stakingTokenInstance.address);
                bridgePayloads = new Array(numUnstakes).fill(bridgePayload);
                values = new Array(numUnstakes).fill(0);
                // Request withdraw
                console.log("User requests withdraw of half of stOLAS:", stAmount.toString());
                previewAmount = await st.previewRedeem(stAmount);
                let tx = await treasury.requestToWithdraw(stAmount, chainIds, stakingInstances, bridgePayloads, values);
                let res = await tx.wait();
                // Get withdraw request Id
                //console.log(res.logs);
                let requestId = ethers.BigNumber.from(res.logs[5].topics[3]);
                let data6909 = ethers.utils.defaultAbiCoder.decode(["uint256", "uint256"], res.logs[5].data);
                let olasWithdrawAmount = ethers.BigNumber.from(data6909[1]);
                expect(olasWithdrawAmount).to.equal(previewAmount);
                console.log("Withdraw requestId:", requestId.toString());
                console.log("User is minted ERC6909 tokens corresponding to number of OLAS:", olasWithdrawAmount.toString());

                // Relay unstaked tokens to L1
                const receiverBalance = await collector.mapOperationReceiverBalances(unstakeOperation);
                const minOlasBalance = await collector.MIN_OLAS_BALANCE();
                if (receiverBalance.balance.gte(minOlasBalance)) {
                    console.log("Calling relay unstaked tokens to L1 by agent or manually");
                    await collector.relayTokens(unstakeOperation, bridgePayload);
                }

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
            }

            let stBalance = await st.balanceOf(deployer.address);
            console.log("Full stake user stOLAS remainder:", stBalance.toString());

            let stBalanceAssets = await st.totalAssets();
            console.log("Full stake OLAS total assets on stOLAS:", stBalanceAssets.toString());

            // Unstake all in numIters iterations or less
            let stAmount = stBalance.div(numIters);

            for (let i = 0; i < numIters; i++) {
                console.log("\n\n FULL UNSTAKE ITERATION:", i);
                const numUnstakes = 25;
                const chainIds = new Array(numUnstakes).fill(gnosisChainId);
                const stakingInstances = new Array(numUnstakes).fill(stakingTokenInstance.address);
                const bridgePayloads = new Array(numUnstakes).fill(bridgePayload);
                const values = new Array(numUnstakes).fill(0);
                // Request withdraw
                console.log("User requests partial withdraw of stOLAS:", stAmount.toString());
                const previewAmount = await st.previewRedeem(stAmount);
                let tx = await treasury.requestToWithdraw(stAmount, chainIds, stakingInstances, bridgePayloads, values);
                let res = await tx.wait();
                // Get withdraw request Id
                //console.log(res.logs);
                let requestId = ethers.BigNumber.from(res.logs[5].topics[3]);
                let data6909 = ethers.utils.defaultAbiCoder.decode(["uint256", "uint256"], res.logs[5].data);
                let olasWithdrawAmount = ethers.BigNumber.from(data6909[1]);
                expect(olasWithdrawAmount).to.equal(previewAmount);
                console.log("Withdraw requestId:", requestId.toString());
                console.log("User is minted ERC6909 tokens corresponding to number of OLAS:", olasWithdrawAmount.toString());

                // Relay unstaked tokens to L1
                const receiverBalance = await collector.mapOperationReceiverBalances(unstakeOperation);
                const minOlasBalance = await collector.MIN_OLAS_BALANCE();
                if (receiverBalance.balance.gte(minOlasBalance)) {
                    console.log("Calling relay unstaked tokens to L1 by agent or manually");
                    await collector.relayTokens(unstakeOperation, bridgePayload);
                }

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
            }

            stBalance = await st.balanceOf(deployer.address);
            console.log("Final user stOLAS remainder:", stBalance.toString());

            stBalanceAssets = await st.totalAssets();
            console.log("Final OLAS total assets on stOLAS:", stBalanceAssets.toString());

            // Check sync of staked balances on both chains
            let stakedBalanceL1 = await st.stakedBalance();
            let stakedServiceIds = await stakingManager.getStakedServiceIds(stakingTokenInstance.address);
            let stakedBalanceL2 = minStakingDeposit.mul(2).mul(stakedServiceIds.length);
            let stakeBalanceRemainder = await stakingManager.mapStakingProxyBalances(stakingTokenInstance.address);
            stakedBalanceL2 = stakedBalanceL2.add(stakeBalanceRemainder);
            expect(stakedBalanceL1).to.equal(stakedBalanceL2);

            // Restore a previous state of blockchain
            snapshot.restore();
        });

        it("Retire models", async function () {
            // Max timeout 1600 sec for coverage
            this.timeout(1600000);

            // Take a snapshot of the current state of the blockchain
            const snapshot = await helpers.takeSnapshot();

            console.log("L1");

            // Get OLAS amount to stake - want to cover 19 and 20 full staked services: 2 * 20 * minStakingDeposit - veOLAS lock
            //let olasAmount = minStakingDeposit.mul(40);
            let olasAmount = (minStakingDeposit.mul(3)).sub(1);

            const numStakes = 18;
            const amountToStake = olasAmount.mul(numStakes);

            // Stake OLAS on L1
            console.log("User deposits OLAS for stOLAS");
            let numIters = 10;
            let chainIds = new Array(numStakes).fill(gnosisChainId);
            let stakingInstances = new Array(numStakes).fill(stakingTokenInstance.address);
            let bridgePayloads = new Array(numStakes).fill(bridgePayload);
            let values = new Array(numStakes).fill(0);
            for (let i = 0; i < numIters; i++) {
                await olas.approve(depository.address, amountToStake);
                await depository.deposit(amountToStake, chainIds, stakingInstances, bridgePayloads, values);
            }

            let stBalance = await st.balanceOf(deployer.address);
            console.log("User stOLAS balance now:", stBalance.toString());
            let stTotalAssets = await st.totalAssets();
            console.log("OLAS total assets on stOLAS:", stTotalAssets.toString());

            // Try to close a model without setting it to retired
            await expect(
                depository.closeRetiredStakingModels([gnosisChainId], [stakingTokenInstance.address])
            ).to.be.revertedWithCustomError(depository, "WrongStakingModel");

            // Set model as retired
            await depository.setStakingModelStatuses([gnosisChainId], [stakingTokenInstance.address], [0]);

            // Try to close a model with remainder still not equal supply
            await expect(
                depository.closeRetiredStakingModels([gnosisChainId], [stakingTokenInstance.address])
            ).to.be.revertedWithCustomError(depository, "WrongStakingModel");

            const numUnstakes = 25;
            chainIds = new Array(numUnstakes).fill(gnosisChainId);
            stakingInstances = new Array(numUnstakes).fill(stakingTokenInstance.address);
            bridgePayloads = new Array(numUnstakes).fill(bridgePayload);
            values = new Array(numUnstakes).fill(0);
            const stakingModelId = await depository.getStakingModelId(gnosisChainId, stakingTokenInstance.address);
            let stakingModel;
            for (let i = 0; i < numIters; i++) {
                await depository.unstakeRetired(chainIds, stakingInstances, bridgePayloads, values);

                // Check model balances after unstakes and break if unstake is complete
                stakingModel = await depository.mapStakingModels(stakingModelId);
                if (stakingModel.supply == stakingModel.remainder) {
                    break;
                }
            }

            // Close retired model
            await depository.closeRetiredStakingModels([gnosisChainId], [stakingTokenInstance.address]);

            console.log("\nL2");

            // Check collector balance
            let collectorBalance = await olas.balanceOf(collector.address);
            expect(collectorBalance).to.equal(stakingModel.supply);
            console.log("Collector balance:", collectorBalance.toString());

            // Relay rewards to L1
            console.log("Calling relay unstake retired tokens to L1 by agent or manually");
            await collector.relayTokens(unstakeRetiredOperation, bridgePayload);

            console.log("\nL1");

            const stakedBalanceBefore = await st.stakedBalance();
            const vaultBalanceBefore = await st.vaultBalance();
            const reserveBalanceBefore = await st.reserveBalance();

            // Relay OLAS to stOLAS
            console.log("Calling relay unstake retired tokens to stOLAS by agent or manually");
            await unstakeRelayer.relay();

            const stakedBalanceAfter = await st.stakedBalance();
            const vaultBalanceAfter = await st.vaultBalance();
            const reserveBalanceAfter = await st.reserveBalance();

            console.log("stakedBalance before:", stakedBalanceBefore.toString());
            console.log("vaultBalance before:", vaultBalanceBefore.toString());
            console.log("reserveBalance before:", reserveBalanceBefore.toString());

            // Check updated balances
            expect(stakedBalanceAfter).to.equal(stakedBalanceBefore.sub(collectorBalance));
            expect(vaultBalanceAfter).to.equal(vaultBalanceBefore);
            expect(reserveBalanceAfter).to.equal(reserveBalanceBefore.add(collectorBalance));

            console.log("stakedBalance after:", stakedBalanceAfter.toString());
            console.log("vaultBalance after:", vaultBalanceAfter.toString());
            console.log("reserveBalance after:", reserveBalanceAfter.toString());

            stBalance = await st.balanceOf(deployer.address);
            console.log("Final user stOLAS remainder:", stBalance.toString());

            stBalance = await st.totalAssets();
            console.log("Final OLAS total assets on stOLAS:", stBalance.toString());

            // Restore a previous state of blockchain
            snapshot.restore();
        });

        it("Check OLAS vs stOLAS amounts", async function () {
            // Max timeout 1600 sec for coverage
            this.timeout(1600000);

            // Take a snapshot of the current state of the blockchain
            const snapshot = await helpers.takeSnapshot();

            console.log("L1");

            // Get OLAS amount to stake
            const olasAmount = minStakingDeposit.mul(8).div(3);
            console.log("User deposits OLAS amount:", olasAmount.toString());

            // Approve OLAS for depository
            await olas.approve(depository.address, initSupply);

            // Stake OLAS on L1 first deposit
            console.log("User deposits OLAS for stOLAS");
            let previewAmount = await st.previewDeposit(olasAmount);
            console.log("User stOLAS preview balance:", previewAmount.toString());
            let stBalanceBefore = await st.balanceOf(deployer.address);
            // The deposit is made such that reserveBalance becomes > 0 on purpose
            await depository.deposit(olasAmount, [gnosisChainId], [stakingTokenInstance.address], [bridgePayload], [0]);
            let stBalanceAfter = await st.balanceOf(deployer.address);
            let stBalanceDiff = stBalanceAfter.sub(stBalanceBefore);
            console.log("User stOLAS balance now:", stBalanceAfter.toString());
            let stTotalAssets = await st.totalAssets();
            console.log("OLAS total assets on stOLAS:", stTotalAssets.toString());

            let stakedBalanceAfter = await st.stakedBalance();
            let vaultBalanceAfter = await st.vaultBalance();
            let reserveBalanceAfter = await st.reserveBalance();

            console.log("stakedBalance after 1st deposit:", stakedBalanceAfter.toString());
            console.log("vaultBalance after 1st deposit:", vaultBalanceAfter.toString());
            console.log("reserveBalance after 1st deposit:", reserveBalanceAfter.toString());

            expect(stBalanceDiff).to.equal(previewAmount);

            // Estimate full first redeem
            previewAmount = await st.previewRedeem(stBalanceAfter);
            console.log("User OLAS preview balance:", previewAmount.toString());
            expect(olasAmount).to.equal(previewAmount);

            // Stake OLAS on L1 multiple deposits
            const numIters = 100;
            for (let i = 0; i < numIters; i++) {
                //console.log("Iteration:", i);
                previewAmount = await st.previewDeposit(olasAmount);
                //console.log("User stOLAS preview balance:", previewAmount.toString());
                stBalanceBefore = await st.balanceOf(deployer.address);
                await depository.deposit(olasAmount, [gnosisChainId, gnosisChainId],
                    [stakingTokenInstance.address, stakingTokenInstance.address], [bridgePayload, bridgePayload], [0, 0]);
                stBalanceAfter = await st.balanceOf(deployer.address);
                //console.log("stOLAS balance after additional deposit:", stBalanceAfter.toString());
                stBalanceDiff = stBalanceAfter.sub(stBalanceBefore);
                //console.log("User new obtained stOLAS:", stBalanceDiff.toString());
                //console.log("User stOLAS balance now:", stBalanceAfter.toString());
                stTotalAssets = await st.totalAssets();
                //console.log("OLAS total assets on stOLAS:", stTotalAssets.toString());

                stakedBalanceAfter = await st.stakedBalance();
                vaultBalanceAfter = await st.vaultBalance();
                reserveBalanceAfter = await st.reserveBalance();

                //console.log("stakedBalance:", stakedBalanceAfter.toString());
                //console.log("vaultBalance:", vaultBalanceAfter.toString());
                //console.log("reserveBalance:", reserveBalanceAfter.toString());
                let totalComputedAssets = stakedBalanceAfter.add(vaultBalanceAfter).add(reserveBalanceAfter);

                expect(stBalanceDiff).to.equal(previewAmount);

                stTotalAssets = await st.totalAssets();
                //console.log("OLAS total assets on stOLAS now:", stTotalAssets.toString());
                expect(stTotalAssets).to.equal(totalComputedAssets);

                // Estimate full redeem after more deposits
                previewAmount = await st.previewRedeem(stBalanceAfter);
                //console.log("User OLAS preview balance:", previewAmount.toString());
                expect(previewAmount).to.equal(stTotalAssets);
            }

            console.log("stakedBalance after last deposit:", stakedBalanceAfter.toString());
            console.log("vaultBalance after last deposit:", vaultBalanceAfter.toString());
            console.log("reserveBalance after last deposit:", reserveBalanceAfter.toString());
            console.log("OLAS total assets on stOLAS now:", stTotalAssets.toString());
            console.log("User OLAS preview balance:", previewAmount.toString());

            // Restore a previous state of blockchain
            snapshot.restore();
        });
    });
});
