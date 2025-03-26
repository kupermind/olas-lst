/*global hre, process*/
const { expect } = require("chai");
const { ethers } = require("hardhat");
const fs = require("fs");

const main = async () => {
    let olas;
    let ve;
    let st;
    let lock;
    let depository;
    let treasury;
    let collector;
    let beacon;
    let gnosisDepositProcessorL1;
    let baseDepositProcessorL1;
    let deployer;
    const AddressZero = ethers.constants.AddressZero;
    const HashZero = ethers.constants.HashZero;
    const initSupply = "5" + "0".repeat(26);
    const maxStakingLimit = ethers.utils.parseEther("20000");
    const gnosisChainId = 100;
    const baseChainId = 8453;
    const regDeposit = ethers.utils.parseEther("10000");
    const maxNumServices = 100;
    const stakingSupply = (regDeposit.mul(2)).mul(ethers.BigNumber.from(maxNumServices));

    const globalsFile = "scripts/deployment/globals_ethereum_sepolia.json";
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

    // Mint tokens to the deployer
    olas = await ethers.getContractAt("ERC20Token", parsedData.olasAddress);
    //await olas.mint(deployer.address, initSupply);

    const SToken = await ethers.getContractFactory("stOLAS");
    st = await SToken.deploy(parsedData.olasAddress, {gasLimit: 2000000});
    await st.deployed();

    // Wait for half a minute for the transaction completion
    await new Promise(r => setTimeout(r, 30000));

    await hre.run("verify:verify", {
        address: st.address,
        constructorArguments: [parsedData.olasAddress],
    });
    parsedData.stOLASAddress = st.address;
    fs.writeFileSync(globalsFile, JSON.stringify(parsedData));


    const Lock = await ethers.getContractFactory("Lock");
    lock = await Lock.deploy(parsedData.olasAddress, parsedData.veOLASAddress);
    await lock.deployed();

    // Wait for half a minute for the transaction completion
    await new Promise(r => setTimeout(r, 30000));

    await hre.run("verify:verify", {
        address: lock.address,
        constructorArguments: [parsedData.olasAddress, parsedData.veOLASAddress],
    });
    parsedData.lockAddress = lock.address;
    fs.writeFileSync(globalsFile, JSON.stringify(parsedData));


    const LockProxy = await ethers.getContractFactory("Proxy");
    let initPayload = lock.interface.encodeFunctionData("initialize", []);
    const lockProxy = await LockProxy.deploy(parsedData.lockAddress, initPayload);
    await lockProxy.deployed();

    // Wait for half a minute for the transaction completion
    await new Promise(r => setTimeout(r, 30000));

    await hre.run("verify:verify", {
        address: lockProxy.address,
        constructorArguments: [parsedData.lockAddress, initPayload],
    });
    parsedData.lockProxyAddress = lockProxy.address;
    fs.writeFileSync(globalsFile, JSON.stringify(parsedData));
    lock = await ethers.getContractAt("Lock", parsedData.lockProxyAddress);


    // Transfer initial lock
    await olas.transfer(parsedData.lockProxyAddress, ethers.utils.parseEther("1"));
    // Set governor and create first lock
    await lock.setGovernorAndCreateFirstLock(parsedData.olasGovernorAddress, {gasLimit: 500000});

    const Depository = await ethers.getContractFactory("Depository");
    depository = await Depository.deploy(parsedData.olasAddress, parsedData.stOLASAddress, parsedData.lockProxyAddress);
    await depository.deployed();

    // Wait for half a minute for the transaction completion
    await new Promise(r => setTimeout(r, 30000));

    await hre.run("verify:verify", {
        address: depository.address,
        constructorArguments: [parsedData.olasAddress, parsedData.stOLASAddress, parsedData.lockProxyAddress],
    });
    parsedData.depositoryAddress = depository.address;
    fs.writeFileSync(globalsFile, JSON.stringify(parsedData));


    const DepositoryProxy = await ethers.getContractFactory("Proxy");
    initPayload = depository.interface.encodeFunctionData("initialize", [parsedData.lockFactor, parsedData.maxStakingLimit]);
    const depositoryProxy = await DepositoryProxy.deploy(parsedData.depositoryAddress, initPayload);
    await depositoryProxy.deployed();

    // Wait for half a minute for the transaction completion
    await new Promise(r => setTimeout(r, 30000));

    await hre.run("verify:verify", {
        address: depositoryProxy.address,
        constructorArguments: [depository.address, initPayload],
    });
    parsedData.depositoryProxyAddress = depositoryProxy.address;
    fs.writeFileSync(globalsFile, JSON.stringify(parsedData));
    depository = await ethers.getContractAt("Depository", parsedData.depositoryProxyAddress);


    const Treasury = await ethers.getContractFactory("Treasury");
    treasury = await Treasury.deploy(parsedData.olasAddress, parsedData.stOLASAddress, parsedData.depositoryProxyAddress);
    await treasury.deployed();

    // Wait for half a minute for the transaction completion
    await new Promise(r => setTimeout(r, 30000));

    await hre.run("verify:verify", {
        address: treasury.address,
        constructorArguments: [parsedData.olasAddress, parsedData.stOLASAddress, parsedData.depositoryProxyAddress],
    });
    parsedData.treasuryAddress = treasury.address;
    fs.writeFileSync(globalsFile, JSON.stringify(parsedData));


    const TreasuryProxy = await ethers.getContractFactory("Proxy");
    initPayload = treasury.interface.encodeFunctionData("initialize", [parsedData.withdrawDelay]);
    const treasuryProxy = await TreasuryProxy.deploy(parsedData.treasuryAddress, initPayload);
    await treasuryProxy.deployed();

    // Wait for half a minute for the transaction completion
    await new Promise(r => setTimeout(r, 30000));

    await hre.run("verify:verify", {
        address: treasuryProxy.address,
        constructorArguments: [treasury.address, initPayload],
    });
    parsedData.treasuryProxyAddress = treasuryProxy.address;
    fs.writeFileSync(globalsFile, JSON.stringify(parsedData));

    // Change managers for stOLAS
    // Only Treasury contract can mint OLAS
    //st = await ethers.getContractAt("stOLAS", parsedData.stOLASAddress);
    await st.changeManagers(parsedData.treasuryProxyAddress, parsedData.depositoryProxyAddress);

    // Change treasury address in depository
    //depository = await ethers.getContractAt("Depository", parsedData.depositoryProxyAddress);
    await depository.changeTreasury(parsedData.treasuryProxyAddress);

    const GnosisDepositProcessorL1 = await ethers.getContractFactory("GnosisDepositProcessorL1");
    gnosisDepositProcessorL1 = await GnosisDepositProcessorL1.deploy(parsedData.olasAddress, parsedData.depositoryProxyAddress,
        parsedData.gnosisOmniBridgeAddress, parsedData.gnosisAMBForeignAddress, gnosisChainId);
    await gnosisDepositProcessorL1.deployed();

    // Wait for half a minute for the transaction completion
    await new Promise(r => setTimeout(r, 30000));

    await hre.run("verify:verify", {
        address: gnosisDepositProcessorL1.address,
        constructorArguments: [parsedData.olasAddress, parsedData.depositoryProxyAddress, parsedData.gnosisOmniBridgeAddress,
            parsedData.gnosisAMBForeignAddress, gnosisChainId],
    });
    parsedData.gnosisDepositProcessorL1Address = gnosisDepositProcessorL1.address;
    fs.writeFileSync(globalsFile, JSON.stringify(parsedData));


    const BaseDepositProcessorL1 = await ethers.getContractFactory("BaseDepositProcessorL1");
    baseDepositProcessorL1 = await BaseDepositProcessorL1.deploy(parsedData.olasAddress, parsedData.depositoryProxyAddress,
        parsedData.baseL1StandardBridgeProxyAddress, parsedData.baseL1CrossDomainMessengerProxyAddress, gnosisChainId,
        parsedData.baseOLASAddress);
    await baseDepositProcessorL1.deployed();

    // Wait for half a minute for the transaction completion
    await new Promise(r => setTimeout(r, 30000));

    parsedData.baseDepositProcessorL1Address = baseDepositProcessorL1.address;
    fs.writeFileSync(globalsFile, JSON.stringify(parsedData));

    await hre.run("verify:verify", {
        address: parsedData.baseDepositProcessorL1Address,
        constructorArguments: [parsedData.olasAddress, parsedData.depositoryProxyAddress,
            parsedData.baseL1StandardBridgeProxyAddress, parsedData.baseL1CrossDomainMessengerProxyAddress, gnosisChainId,
            parsedData.baseOLASAddress],
    });


    // Whitelist deposit processors
    //depository = await ethers.getContractAt("Depository", parsedData.depositoryProxyAddress);
    await depository.setDepositProcessorChainIds([parsedData.gnosisDepositProcessorL1Address], [gnosisChainId]);
    await depository.setDepositProcessorChainIds([parsedData.baseDepositProcessorL1Address], [baseChainId]);

    // Set StakingProcessorL2-s addresses in DepositProcessorL1-s
    //await gnosisDepositProcessorL1.setL2StakingProcessor(gnosisStakingProcessorL2Address);
    //await baseDepositProcessorL1.setL2StakingProcessor(baseStakingProcessorL2Address);

    // Add model to L1
    //await depository.createAndActivateStakingModels([gnosisChainId], [stakingTokenAddress], [stakingSupply]);
};

main()
    .then(() => process.exit(0))
    .catch(error => {
        console.error(error);
        process.exit(1);
    });
