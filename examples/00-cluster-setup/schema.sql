-- ==============================================================================
-- 00-cluster-setup: Cluster Initialization & Worker Registration
-- Authoritative Docs: https://docs.citusdata.com/en/v14.2/develop/api_udf.html#citus-add-node
-- ==============================================================================

-- 1. Ensure Citus extension is installed
CREATE EXTENSION IF NOT EXISTS citus;

-- 2. Inform the Citus cluster about the coordinator's network hostname and port.
--    This hostname is used by worker nodes when communicating back to the coordinator
--    (e.g., during 2PC distributed transactions, metadata sync, or foreign keys).
SELECT citus_set_coordinator_host('citus_coordinator', 5432);

-- 3. Register worker nodes idempotently.
--    citus_add_node(nodename, nodeport) registers a worker node with the coordinator.
--    Worker 1 & Worker 2 form our initial active worker set.
--    Worker 3 is kept available for dynamic rebalancing / scaling in Example 06.
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_dist_node 
        WHERE nodename = 'citus_worker_1' AND nodeport = 5432
    ) THEN
        PERFORM citus_add_node('citus_worker_1', 5432);
        RAISE NOTICE 'Added worker node: citus_worker_1:5432';
    ELSE
        RAISE NOTICE 'Worker citus_worker_1:5432 already registered in pg_dist_node';
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM pg_dist_node 
        WHERE nodename = 'citus_worker_2' AND nodeport = 5432
    ) THEN
        PERFORM citus_add_node('citus_worker_2', 5432);
        RAISE NOTICE 'Added worker node: citus_worker_2:5432';
    ELSE
        RAISE NOTICE 'Worker citus_worker_2:5432 already registered in pg_dist_node';
    END IF;
END $$;

-- 4. Tune default shard count for educational lab visibility.
--    Default is 32 shards in production, which spreads across large clusters.
--    For a local 2-worker lab, 4 shards per distributed table provides an intuitive
--    2-shard-per-node balanced distribution that is easy to observe in EXPLAIN output.
ALTER SYSTEM SET citus.shard_count = 4;

-- Replication factor defaults to 1 (distributed sharding relies on PostgreSQL
-- streaming replication / Patroni per-node for high availability, not shard replication).
ALTER SYSTEM SET citus.shard_replication_factor = 1;

-- Enable propagation of SET LOCAL commands to worker nodes.
-- Essential for session-based context (such as SET LOCAL app.tenant_id = ...)
-- used with PostgreSQL Row-Level Security (RLS) on distributed tables.
ALTER SYSTEM SET citus.propagate_set_commands = 'local';

-- Reload configuration to apply GUCs
SELECT pg_reload_conf();
