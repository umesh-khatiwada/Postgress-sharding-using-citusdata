-- ============================================================================
-- Example 08: Time-Series Partitioning
-- Demonstration Queries
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. Inspect Declarative Partitions and Distributed Shard Placements
-- ----------------------------------------------------------------------------
-- Citus automatically distributes every child partition according to the
-- root table's distribution key (tenant_id).
SELECT
    inhrelid::regclass AS partition_name,
    pg_get_expr(c.relpartbound, c.oid) AS partition_range,
    (SELECT count(*) FROM citus_shards cs WHERE cs.table_name = inhrelid::regclass) AS shard_count
FROM pg_inherits i
JOIN pg_class c ON c.oid = i.inhrelid
WHERE inhparent = 'server_metrics'::regclass
ORDER BY partition_name;

-- ----------------------------------------------------------------------------
-- 2. Partition Pruning in Distributed EXPLAIN Plan
-- ----------------------------------------------------------------------------
-- Query metrics for today only. PostgreSQL's declarative partition pruning
-- eliminates all partition subplans (Subplans Removed: 5) so only today's
-- partition shards are queried across the worker nodes.
EXPLAIN (ANALYZE, VERBOSE)
SELECT
    tenant_id,
    server_id,
    round(avg(cpu_utilization), 2) AS avg_cpu,
    round(max(memory_utilization), 2) AS peak_mem
FROM server_metrics
WHERE metric_time >= date_trunc('day', now())
  AND metric_time < date_trunc('day', now()) + interval '1 day'
GROUP BY tenant_id, server_id
ORDER BY tenant_id, server_id;

-- ----------------------------------------------------------------------------
-- 3. Two-Dimensional Router Query (Single Tenant + Time Pruning)
-- ----------------------------------------------------------------------------
-- Sharded by tenant_id and partitioned by metric_time.
-- Notice Task Count: 1 routing to a single worker, with index scan backward
-- over only the relevant daily partition (execution in sub-0.1ms on worker).
EXPLAIN (ANALYZE, VERBOSE)
SELECT
    tenant_id,
    server_id,
    metric_time,
    cpu_utilization,
    memory_utilization
FROM server_metrics
WHERE tenant_id = 1
  AND metric_time >= date_trunc('day', now())
  AND metric_time < date_trunc('day', now()) + interval '1 day'
ORDER BY metric_time DESC
LIMIT 5;

-- ----------------------------------------------------------------------------
-- 4. Automated Retention Enforcement: Dropping Old Time Partitions
-- ----------------------------------------------------------------------------
-- Drop partitions older than 2 days ago in O(1) time without vacuum overhead
CALL drop_old_time_partitions('server_metrics', now() - interval '2 days');

-- Verify remaining active partitions
SELECT
    inhrelid::regclass AS active_partition,
    pg_get_expr(c.relpartbound, c.oid) AS partition_range
FROM pg_inherits i
JOIN pg_class c ON c.oid = i.inhrelid
WHERE inhparent = 'server_metrics'::regclass
ORDER BY active_partition;
