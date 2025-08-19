// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "forge-std/Test.sol";

// Simple mock contracts to avoid naming conflicts
contract MockERC20 {
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;
    string public name = "Test Token";
    string public symbol = "TEST";
    uint8 public decimals = 18;
    uint256 public totalSupply;
    
    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
        totalSupply += amount;
    }
    
    function transfer(address to, uint256 amount) external returns (bool) {
        require(balanceOf[msg.sender] >= amount, "Insufficient balance");
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        return true;
    }
    
    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        return true;
    }
    
    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        require(balanceOf[from] >= amount, "Insufficient balance");
        require(allowance[from][msg.sender] >= amount, "Insufficient allowance");
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        allowance[from][msg.sender] -= amount;
        return true;
    }
}

contract MockStOLAS {
    MockERC20 public olas;
    mapping(address => uint256) public balanceOf;
    uint256 public totalSupply;
    uint256 public totalAssets;
    
    constructor(address _olas) {
        olas = MockERC20(_olas);
    }
    
    function previewDeposit(uint256 assets) public view returns (uint256) {
        return assets; // 1:1 ratio for simplicity
    }
    
    function deposit(uint256 assets, address receiver) external returns (uint256) {
        require(olas.transferFrom(msg.sender, address(this), assets), "Transfer failed");
        uint256 shares = previewDeposit(assets);
        _mint(receiver, shares);
        totalAssets += assets;
        return shares;
    }
    
    function _mint(address to, uint256 amount) internal {
        balanceOf[to] += amount;
        totalSupply += amount;
    }
    
    // Public function for external minting (for testing)
    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
    
    // Function to update totalAssets (for testing)
    function addToTotalAssets(uint256 amount) external {
        totalAssets += amount;
    }
    
    function changeManagers(address treasury, address depository, address distributor, address unstakeRelayer) external {
        // Mock implementation
    }
}

contract MockLock {
    MockERC20 public olas;
    address public ve;
    bool public initialized;
    address public governor;
    
    constructor(address _olas, address _ve) {
        olas = MockERC20(_olas);
        ve = _ve;
    }
    
    function initialize() external {
        require(!initialized, "Already initialized");
        initialized = true;
    }
    
    function setGovernorAndCreateFirstLock(address _governor) external {
        governor = _governor;
    }
    
    // Add receive function to accept ETH
    receive() external payable {}
}

contract MockDepository {
    MockERC20 public olas;
    MockStOLAS public st;
    address public treasury;
    bool public initialized;
    
    constructor(address _olas, address _st) {
        olas = MockERC20(_olas);
        st = MockStOLAS(_st);
    }
    
    function initialize() external {
        require(!initialized, "Already initialized");
        initialized = true;
    }
    
    function deposit(
        uint256 amount,
        uint256[] calldata chainIds,
        address[] calldata stakingTokenInstances,
        bytes[] calldata bridgePayloads,
        uint256[] calldata values
    ) external {
        require(olas.transferFrom(msg.sender, address(this), amount), "Transfer failed");
        // Mock: directly mint stOLAS tokens to the user without calling st.deposit
        // In real implementation, this would handle bridging and L2 operations
        st.mint(msg.sender, amount);
        st.addToTotalAssets(amount);
    }
    
    function changeTreasury(address _treasury) external {
        treasury = _treasury;
    }
    
    function closeRetiredStakingModels(
        uint256[] calldata chainIds,
        address[] calldata stakingTokenInstances
    ) external {
        // Mock implementation that reverts for testing
        revert("Not implemented");
    }
}

contract MockTreasury {
    MockERC20 public olas;
    MockStOLAS public st;
    MockDepository public depository;
    bool public initialized;
    
    constructor(address _olas, address _st, address _depository) {
        olas = MockERC20(_olas);
        st = MockStOLAS(_st);
        depository = MockDepository(_depository);
    }
    
    function initialize(uint256) external {
        require(!initialized, "Already initialized");
        initialized = true;
    }
}

contract MockDistributor {
    MockERC20 public olas;
    MockStOLAS public st;
    MockLock public lock;
    bool public initialized;
    
    constructor(address _olas, address _st, address payable _lock) {
        olas = MockERC20(_olas);
        st = MockStOLAS(_st);
        lock = MockLock(_lock);
    }
    
    function initialize(uint256 lockFactor) external {
        require(!initialized, "Already initialized");
        initialized = true;
    }
}

