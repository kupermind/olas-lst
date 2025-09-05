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
        console.log("Current block number chiado: " + result);
    });

    // Get the EOA
    const account = ethers.utils.HDNode.fromMnemonic(process.env.TESTNET_MNEMONIC).derivePath("m/44'/60'/0'/0/0");
    const deployer = new ethers.Wallet(account, provider);
    console.log("Deployer address:", deployer.address);

    // Reward operation
    const REWARD = "0x0b9821ae606ebc7c79bf3390bdd3dc93e1b4a7cda27aad60646e7b88ff55b001";
    // Unstake operation
    const UNSTAKE = "0x8ca9a95e41b5eece253c93f5b31eed1253aed6b145d8a6e14d913fdf8e732293";
    // Unstake-retired operation
    const UNSTAKE_RETIRED = "0x9065ad15d9673159e4597c86084aff8052550cec93c5a6e44b3f1dba4c8731b3";

    const collector = await ethers.getContractAt("Collector", parsedData.collectorProxyAddress);
    await collector.relayTokens(REWARD, "0x" , { gasLimit: 1000000 });
};

main()
    .then(() => process.exit(0))
    .catch(error => {
        console.error(error);
        process.exit(1);
    });
