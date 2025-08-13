./scripts/deployment/deploy_l2_01_collector.sh $1
./scripts/deployment/deploy_l2_02_collector_proxy.sh $1
./scripts/deployment/deploy_l2_03_activity_module.sh $1
./scripts/deployment/deploy_l2_04_beacon.sh $1
./scripts/deployment/deploy_l2_05_staking_manager.sh $1
./scripts/deployment/deploy_l2_06_staking_manager_proxy.sh $1
./scripts/deployment/deploy_l2_07_module_activity_checker.sh $1
./scripts/deployment/deploy_l2_08_staking_token_locked.sh $1
./scripts/deployment/deploy_l2_09_gnosis_staking_processor.sh $1

##### !!!! For mainnet - this is subject to the DAO vote
# Whitelist staking implementation
./scripts/deployment/script_l2_01_whitelist_staking_implementation.sh $1

# Change staking processors in CollectorProxy and StakingManagerProxy
./scripts/deployment/script_l2_02_change_staking_processors.sh $1

# Fund StakingManagerProxy
./scripts/deployment/script_l2_03_fund_staking_manager.sh $1