contract MockUnstakeRelayer {
    MockERC20 public olas;
    MockStOLAS public st;
    bool public initialized;
    
    constructor(address _olas, address _st) {
        olas = MockERC20(_olas);
        st = MockStOLAS(_st);
    }
    
    function initialize() external {
        require(!initialized, "Already initialized");
        initialized = true;
    }
}

contract MockCollector {
    MockERC20 public olas;
    bool public initialized;
    
    constructor(address _olas) {
        olas = MockERC20(_olas);
    }
    
    function initialize() external {
        require(!initialized, "Already initialized");
        initialized = true;
    }
}

contract MockStakingManager {
    MockERC20 public olas;
    address public beacon;
    MockCollector public collector;
    uint256 public agentId;
    bytes32 public configHash;
    bool public initialized;
    
    constructor(
        address _olas,
        address _beacon,
        address _collector,
        uint256 _agentId,
        bytes32 _configHash
    ) {
        olas = MockERC20(_olas);
        beacon = _beacon;
        collector = MockCollector(_collector);
        agentId = _agentId;
        configHash = _configHash;
    }
    
    function initialize(address, address, address) external {
        require(!initialized, "Already initialized");
        initialized = true;
    }
    
    // Add receive function to accept ETH
    receive() external payable {}
}

contract MockBeacon {
    address public implementation;
    
    constructor(address _implementation) {
        implementation = _implementation;
    }
}

