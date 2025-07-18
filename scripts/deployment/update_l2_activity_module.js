/*global hre, process*/
const { expect } = require("chai");
const { ethers } = require("hardhat");
const fs = require("fs");

const main = async () => {
    let activityModule;
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


    // Deploy new activity module implementation
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
    fs.writeFileSync(globalsFile, JSON.stringify(parsedData));

    // Change activityModule implementation in beacon
    const beacon = await ethers.getContractAt("Beacon", parsedData.beaconAddress);
    await beacon.changeImplementation(parsedData.activityModuleAddress);
};

main()
    .then(() => process.exit(0))
    .catch(error => {
        console.error(error);
        process.exit(1);
    });
