-- ============================================================================
-- Example 06: Rebalancing & Scaling
-- Teardown and State Restoration Script
-- ============================================================================

-- Drop tables
DROP TABLE IF EXISTS sensor_events CASCADE;
DROP TABLE IF EXISTS sensor_fleets CASCADE;

-- Ensure all worker nodes are active and eligible to hold shards
SELECT citus_set_node_property('citus_worker_1', 5432, 'shouldhaveshards', true);
SELECT citus_set_node_property('citus_worker_2', 5432, 'shouldhaveshards', true);
SELECT citus_set_node_property('citus_worker_3', 5432, 'shouldhaveshards', true);

-- Rebalance cluster to maintain clean distribution for subsequent examples
SELECT rebalance_table_shards(shard_transfer_mode => 'block_writes');
