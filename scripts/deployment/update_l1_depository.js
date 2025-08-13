/*global hre, process*/
const { expect } = require("chai");
const { ethers } = require("hardhat");
const fs = require("fs");

const main = async () => {
    let depository;
    let deployer;

    const globalsFile = "scripts/deployment/globals_eth_sepolia.json";
    const dataFromJSON = fs.readFileSync(globalsFile, "utf8");
    let parsedData = JSON.parse(dataFromJSON);

    // Setting up providers and wallets
    const ALCHEMY_API_KEY_SEPOLIA = process.env.ALCHEMY_API_KEY_SEPOLIA;
    const networkURL = parsedData.networkURL + ALCHEMY_API_KEY_SEPOLIA;
    const provider = new ethers.providers.JsonRpcProvider(networkURL);
    await provider.getBlockNumber().then((result) => {
        console.log("Current block number sepolia: " + result);
    });

    // Get the EOA
    const account = ethers.utils.HDNode.fromMnemonic(process.env.TESTNET_MNEMONIC).derivePath("m/44'/60'/0'/0/0");
    deployer = new ethers.Wallet(account, provider);
    console.log("Deployer address:", deployer.address);


    // Deploy new depository implementation
    const Depository = await ethers.getContractFactory("Depository");
    depository = await Depository.deploy(parsedData.olasAddress, parsedData.stOLASAddress);
    await depository.deployed();

    // Wait for half a minute for the transaction completion
    await new Promise(r => setTimeout(r, 30000));

    await hre.run("verify:verify", {
        address: depository.address,
        constructorArguments: [parsedData.olasAddress, parsedData.stOLASAddress],
    });
    parsedData.depositoryAddress = depository.address;
    fs.writeFileSync(globalsFile, JSON.stringify(parsedData));

    // Change depository implementation
    const depositoryProxy = await ethers.getContractAt("Depository", parsedData.depositoryProxyAddress);
    await depositoryProxy.changeImplementation(parsedData.depositoryAddress);
};

main()
    .then(() => process.exit(0))
    .catch(error => {
        console.error(error);
        process.exit(1);
    });
