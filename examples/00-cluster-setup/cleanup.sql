-- ==============================================================================
-- 00-cluster-setup: Cleanup & Reset Script
-- ==============================================================================

-- Reset GUCs back to defaults
ALTER SYSTEM RESET citus.shard_count;
ALTER SYSTEM RESET citus.shard_replication_factor;
SELECT pg_reload_conf();

-- Note on node removal:
-- In production, to deregister an empty/drained worker node:
-- SELECT citus_remove_node('citus_worker_2', 5432);
-- To reset the entire Docker cluster, execute: `make down`
