/*global hre, process*/
const { expect } = require("chai");
const { ethers } = require("hardhat");
const fs = require("fs");

const main = async () => {
    const globalsFile = "scripts/deployment/globals_gnosis_chiado.json";
    //const globalsFile = "scripts/deployment/globals_base_sepolia.json";
    const dataFromJSON = fs.readFileSync(globalsFile, "utf8");
    let parsedData = JSON.parse(dataFromJSON);

    // Setting up providers and wallets
    const networkURL = parsedData.networkURL;
    const provider = new ethers.providers.JsonRpcProvider(networkURL);
    await provider.getBlockNumber().then((result) => {
        console.log("Current block number: " + result);
    });

    // Get the EOA
    const account = ethers.utils.HDNode.fromMnemonic(process.env.TESTNET_MNEMONIC).derivePath("m/44'/60'/0'/0/0");
    const deployer = new ethers.Wallet(account, provider);
    console.log("Deployer address:", deployer.address);

    const stakingManager = await ethers.getContractAt("StakingManager", parsedData.stakingManagerProxyAddress);
    const stakingTokenInstance = await ethers.getContractAt("StakingTokenLocked", parsedData.stakingProxyAddress);

    // Checkpoint
    await stakingTokenInstance.checkpoint();

    // Claim rewards
    const stakedServiceIds = await stakingManager.getStakedServiceIds(parsedData.stakingProxyAddress);
    for (let i = 0; i < stakedServiceIds.length; i++) {
        const serviceInfo = await stakingTokenInstance.mapServiceInfo(stakedServiceIds[i]);
        // Get multisig addresses
        const multisig = await ethers.getContractAt("GnosisSafe", serviceInfo.multisig);

        // Get activity module proxy address
        const owners = await multisig.getOwners();
        const activityModuleProxy = await ethers.getContractAt("ActivityModule", owners[0]);
        const tx = await activityModuleProxy.drain({ gasLimit: 2000000 });
        await tx.wait();
    }
};

main()
    .then(() => process.exit(0))
    .catch(error => {
        console.error(error);
        process.exit(1);
    });
