/*global hre, process*/
const { expect } = require("chai");
const { ethers } = require("hardhat");
const fs = require("fs");

const main = async () => {
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
    const deployer = new ethers.Wallet(account, provider);
    console.log("Deployer address:", deployer.address);

    const gnosisStakingProcessorL2 = await ethers.getContractAt("GnosisStakingProcessorL2",
        parsedData.gnosisStakingProcessorL2Address);

    const target = "0x3e8A4d23b14739f862Bc62f334d013846d2147d5";
    const amount = "20000000000000000000000";
    const batchHash = "0x4bdd10e9ee54db8be5c3151e5de0d75ec68fe05509845468461d77afd502f2d3";
    const operation = "0x1bcc0f4c3fad314e585165815f94ecca9b96690a26d6417d7876448a9a867a69";
    await gnosisStakingProcessorL2.redeem(target, amount, batchHash, operation);
};

main()
    .then(() => process.exit(0))
    .catch(error => {
        console.error(error);
        process.exit(1);
    });