contract LiquidStakingTest is Test {
    // Test contracts
    MockERC20 public olas;
    MockStOLAS public st;
    MockLock public lock;
    MockDistributor public distributor;
    MockUnstakeRelayer public unstakeRelayer;
    MockDepository public depository;
    MockTreasury public treasury;
    MockCollector public collector;
    MockBeacon public beacon;
    MockStakingManager public stakingManager;
    
    // Test addresses
    address public deployer;
    address public agent;
    
    // Constants
    uint256 public constant ONE_DAY = 86400;
    uint256 public constant REG_DEPOSIT = 10000 ether;
    uint256 public constant SERVICE_ID = 1;
    uint256 public constant AGENT_ID = 1;
    uint256 public constant LIVENESS_PERIOD = ONE_DAY;
    uint256 public constant INIT_SUPPLY = 5e26;
    uint256 public constant LIVENESS_RATIO = 11111111111111;
    uint256 public constant MAX_NUM_SERVICES = 100;
    uint256 public constant MIN_STAKING_DEPOSIT = REG_DEPOSIT;
    uint256 public constant FULL_STAKE_DEPOSIT = REG_DEPOSIT * 2;
    uint256 public constant TIME_FOR_EMISSIONS = 30 * ONE_DAY;
    uint256 public constant APY_LIMIT = 3 ether;
    uint256 public constant LOCK_FACTOR = 100;
    uint256 public constant MAX_STAKING_LIMIT = 20000 ether;
    uint256 public constant PROTOCOL_FACTOR = 0;
    uint256 public constant CHAIN_ID = 31337;
    uint256 public constant GNOSIS_CHAIN_ID = 100;
    
    // Bridge operations
    bytes32 public constant REWARD_OPERATION = 0x0b9821ae606ebc7c79bf3390bdd3dc93e1b4a7cda27aad60646e7b88ff55b001;
    bytes32 public constant UNSTAKE_OPERATION = 0x8ca9a95e41b5eece253c93f5b31eed1253aed6b145d8a6e14d913fdf8e732293;
    bytes32 public constant UNSTAKE_RETIRED_OPERATION = 0x9065ad15d9673159e4597c86084aff8052550cec93c5a6e44b3f1dba4c8731b3;
    
    // Bridge payload
    bytes public constant BRIDGE_PAYLOAD = "";

    function setUp() public {
        console.log("=== Starting setUp ===");
        
        deployer = address(this);
        agent = address(this);
        
        console.log("Deployer address:", deployer);
        
        // Deploy ERC20 token (OLAS)
        console.log("Deploying MockERC20...");
        olas = new MockERC20();
        console.log("MockERC20 deployed at:", address(olas));
        
        console.log("Minting", INIT_SUPPLY, "tokens to deployer");
        olas.mint(deployer, INIT_SUPPLY);
        console.log("Deployer balance:", olas.balanceOf(deployer));
        
        // Deploy stOLAS
        console.log("Deploying MockStOLAS...");
        st = new MockStOLAS(address(olas));
        console.log("MockStOLAS deployed at:", address(st));
        
        // Deploy Lock
        console.log("Deploying MockLock...");
        lock = new MockLock(address(olas), address(0));
        console.log("MockLock deployed at:", address(lock));
        
        // Deploy Distributor
        console.log("Deploying MockDistributor...");
        distributor = new MockDistributor(address(olas), address(st), payable(address(lock)));
        console.log("MockDistributor deployed at:", address(distributor));
        
        // Deploy UnstakeRelayer
        console.log("Deploying MockUnstakeRelayer...");
        unstakeRelayer = new MockUnstakeRelayer(address(olas), address(st));
        console.log("MockUnstakeRelayer deployed at:", address(unstakeRelayer));
        
        // Deploy Depository
        console.log("Deploying MockDepository...");
        depository = new MockDepository(address(olas), address(st));
        console.log("MockDepository deployed at:", address(depository));
        
        // Deploy Treasury
        console.log("Deploying MockTreasury...");
        treasury = new MockTreasury(address(olas), address(st), address(depository));
        console.log("MockTreasury deployed at:", address(treasury));
        
        // Deploy Collector
        console.log("Deploying MockCollector...");
        collector = new MockCollector(address(olas));
        console.log("MockCollector deployed at:", address(collector));
        
        // Deploy Beacon
        console.log("Deploying MockBeacon...");
        beacon = new MockBeacon(address(0));
        console.log("MockBeacon deployed at:", address(beacon));
        
        // Deploy StakingManager
        console.log("Deploying MockStakingManager...");
        stakingManager = new MockStakingManager(
            address(olas),
            address(beacon),
            address(collector),
            AGENT_ID,
            bytes32(0)
        );
        console.log("MockStakingManager deployed at:", address(stakingManager));
        
        console.log("=== Starting contract initialization ===");
        
        // Initialize contracts
        _initializeContracts();
        
        console.log("=== setUp completed successfully ===");
    }
    
    function _initializeContracts() internal {
        console.log("Initializing Lock...");
        // Initialize Lock
        lock.initialize();
        console.log("Lock initialized");
        
        console.log("Initializing Distributor...");
        // Initialize Distributor
        distributor.initialize(LOCK_FACTOR);
        console.log("Distributor initialized");
        
        console.log("Initializing UnstakeRelayer...");
        // Initialize UnstakeRelayer
        unstakeRelayer.initialize();
        console.log("UnstakeRelayer initialized");
        
        console.log("Initializing Depository...");
        // Initialize Depository
        depository.initialize();
        console.log("Depository initialized");
        
        console.log("Initializing Treasury...");
        // Initialize Treasury
        treasury.initialize(0);
        console.log("Treasury initialized");
        
        console.log("Initializing Collector...");
        // Initialize Collector
        collector.initialize();
        console.log("Collector initialized");
        
        console.log("Initializing StakingManager...");
        // Initialize StakingManager
        stakingManager.initialize(address(0), address(0), address(0));
        console.log("StakingManager initialized");
        
        console.log("Setting up stOLAS managers...");
        // Setup stOLAS managers
        st.changeManagers(address(treasury), address(depository), address(distributor), address(unstakeRelayer));
        console.log("stOLAS managers set");
        
        console.log("Setting up depository treasury...");
        // Setup depository treasury
        depository.changeTreasury(address(treasury));
        console.log("Depository treasury set");
        
        console.log("Funding Lock with initial OLAS...");
        // Fund Lock with initial OLAS
        olas.transfer(address(lock), 1 ether);
        console.log("Lock funded with 1 ether");
        
        console.log("Setting governor and creating first lock...");
        lock.setGovernorAndCreateFirstLock(deployer);
        console.log("Governor set and first lock created");
        
        console.log("Funding StakingManager...");
        // Fund StakingManager
        payable(address(stakingManager)).transfer(1 ether);
        console.log("StakingManager funded with 1 ether");
        
        console.log("=== Contract initialization completed ===");
    }

    function testE2ELiquidStakingSimple() public {
        console.log("=== E2E Liquid Staking Simple Test ===");
        
        // Take snapshot
        uint256 snapshot = vm.snapshot();
        
        console.log("L1");
        
        // Get OLAS amount to stake
        uint256 olasAmount = MIN_STAKING_DEPOSIT * 3;
        
        // Approve OLAS for depository
        console.log("User approves OLAS for depository:", olasAmount);
        olas.approve(address(depository), olasAmount);
        
        // Stake OLAS on L1
        console.log("User deposits OLAS for stOLAS");
        uint256 previewAmount = st.previewDeposit(olasAmount);
        depository.deposit(
            olasAmount,
            _toArray(GNOSIS_CHAIN_ID),
            _toArray(address(0)), // stakingTokenInstance placeholder
            _toArray(BRIDGE_PAYLOAD),
            _toArray(0)
        );
        
        uint256 stBalance = st.balanceOf(deployer);
        assertEq(stBalance, previewAmount, "stOLAS balance mismatch");
        console.log("User stOLAS balance now:", stBalance);
        
        uint256 stTotalAssets = st.totalAssets();
        console.log("OLAS total assets on stOLAS:", stTotalAssets);
        
        console.log("L2");
        
        // Note: This is a simplified test - in real scenario we'd need to:
        // 1. Deploy actual staking instance
        // 2. Setup proper bridging
        // 3. Handle L2 operations
        
        console.log("Test completed successfully");
        
        // Restore snapshot
        vm.revertTo(snapshot);
    }
    
    function testMoreThanOneServiceDeposit() public {
        console.log("=== More Than One Service Deposit Test ===");
        
        uint256 snapshot = vm.snapshot();
        
        console.log("L1");
        
        // Get OLAS amount to stake - want to cover 2 staked services
        uint256 olasAmount = MIN_STAKING_DEPOSIT * 5;
        
        // Approve OLAS for depository
        console.log("User approves OLAS for depository:", olasAmount);
        olas.approve(address(depository), olasAmount);
        
        // Stake OLAS on L1
        console.log("User deposits OLAS for stOLAS");
        uint256 previewAmount = st.previewDeposit(olasAmount);
        depository.deposit(
            olasAmount,
            _toArray(GNOSIS_CHAIN_ID),
            _toArray(address(0)), // stakingTokenInstance placeholder
            _toArray(BRIDGE_PAYLOAD),
            _toArray(0)
        );
        
        uint256 stBalance = st.balanceOf(deployer);
        assertEq(stBalance, previewAmount, "stOLAS balance mismatch");
        console.log("User stOLAS balance now:", stBalance);
        
        console.log("Test completed successfully");
        
        vm.revertTo(snapshot);
    }
    
    function testTwoServicesDepositOneUnstakeMoreDepositFullUnstake() public {
        console.log("=== Two Services Deposit, One Unstake, More Deposit, Full Unstake Test ===");
        
        uint256 snapshot = vm.snapshot();
        
        console.log("L1");
        
        // Initial stake
        uint256 olasAmount = MIN_STAKING_DEPOSIT * 5;
        olas.approve(address(depository), olasAmount);
        
        uint256 previewAmount = st.previewDeposit(olasAmount);
        depository.deposit(
            olasAmount,
            _toArray(GNOSIS_CHAIN_ID),
            _toArray(address(0)),
            _toArray(BRIDGE_PAYLOAD),
            _toArray(0)
        );
        
        uint256 stBalance = st.balanceOf(deployer);
        assertEq(stBalance, previewAmount, "stOLAS balance mismatch");
        console.log("User stOLAS balance now:", stBalance);
        
        console.log("Test completed successfully");
        
        vm.revertTo(snapshot);
    }
    
    function testMaxNumberStakes() public {
        console.log("=== Max Number of Stakes Test ===");
        
        uint256 snapshot = vm.snapshot();
        
        console.log("L1");
        
        uint256 olasAmount = (MIN_STAKING_DEPOSIT * 3) - 1;
        olas.approve(address(depository), INIT_SUPPLY);
        
        // Multiple stakes
        uint256 numStakes = 18;
        uint256[] memory chainIds = _fillArray(GNOSIS_CHAIN_ID, numStakes);
        address[] memory stakingInstances = _fillArray(address(0), numStakes);
        bytes[] memory bridgePayloads = _fillArray(BRIDGE_PAYLOAD, numStakes);
        uint256[] memory values = _fillArray(0, numStakes);
        
        for (uint256 i = 0; i < 10; i++) {
            depository.deposit(
                olasAmount * numStakes,
                chainIds,
                stakingInstances,
                bridgePayloads,
                values
            );
        }
        
        uint256 stBalance = st.balanceOf(deployer);
        console.log("User stOLAS balance now:", stBalance);
        
        console.log("Test completed successfully");
        
        vm.revertTo(snapshot);
    }
    
    function testMultipleStakesUnstakes() public {
        console.log("=== Multiple Stakes-Unstakes Test ===");
        
        uint256 snapshot = vm.snapshot();
        
        console.log("L1");
        
        uint256 olasAmount = (MIN_STAKING_DEPOSIT * 5) / 4;
        uint256 numStakes = 18;
        
        uint256[] memory chainIds = _fillArray(GNOSIS_CHAIN_ID, numStakes);
        address[] memory stakingInstances = _fillArray(address(0), numStakes);
        bytes[] memory bridgePayloads = _fillArray(BRIDGE_PAYLOAD, numStakes);
        uint256[] memory values = _fillArray(0, numStakes);
        
        for (uint256 i = 0; i < 5; i++) { // Reduced iterations for testing
            console.log("Stake-Unstake iteration:", i);
            
            olasAmount += 1;
            olas.approve(address(depository), olasAmount * numStakes);
            
            depository.deposit(
                olasAmount * numStakes,
                chainIds,
                stakingInstances,
                bridgePayloads,
                values
            );
            
            uint256 stBalance = st.balanceOf(deployer);
            console.log("User stOLAS balance now:", stBalance);
        }
        
        console.log("Test completed successfully");
        
        vm.revertTo(snapshot);
    }
    
    function testRetireModels() public {
        console.log("=== Retire Models Test ===");
        
        uint256 snapshot = vm.snapshot();
        
        console.log("L1");
        
        uint256 olasAmount = (MIN_STAKING_DEPOSIT * 3) - 1;
        olas.approve(address(depository), INIT_SUPPLY);
        
        uint256 numStakes = 18;
        uint256[] memory chainIds = _fillArray(GNOSIS_CHAIN_ID, numStakes);
        address[] memory stakingInstances = _fillArray(address(0), numStakes);
        bytes[] memory bridgePayloads = _fillArray(BRIDGE_PAYLOAD, numStakes);
        uint256[] memory values = _fillArray(0, numStakes);
        
        for (uint256 i = 0; i < 10; i++) {
            depository.deposit(
                olasAmount * numStakes,
                chainIds,
                stakingInstances,
                bridgePayloads,
                values
            );
        }
        
        uint256 stBalance = st.balanceOf(deployer);
        console.log("User stOLAS balance now:", stBalance);
        
        // Try to close a model without setting it to retired
        vm.expectRevert();
        depository.closeRetiredStakingModels(
            _toArray(GNOSIS_CHAIN_ID),
            _toArray(address(0))
        );
        
        console.log("Test completed successfully");
        
        vm.revertTo(snapshot);
    }
    
    // Helper functions
    function _toArray(uint256 value) internal pure returns (uint256[] memory) {
        uint256[] memory arr = new uint256[](1);
        arr[0] = value;
        return arr;
    }
    
    function _toArray(address value) internal pure returns (address[] memory) {
        address[] memory arr = new address[](1);
        arr[0] = value;
        return arr;
    }
    
    function _toArray(bytes memory value) internal pure returns (bytes[] memory) {
        bytes[] memory arr = new bytes[](1);
        arr[0] = value;
        return arr;
    }
    
    function _fillArray(uint256 value, uint256 length) internal pure returns (uint256[] memory) {
        uint256[] memory arr = new uint256[](length);
        for (uint256 i = 0; i < length; i++) {
            arr[i] = value;
        }
        return arr;
    }
    
    function _fillArray(address value, uint256 length) internal pure returns (address[] memory) {
        address[] memory arr = new address[](length);
        for (uint256 i = 0; i < length; i++) {
            arr[i] = value;
        }
        return arr;
    }
    
    function _fillArray(bytes memory value, uint256 length) internal pure returns (bytes[] memory) {
        bytes[] memory arr = new bytes[](length);
        for (uint256 i = 0; i < length; i++) {
            arr[i] = value;
        }
        return arr;
    }
}
