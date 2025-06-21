/*global hre, process*/
const { expect } = require("chai");
const { ethers } = require("hardhat");
const fs = require("fs");

const main = async () => {
    let olas;
    let activityChecker;
    let stakingFactory;
    let stakingVerifier;
    let collector;
    let beacon;
    let activityModule;
    let stakingManager;
    let stakingTokenImplementation;
    let stakingTokenInstance;
    let gnosisStakingProcessorL2;
    let deployer;
    const AddressZero = ethers.constants.AddressZero;
    const HashZero = ethers.constants.HashZero;
    const oneDay = 86400;
    const defaultHash = "0x" + "5".repeat(64);
    const regDeposit = ethers.utils.parseEther("10000");
    const agentId = 1;
    const livenessPeriod = oneDay; // 24 hours
    const livenessRatio = "1"; // 1 transaction per 25 hours
    const maxNumServices = 20;
    const minStakingDeposit = regDeposit;
    const timeForEmissions = oneDay * 30;
    let serviceParams = {
        maxNumServices,
        rewardsPerSecond: "951293759512937",
        minStakingDeposit,
        livenessPeriod,
        timeForEmissions,
        serviceRegistry: AddressZero,
        serviceRegistryTokenUtility: AddressZero,
        stakingToken: AddressZero,
        stakingManager: AddressZero,
        activityChecker: AddressZero
    };
    const gnosisChainId = 100;
    const fullStakeDeposit = regDeposit.mul(2);
    const stakingSupply = fullStakeDeposit.mul(ethers.BigNumber.from(maxNumServices));

    const globalsFile = "scripts/deployment/globals_gnosis_chiado.json";
    const dataFromJSON = fs.readFileSync(globalsFile, "utf8");
    let parsedData = JSON.parse(dataFromJSON);

    // Setting up providers and wallets
    const networkURL = parsedData.networkURL;
    const provider = new ethers.providers.JsonRpcProvider(networkURL);
    await provider.getBlockNumber().then((result) => {
        console.log("Current block number chiado: " + result);
    });

    // Get the EOA
    const account = ethers.utils.HDNode.fromMnemonic(process.env.TESTNET_MNEMONIC).derivePath("m/44'/60'/0'/0/0");
    deployer = new ethers.Wallet(account, provider);
    console.log("Deployer address:", deployer.address);

    // Deploy Collector
    console.log("Deploying Collector");
    const Collector = await ethers.getContractFactory("Collector");
    collector = await Collector.deploy(parsedData.olasAddress, parsedData.distributorAddress);
    await collector.deployed();

    // Wait for half a minute for the transaction completion
    await new Promise(r => setTimeout(r, 30000));

    await hre.run("verify:verify", {
        address: collector.address,
        constructorArguments: [parsedData.olasAddress, parsedData.distributorAddress],
    });
    parsedData.collectorAddress = collector.address;
    console.log("Collector address:", collector.address);
    fs.writeFileSync(globalsFile, JSON.stringify(parsedData));

    // Deploy Collector Proxy
    console.log("Deploying Collector Proxy");
    const CollectorProxy = await ethers.getContractFactory("Proxy");
    let initPayload = collector.interface.encodeFunctionData("initialize", []);
    const collectorProxy = await CollectorProxy.deploy(parsedData.collectorAddress, initPayload);
    await collectorProxy.deployed();

    // Wait for half a minute for the transaction completion
    await new Promise(r => setTimeout(r, 30000));

    await hre.run("verify:verify", {
        address: collectorProxy.address,
        constructorArguments: [collector.address, initPayload],
    });
    parsedData.collectorProxyAddress = collectorProxy.address;
    console.log("Collector Proxy address:", collectorProxy.address);
    fs.writeFileSync(globalsFile, JSON.stringify(parsedData));
    collector = await ethers.getContractAt("Collector", parsedData.collectorProxyAddress);

    // Deploy ActivityModule
    console.log("Deploying ActivityModule");
    const ActivityModule = await ethers.getContractFactory("ActivityModule");
    activityModule = await ActivityModule.deploy(parsedData.olasAddress, parsedData.collectorProxyAddress);
    await activityModule.deployed();

    // Wait for half a minute for the transaction completion
    await new Promise(r => setTimeout(r, 30000));

    await hre.run("verify:verify", {
        address: activityModule.address,
        constructorArguments: [parsedData.olasAddress, parsedData.collectorProxyAddress],
    });
    parsedData.activityModuleAddress = activityModule.address;  
    console.log("ActivityModule address:", activityModule.address);
    fs.writeFileSync(globalsFile, JSON.stringify(parsedData));

    // Deploy Beacon
    console.log("Deploying Beacon");
    const Beacon = await ethers.getContractFactory("Beacon");
    beacon = await Beacon.deploy(parsedData.activityModuleAddress);
    await beacon.deployed();

    // Wait for half a minute for the transaction completion
    await new Promise(r => setTimeout(r, 30000));

    await hre.run("verify:verify", {
        address: beacon.address,
        constructorArguments: [parsedData.activityModuleAddress],
    });
    parsedData.beaconAddress = beacon.address;
    console.log("Beacon address:", beacon.address);
    fs.writeFileSync(globalsFile, JSON.stringify(parsedData));

    // Deploy StakingManager
    console.log("Deploying StakingManager");
    const StakingManager = await ethers.getContractFactory("StakingManager");
    stakingManager = await StakingManager.deploy(parsedData.olasAddress, parsedData.treasuryProxyAddress,
        parsedData.serviceManagerTokenAddress, parsedData.stakingFactoryAddress, parsedData.safeToL2SetupAddress,
        parsedData.gnosisSafeL2Address, parsedData.beaconAddress, parsedData.collectorProxyAddress, agentId, defaultHash);
    await stakingManager.deployed();

    // Wait for half a minute for the transaction completion
    await new Promise(r => setTimeout(r, 30000));

    await hre.run("verify:verify", {
        address: stakingManager.address,
        constructorArguments: [parsedData.olasAddress, parsedData.treasuryProxyAddress, parsedData.serviceManagerTokenAddress,
            parsedData.stakingFactoryAddress, parsedData.safeToL2SetupAddress, parsedData.gnosisSafeL2Address,
            parsedData.beaconAddress, parsedData.collectorProxyAddress, agentId, defaultHash],
    });
    parsedData.stakingManagerAddress = stakingManager.address;
    console.log("StakingManager address:", stakingManager.address);
    fs.writeFileSync(globalsFile, JSON.stringify(parsedData));

    // Initialize stakingManager
    console.log("Initializing stakingManagerProxy");
    const StakingManagerProxy = await ethers.getContractFactory("Proxy");
    initPayload = stakingManager.interface.encodeFunctionData("initialize", [parsedData.gnosisSafeMultisigImplementationAddress,
        parsedData.gnosisSafeSameAddressMultisigImplementationAddress, parsedData.fallbackHandlerAddress]);
    const stakingManagerProxy = await StakingManagerProxy.deploy(parsedData.stakingManagerAddress, initPayload);
    await stakingManagerProxy.deployed();

    // Wait for half a minute for the transaction completion
    await new Promise(r => setTimeout(r, 30000));

    await hre.run("verify:verify", {
        address: stakingManagerProxy.address,
        constructorArguments: [parsedData.stakingManagerAddress, initPayload],
    });
    parsedData.stakingManagerProxyAddress = stakingManagerProxy.address;
    console.log("StakingManagerProxy address:", stakingManagerProxy.address);
    fs.writeFileSync(globalsFile, JSON.stringify(parsedData));
    stakingManager = await ethers.getContractAt("StakingManager", parsedData.stakingManagerProxyAddress);


    // Fund staking manager with native to support staking creation
    console.log("Fund staking manager with native to support staking creation");
    let tx = await deployer.sendTransaction({to: stakingManager.address, value: ethers.utils.parseEther("0.000001")});
    await tx.wait();

    // Deploy GnosisStakingProcessorL2
    console.log("Deploying GnosisStakingProcessorL2");
    const GnosisStakingProcessorL2 = await ethers.getContractFactory("GnosisStakingProcessorL2");
    gnosisStakingProcessorL2 = await GnosisStakingProcessorL2.deploy(parsedData.olasAddress,
        parsedData.stakingManagerProxyAddress, parsedData.gnosisOmniBridgeAddress, parsedData.gnosisAMBHomeAddress,
        parsedData.gnosisDepositProcessorL1Address, gnosisChainId);
    await gnosisStakingProcessorL2.deployed();

    // Wait for half a minute for the transaction completion
    await new Promise(r => setTimeout(r, 30000));

    await hre.run("verify:verify", {
        address: gnosisStakingProcessorL2.address,
        constructorArguments: [parsedData.olasAddress, parsedData.stakingManagerProxyAddress,
            parsedData.gnosisOmniBridgeAddress, parsedData.gnosisAMBHomeAddress,
            parsedData.gnosisDepositProcessorL1Address, gnosisChainId],
    });
    parsedData.gnosisStakingProcessorL2Address = gnosisStakingProcessorL2.address;
    console.log("GnosisStakingProcessorL2 address:", gnosisStakingProcessorL2.address);
    fs.writeFileSync(globalsFile, JSON.stringify(parsedData));


    // changeStakingProcessorL2 for collector
    collector = await ethers.getContractAt("Collector", parsedData.collectorProxyAddress);
    await collector.changeStakingProcessorL2(parsedData.gnosisStakingProcessorL2Address);

    // changeStakingProcessorL2 for stakingManager
    stakingManager = await ethers.getContractAt("StakingManager", parsedData.stakingManagerProxyAddress);
    await stakingManager.changeStakingProcessorL2(parsedData.gnosisStakingProcessorL2Address);

    // Deploy ActivityChecker
    console.log("Deploying ActivityChecker");
    const ActivityChecker = await ethers.getContractFactory("ModuleActivityChecker");
    activityChecker = await ActivityChecker.deploy(livenessRatio);
    await activityChecker.deployed();

    // Wait for half a minute for the transaction completion
    await new Promise(r => setTimeout(r, 30000));

    await hre.run("verify:verify", {
        address: activityChecker.address,
        constructorArguments: [livenessRatio],
    });
    parsedData.activityCheckerAddress = activityChecker.address;
    console.log("ActivityChecker address:", activityChecker.address);
    fs.writeFileSync(globalsFile, JSON.stringify(parsedData));

    // Deploy StakingTokenLocked
    console.log("Deploying StakingTokenLocked");
    const StakingTokenLocked = await ethers.getContractFactory("StakingTokenLocked");
    stakingTokenImplementation = await StakingTokenLocked.deploy();
    await stakingTokenImplementation.deployed();

    // Wait for half a minute for the transaction completion
    await new Promise(r => setTimeout(r, 30000));

    await hre.run("verify:verify", {
        address: stakingTokenImplementation.address,
        constructorArguments: [],
    });
    parsedData.stakingTokenImplementationAddress = stakingTokenImplementation.address;
    console.log("StakingTokenLocked address:", stakingTokenImplementation.address);
    fs.writeFileSync(globalsFile, JSON.stringify(parsedData));


    // Whitelist implementation
    stakingVerifier = await ethers.getContractAt("StakingVerifier", parsedData.stakingVerifierAddress);
    await stakingVerifier.setImplementationsStatuses([parsedData.stakingTokenImplementationAddress], [true], true);

    serviceParams.serviceRegistry = parsedData.serviceRegistryAddress,
    serviceParams.serviceRegistryTokenUtility = parsedData.serviceRegistryTokenUtilityAddress,
    serviceParams.stakingToken = parsedData.olasAddress;
    serviceParams.activityChecker = parsedData.activityCheckerAddress;
    serviceParams.stakingManager = parsedData.stakingManagerProxyAddress;

    // Create staking contract instance
    stakingFactory = await ethers.getContractAt("StakingFactory", parsedData.stakingFactoryAddress);
    //stakingTokenImplementation = await ethers.getContractAt("StakingTokenLocked", parsedData.stakingTokenImplementationAddress);
    initPayload = stakingTokenImplementation.interface.encodeFunctionData("initialize", [serviceParams]);
    tx = await stakingFactory.createStakingInstance(parsedData.stakingTokenImplementationAddress, initPayload,
        {gasLimit: 5000000});
    const res = await tx.wait();
    // Get staking contract instance address from the event
    parsedData.stakingTokenAddress = "0x" + res.logs[0].topics[2].slice(26);
    console.log("StakingToken address:", parsedData.stakingTokenAddress);
    fs.writeFileSync(globalsFile, JSON.stringify(parsedData));

    // Wait for half a minute for the transaction completion
    await new Promise(r => setTimeout(r, 30000));

    await hre.run("verify:verify", {
        address: parsedData.stakingTokenAddress,
        constructorArguments: [parsedData.stakingTokenImplementationAddress],
    });

    // Fund the staking contract
    olas = await ethers.getContractAt("ERC20Token", parsedData.olasAddress);
    const amount = regDeposit.mul(10);
    await olas.approve(parsedData.stakingTokenAddress, amount);
    stakingTokenInstance = await ethers.getContractAt("StakingTokenLocked", parsedData.stakingTokenAddress);
    await stakingTokenInstance.deposit(amount, { gasLimit: 300000 });
};

main()
    .then(() => process.exit(0))
    .catch(error => {
        console.error(error);
        process.exit(1);
    });
