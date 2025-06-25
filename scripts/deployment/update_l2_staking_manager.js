/*global hre, process*/
const { expect } = require("chai");
const { ethers } = require("hardhat");
const fs = require("fs");

const main = async () => {
    const agentId = 1;
    const defaultHash = "0x" + "5".repeat(64);
    let stakingManager;
    let deployer;

    //const globalsFile = "scripts/deployment/globals_gnosis_chiado.json";
    const globalsFile = "scripts/deployment/globals_base_sepolia.json";
    const dataFromJSON = fs.readFileSync(globalsFile, "utf8");
    let parsedData = JSON.parse(dataFromJSON);

    // Setting up providers and wallets
    const networkURL = parsedData.networkURL;
    const provider = new ethers.providers.JsonRpcProvider(networkURL);
    await provider.getBlockNumber().then((result) => {
        console.log("Network:", parsedData.networkURL);
        console.log("Current block number: ", result);
    });

    // Get the EOA
    const account = ethers.utils.HDNode.fromMnemonic(process.env.TESTNET_MNEMONIC).derivePath("m/44'/60'/0'/0/0");
    deployer = new ethers.Wallet(account, provider);
    console.log("Deployer address:", deployer.address);


    // Deploy new staking manager implementation
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
    fs.writeFileSync(globalsFile, JSON.stringify(parsedData));

    // Change stakingManager implementation
    const stakingManagerProxy = await ethers.getContractAt("StakingManager", parsedData.stakingManagerProxyAddress);
    await stakingManagerProxy.changeImplementation(parsedData.stakingManagerAddress);
};

main()
    .then(() => process.exit(0))
    .catch(error => {
        console.error(error);
        process.exit(1);
    });
