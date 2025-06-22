/*global hre, process*/
const { expect } = require("chai");
const { ethers } = require("hardhat");
const fs = require("fs");

const main = async () => {
    let collector;
    let deployer;

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


    // Deploy new collector implementation
    const Collector = await ethers.getContractFactory("Collector");
    collector = await Collector.deploy(parsedData.olasAddress, parsedData.distributorProxyAddress);
    await collector.deployed();

    // Wait for half a minute for the transaction completion
    await new Promise(r => setTimeout(r, 30000));

    await hre.run("verify:verify", {
        address: collector.address,
        constructorArguments: [parsedData.olasAddress, parsedData.distributorProxyAddress],
    });
    parsedData.collectorAddress = collector.address;
    fs.writeFileSync(globalsFile, JSON.stringify(parsedData));

    // Change collector implementation
    const collectorProxy = await ethers.getContractAt("Collector", parsedData.collectorProxyAddress);
    await collectorProxy.changeImplementation(parsedData.collectorAddress);
};

main()
    .then(() => process.exit(0))
    .catch(error => {
        console.error(error);
        process.exit(1);
    });
