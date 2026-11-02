-- ==============================================================================
-- 00-cluster-setup: Cluster Metadata & Health Introspection Queries
-- Authoritative Docs: https://docs.citusdata.com/en/v14.2/develop/api_metadata.html
-- ==============================================================================

-- 1. Citus and PostgreSQL Versions
SELECT citus_version();
SELECT version();

-- 2. List all active worker nodes known to coordinator
SELECT * FROM citus_get_active_worker_nodes();

-- 3. Query pg_dist_node catalog for complete node metadata
--    Shows node ID, DNS name, port, primary/secondary role, and active status
SELECT 
    nodeid,
    nodename,
    nodeport,
    groupid,
    noderole,
    nodecluster,
    isactive,
    shouldhaveshards
FROM pg_dist_node
ORDER BY nodeid;

-- 4. Check cluster sharding configuration settings (GUCs)
SELECT 
    name,
    setting,
    unit,
    short_desc
FROM pg_settings 
WHERE name IN (
    'citus.shard_count',
    'citus.shard_replication_factor',
    'citus.coordinator_host',
    'citus.max_adaptive_executor_pool_size'
)
ORDER BY name;

-- 5. Run cluster connectivity & health check
--    Verifies coordinator can reach all registered workers
SELECT * FROM citus_check_cluster_node_health();
