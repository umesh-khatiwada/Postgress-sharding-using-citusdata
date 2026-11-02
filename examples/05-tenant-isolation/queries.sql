-- ==============================================================================
-- 05-tenant-isolation: Demonstrations & Query Plans
-- Authoritative Docs: https://docs.citusdata.com/en/v14.2/admin_guide/cluster_management.html#tenant-isolation
-- ==============================================================================

-- ==============================================================================
-- 1. Simulate Workload: Hot Tenant 999 generates high query volume
-- ==============================================================================
DO $$
BEGIN
    FOR i IN 1..100 LOOP
        PERFORM avg(metric_value) FROM account_metrics WHERE account_id = 999;
    END LOOP;
END $$;


-- ==============================================================================
-- 2. Detect the Hot Tenant with citus_stat_tenants
-- The view identifies tenants with disproportionate query activity, CPU, and reads.
-- ==============================================================================
SELECT 
    nodeid,
    colocation_id,
    tenant_attribute AS hot_tenant_id,
    query_count_in_this_period,
    read_count_in_this_period,
    cpu_usage_in_this_period,
    score
FROM citus_stat_tenants(true)
WHERE tenant_attribute = '999'
ORDER BY query_count_in_this_period DESC;


-- ==============================================================================
-- 3. Shard Placement BEFORE Isolation
-- Notice that Account 999 shares standard hash-partitioned shards on worker 1 or 2.
-- ==============================================================================
SELECT 
    cs.table_name::text,
    cs.shardid,
    cs.nodename,
    cs.nodeport,
    s.shardminvalue,
    s.shardmaxvalue
FROM citus_shards cs
JOIN pg_dist_shard s ON cs.shardid = s.shardid
WHERE cs.table_name::text IN ('accounts', 'account_metrics')
ORDER BY cs.table_name, cs.shardid;


-- ==============================================================================
-- 4. Isolate Tenant 999 into a Dedicated Shard Group
-- Citus splits the existing shard range and carves out a single-tenant shard
-- dedicated solely to tenant 999 across all co-located child tables.
-- ==============================================================================
SELECT isolate_tenant_to_new_shard(
    'accounts', 
    999, 
    cascade_option => 'cascade', 
    shard_transfer_mode => 'block_writes'
) AS new_isolated_shard_id;


-- ==============================================================================
-- 5. Move Isolated Shards to Dedicated Worker Node (citus_worker_3)
-- Relocate tenant 999's shards off worker 1/2 and onto dedicated worker 3.
-- Notice: Isolated shards have shardminvalue == shardmaxvalue!
-- ==============================================================================
DO $$
DECLARE
    r RECORD;
BEGIN
    FOR r IN (
        SELECT cs.shardid, cs.nodename, cs.nodeport
        FROM citus_shards cs
        JOIN pg_dist_shard s ON cs.shardid = s.shardid
        WHERE cs.table_name::text IN ('accounts', 'account_metrics')
          AND s.shardminvalue = s.shardmaxvalue
          AND cs.nodename != 'citus_worker_3'
    ) LOOP
        RAISE NOTICE 'Moving isolated shard % from % to citus_worker_3...', r.shardid, r.nodename;
        PERFORM citus_move_shard_placement(
            r.shardid,
            r.nodename,
            r.nodeport,
            'citus_worker_3',
            5432,
            shard_transfer_mode => 'block_writes'
        );
    END LOOP;
END $$;


-- ==============================================================================
-- 6. Shard Placement AFTER Isolation & Relocation
-- Confirm that tenant 999's isolated shards reside exclusively on citus_worker_3.
-- ==============================================================================
SELECT 
    cs.table_name::text,
    cs.shardid,
    cs.nodename,
    s.shardminvalue,
    s.shardmaxvalue
FROM citus_shards cs
JOIN pg_dist_shard s ON cs.shardid = s.shardid
WHERE cs.table_name::text IN ('accounts', 'account_metrics')
  AND s.shardminvalue = s.shardmaxvalue;


-- ==============================================================================
-- 7. Query Routing Verification
-- Queries for Account 999 now route directly to dedicated worker 3!
-- ==============================================================================
EXPLAIN (ANALYZE, VERBOSE)
SELECT account_id, count(*), round(avg(metric_value), 2) AS avg_metric
FROM account_metrics
WHERE account_id = 999
GROUP BY account_id;
