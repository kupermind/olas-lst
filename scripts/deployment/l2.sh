# Deploy Collector
./scripts/deployment/deploy_l2_01_collector.sh $1

# Deploy Collector Proxy
./scripts/deployment/deploy_l2_02_collector_proxy.sh $1

# Deploy ActivityModule
./scripts/deployment/deploy_l2_03_activity_module.sh $1

# Deploy Beacon
./scripts/deployment/deploy_l2_04_beacon.sh $1

# Deploy StakingManager
./scripts/deployment/deploy_l2_05_staking_manager.sh $1

# Deploy StakingManager Proxy
./scripts/deployment/deploy_l2_06_staking_manager_proxy.sh $1

# Deploy ModuleActivityChecker
./scripts/deployment/deploy_l2_07_module_activity_checker.sh $1

# Deploy StakingTokenLocked
./scripts/deployment/deploy_l2_08_staking_token_locked.sh $1

# Deploy GnosisStakingProcessorL2
./scripts/deployment/deploy_l2_09_gnosis_staking_processor.sh $1

# Deploy BaseStakingProcessorL2
#./scripts/deployment/deploy_l2_10_base_staking_processor.sh $1

# Change staking processors in CollectorProxy and StakingManagerProxy
./scripts/deployment/script_l2_01_change_staking_processors.sh $1

# Fund StakingManagerProxy
./scripts/deployment/script_l2_02_fund_staking_manager.sh $1

# Set operation receivers in Collector
./scripts/deployment/script_l2_03_set_operation_receivers_collector.sh $1

# Change protocol factor in Collector
./scripts/deployment/script_l2_0n_change_protocol_factor_collector.sh $1

##### !!!! For mainnet - this is subject to the DAO vote
# Whitelist staking implementation
./scripts/deployment/script_l2_06_whitelist_staking_implementation.sh $1