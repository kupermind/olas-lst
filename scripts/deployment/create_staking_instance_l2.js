/*global hre, process*/
const { expect } = require("chai");
const { ethers } = require("hardhat");
const fs = require("fs");

const main = async () => {
    let olas;
    let activityChecker;
    let stakingFactory;
    let stakingTokenImplementation;
    let stakingTokenInstance;
    let deployer;
    const AddressZero = ethers.constants.AddressZero;
    const oneDay = 86400;
    const defaultHash = "0x" + "5".repeat(64);
    const regDeposit = ethers.utils.parseEther("10000");
    const agentId = 1;
    const livenessPeriod = oneDay; // 24 hours
    const livenessRatio = "1"; // minimal possible livenessRatio
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
    const stakingSupply = (regDeposit.mul(2)).mul(ethers.BigNumber.from(maxNumServices));

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

    //    const ActivityChecker = await ethers.getContractFactory("ModuleActivityChecker");
    //    activityChecker = await ActivityChecker.deploy(livenessRatio);
    //    await activityChecker.deployed();
    //
    //    // Wait for half a minute for the transaction completion
    //    await new Promise(r => setTimeout(r, 30000));
    //
    //    parsedData.activityCheckerAddress = activityChecker.address;
    //    fs.writeFileSync(globalsFile, JSON.stringify(parsedData));

    serviceParams.serviceRegistry = parsedData.serviceRegistryAddress,
    serviceParams.serviceRegistryTokenUtility = parsedData.serviceRegistryTokenUtilityAddress,
    serviceParams.stakingToken = parsedData.olasAddress;
    serviceParams.activityChecker = parsedData.activityCheckerAddress;
    serviceParams.stakingManager = parsedData.stakingManagerProxyAddress;

    stakingFactory = await ethers.getContractAt("StakingFactory", parsedData.stakingFactoryAddress);
    stakingTokenImplementation = await ethers.getContractAt("StakingTokenLocked", parsedData.stakingTokenImplementationAddress);
    initPayload = stakingTokenImplementation.interface.encodeFunctionData("initialize", [serviceParams]);
    const tx = await stakingFactory.createStakingInstance(parsedData.stakingTokenImplementationAddress, initPayload,
        {gasLimit: 5000000});
    const res = await tx.wait();
    // Get staking contract instance address from the event
    parsedData.stakingTokenAddress = "0x" + res.logs[0].topics[2].slice(26);
    fs.writeFileSync(globalsFile, JSON.stringify(parsedData));

    // Wait for half a minute for the transaction completion
    await new Promise(r => setTimeout(r, 30000));

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
