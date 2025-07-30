/*global hre, process*/
const { expect } = require("chai");
const { ethers } = require("hardhat");
const fs = require("fs");

const main = async () => {
    let olas;
    let ve;
    let st;
    let lock;
    let distributor;
    let unstakeRelayer;
    let depository;
    let treasury;
    let gnosisDepositProcessorL1;
    let baseDepositProcessorL1;
    let deployer;
    const AddressZero = ethers.constants.AddressZero;
    const HashZero = ethers.constants.HashZero;
    const initSupply = "5" + "0".repeat(26);
    const gnosisChainId = 100;
    const baseChainId = 8453;
    const regDeposit = ethers.utils.parseEther("10000");
    const fullStakeDeposit = regDeposit.mul(2);
    const maxNumServices = 100;
    const stakingSupply = fullStakeDeposit.mul(ethers.BigNumber.from(maxNumServices));

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

    // Get OLAS contract
    olas = await ethers.getContractAt("ERC20Token", parsedData.olasAddress);
    //Mint tokens to the deployer
    //await olas.mint(deployer.address, initSupply);

    // Deploy stOLAS
    console.log("Deploying stOLAS");
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
    console.log("stOLAS address:", st.address);
    fs.writeFileSync(globalsFile, JSON.stringify(parsedData));

    // Deploy Lock
    console.log("Deploying Lock");
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
    console.log("Lock address:", lock.address);
    fs.writeFileSync(globalsFile, JSON.stringify(parsedData));

    // Deploy Lock Proxy
    console.log("Deploying Lock Proxy");
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
    console.log("Lock Proxy address:", lockProxy.address);
    fs.writeFileSync(globalsFile, JSON.stringify(parsedData));
    lock = await ethers.getContractAt("Lock", parsedData.lockProxyAddress);

    // Transfer initial lock
    console.log("Transfer initial lock amount");
    await olas.transfer(parsedData.lockProxyAddress, ethers.utils.parseEther("1"));

    // Set governor and create first lock
    console.log("Set governor and create first lock");
    await lock.setGovernorAndCreateFirstLock(parsedData.olasGovernorAddress, {gasLimit: 500000});

    // Deploy Distributor
    console.log("Deploying Distributor");
    const Distributor = await ethers.getContractFactory("Distributor");
    distributor = await Distributor.deploy(parsedData.olasAddress, parsedData.stOLASAddress, parsedData.lockProxyAddress);
    await distributor.deployed();

    // Wait for half a minute for the transaction completion
    await new Promise(r => setTimeout(r, 30000));

    await hre.run("verify:verify", {
        address: distributor.address,
        constructorArguments: [parsedData.olasAddress, parsedData.stOLASAddress, parsedData.lockProxyAddress],
    });
    parsedData.distributorAddress = distributor.address;
    console.log("Distributor address:", distributor.address);
    fs.writeFileSync(globalsFile, JSON.stringify(parsedData));

    // Deploy Distributor Proxy
    console.log("Deploying Distributor Proxy");
    const DistributorProxy = await ethers.getContractFactory("Proxy");
    initPayload = distributor.interface.encodeFunctionData("initialize", [parsedData.lockFactor]);
    const distributorProxy = await DistributorProxy.deploy(parsedData.distributorAddress, initPayload);
    await distributorProxy.deployed();

    // Wait for half a minute for the transaction completion
    await new Promise(r => setTimeout(r, 30000));

    await hre.run("verify:verify", {
        address: distributorProxy.address,
        constructorArguments: [distributor.address, initPayload],
    });
    parsedData.distributorProxyAddress = distributorProxy.address;
    console.log("Distributor Proxy address:", distributorProxy.address);
    fs.writeFileSync(globalsFile, JSON.stringify(parsedData));
    distributor = await ethers.getContractAt("Distributor", parsedData.distributorProxyAddress);

    // Deploy UnstakeRelayer
    console.log("Deploying UnstakeRelayer");
    const UnstakeRelayer = await ethers.getContractFactory("UnstakeRelayer");
    unstakeRelayer = await UnstakeRelayer.deploy(parsedData.olasAddress, parsedData.stOLASAddress);
    await unstakeRelayer.deployed();

    // Wait for half a minute for the transaction completion
    await new Promise(r => setTimeout(r, 30000));

    await hre.run("verify:verify", {
        address: unstakeRelayer.address,
        constructorArguments: [parsedData.olasAddress, parsedData.stOLASAddress],
    });
    parsedData.unstakeRelayerAddress = unstakeRelayer.address;
    console.log("UnstakeRelayer address:", unstakeRelayer.address);
    fs.writeFileSync(globalsFile, JSON.stringify(parsedData));

    // Deploy UnstakeRelayer Proxy
    console.log("Deploying UnstakeRelayer Proxy");
    const UnstakeRelayerProxy = await ethers.getContractFactory("Proxy");
    initPayload = unstakeRelayer.interface.encodeFunctionData("initialize", []);
    const unstakeRelayerProxy = await UnstakeRelayerProxy.deploy(parsedData.unstakeRelayerAddress, initPayload);
    await unstakeRelayerProxy.deployed();

    // Wait for half a minute for the transaction completion
    await new Promise(r => setTimeout(r, 30000));

    await hre.run("verify:verify", {
        address: unstakeRelayerProxy.address,
        constructorArguments: [unstakeRelayer.address, initPayload],
    });
    parsedData.unstakeRelayerProxyAddress = unstakeRelayerProxy.address;
    console.log("UnstakeRelayer Proxy address:", unstakeRelayerProxy.address);
    fs.writeFileSync(globalsFile, JSON.stringify(parsedData));
    unstakeRelayer = await ethers.getContractAt("UnstakeRelayer", parsedData.unstakeRelayerProxyAddress);

    // Deploy Depository
    console.log("Deploying Depository");
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
    console.log("Depository address:", depository.address);
    fs.writeFileSync(globalsFile, JSON.stringify(parsedData));

    // Deploy Depository Proxy
    console.log("Deploying Depository Proxy");
    const DepositoryProxy = await ethers.getContractFactory("Proxy");
    initPayload = depository.interface.encodeFunctionData("initialize", []);
    const depositoryProxy = await DepositoryProxy.deploy(parsedData.depositoryAddress, initPayload);
    await depositoryProxy.deployed();

    // Wait for half a minute for the transaction completion
    await new Promise(r => setTimeout(r, 30000));

    await hre.run("verify:verify", {
        address: depositoryProxy.address,
        constructorArguments: [depository.address, initPayload],
    });
    parsedData.depositoryProxyAddress = depositoryProxy.address;
    console.log("Depository Proxy address:", depositoryProxy.address);
    fs.writeFileSync(globalsFile, JSON.stringify(parsedData));
    depository = await ethers.getContractAt("Depository", parsedData.depositoryProxyAddress);

    // Deploy Treasury
    console.log("Deploying Treasury");
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
    console.log("Treasury address:", treasury.address);
    fs.writeFileSync(globalsFile, JSON.stringify(parsedData));

    // Deploy Treasury Proxy
    console.log("Deploying Treasury Proxy");
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
    console.log("Treasury Proxy address:", treasuryProxy.address);
    fs.writeFileSync(globalsFile, JSON.stringify(parsedData));

    // Change managers for stOLAS
    // Only Treasury contract can mint OLAS
    console.log("Changing stOLAS managers");
    st = await ethers.getContractAt("stOLAS", parsedData.stOLASAddress);
    await st.changeManagers(parsedData.treasuryProxyAddress, parsedData.depositoryProxyAddress);

    // Change treasury address in depository
    console.log("Change treasury address in depository");
    depository = await ethers.getContractAt("Depository", parsedData.depositoryProxyAddress);
    await depository.changeTreasury(parsedData.treasuryProxyAddress);

    // Deploy Gnosis Deposit Processor L1
    console.log("Deploying Gnosis Deposit Processor L1");
    const GnosisDepositProcessorL1 = await ethers.getContractFactory("GnosisDepositProcessorL1");
    gnosisDepositProcessorL1 = await GnosisDepositProcessorL1.deploy(parsedData.olasAddress, parsedData.depositoryProxyAddress,
        parsedData.gnosisOmniBridgeAddress, parsedData.gnosisAMBForeignAddress);
    await gnosisDepositProcessorL1.deployed();

    // Wait for half a minute for the transaction completion
    await new Promise(r => setTimeout(r, 30000));

    await hre.run("verify:verify", {
        address: gnosisDepositProcessorL1.address,
        constructorArguments: [parsedData.olasAddress, parsedData.depositoryProxyAddress, parsedData.gnosisOmniBridgeAddress,
            parsedData.gnosisAMBForeignAddress],
    });
    parsedData.gnosisDepositProcessorL1Address = gnosisDepositProcessorL1.address;
    console.log("Gnosis Deposit Processor L1 address:", gnosisDepositProcessorL1.address);
    fs.writeFileSync(globalsFile, JSON.stringify(parsedData));

    // Deploy Base Deposit Processor L1
    console.log("Deploying Base Deposit Processor L1");
    const BaseDepositProcessorL1 = await ethers.getContractFactory("BaseDepositProcessorL1");
    baseDepositProcessorL1 = await BaseDepositProcessorL1.deploy(parsedData.olasAddress, parsedData.depositoryProxyAddress,
        parsedData.baseL1StandardBridgeProxyAddress, parsedData.baseL1CrossDomainMessengerProxyAddress,
        parsedData.baseOLASAddress);
    await baseDepositProcessorL1.deployed();

    // Wait for half a minute for the transaction completion
    await new Promise(r => setTimeout(r, 30000));

    parsedData.baseDepositProcessorL1Address = baseDepositProcessorL1.address;
    console.log("Base Deposit Processor L1 address:", baseDepositProcessorL1.address);
    fs.writeFileSync(globalsFile, JSON.stringify(parsedData));

    await hre.run("verify:verify", {
        address: parsedData.baseDepositProcessorL1Address,
        constructorArguments: [parsedData.olasAddress, parsedData.depositoryProxyAddress,
            parsedData.baseL1StandardBridgeProxyAddress, parsedData.baseL1CrossDomainMessengerProxyAddress,
            parsedData.baseOLASAddress],
    });


    // Whitelist deposit processors
    depository = await ethers.getContractAt("Depository", parsedData.depositoryProxyAddress);
    await depository.setDepositProcessorChainIds([parsedData.gnosisDepositProcessorL1Address], [gnosisChainId]);
    await depository.setDepositProcessorChainIds([parsedData.baseDepositProcessorL1Address], [baseChainId]);

    // Set StakingProcessorL2-s addresses in DepositProcessorL1-s
    //console.log("Setting gnosisStakingProcessorL2 in gnosisDepositProcessorL1");
    //gnosisDepositProcessorL1 = await ethers.getContractAt("GnosisDepositProcessorL1", parsedData.gnosisDepositProcessorL1Address);
    //await gnosisDepositProcessorL1.setL2StakingProcessor(parsedData.gnosisStakingProcessorL2Address);
    //console.log("Setting baseStakingProcessorL2 in baseDepositProcessorL1");
    //baseDepositProcessorL1 = await ethers.getContractAt("BaseDepositProcessorL1", parsedData.baseDepositProcessorL1Address);
    //await baseDepositProcessorL1.setL2StakingProcessor(parsedData.baseStakingProcessorL2Address);

    // Add model to L1
    //await depository.createAndActivateStakingModels([gnosisChainId], [stakingTokenAddress], [fullStakeDeposit],
    //    [maxNumServices]);
};

main()
    .then(() => process.exit(0))
    .catch(error => {
        console.error(error);
        process.exit(1);
    });
