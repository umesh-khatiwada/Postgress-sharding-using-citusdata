-- ============================================================================
-- Example 07: Real-Time Analytics
-- Analytical Demonstration Queries
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. Real-time Distributed Parallel Aggregation on Raw Ingested Events
-- ----------------------------------------------------------------------------
-- Scans the raw event table. Demonstrates Citus adaptive executor pushing
-- aggregation down to workers and combining partial results on coordinator.
EXPLAIN (ANALYZE, VERBOSE)
SELECT
    tenant_id,
    count(*) AS total_events,
    count(DISTINCT user_id) AS exact_unique_users,
    round(avg(latency_ms), 2) AS avg_latency_ms,
    count(*) FILTER (WHERE status_code >= 400) AS total_errors
FROM analytics_events
WHERE tenant_id = 1
GROUP BY tenant_id;

-- ----------------------------------------------------------------------------
-- 2. Incremental Co-Located Rollup Ingestion
-- ----------------------------------------------------------------------------
-- Rolls raw streaming events into hourly rollup cubes using HyperLogLog (hll)
-- and TopN sketches. Because both tables share tenant_id as the distribution key,
-- this query executes locally on each worker without network repartitioning.
EXPLAIN (ANALYZE, VERBOSE)
INSERT INTO hourly_event_rollups (
    tenant_id,
    bucket_time,
    total_events,
    error_count,
    total_latency_ms,
    unique_users,
    top_paths
)
SELECT
    tenant_id,
    date_trunc('hour', event_time) AS bucket_time,
    count(*) AS total_events,
    count(*) FILTER (WHERE status_code >= 400) AS error_count,
    sum(latency_ms) AS total_latency_ms,
    hll_add_agg(hll_hash_bigint(user_id)) AS unique_users,
    topn_add_agg(path) AS top_paths
FROM analytics_events
GROUP BY tenant_id, date_trunc('hour', event_time)
ON CONFLICT (tenant_id, bucket_time) DO UPDATE
SET
    total_events = hourly_event_rollups.total_events + EXCLUDED.total_events,
    error_count = hourly_event_rollups.error_count + EXCLUDED.error_count,
    total_latency_ms = hourly_event_rollups.total_latency_ms + EXCLUDED.total_latency_ms,
    unique_users = hourly_event_rollups.unique_users || EXCLUDED.unique_users,
    top_paths = topn_union(hourly_event_rollups.top_paths, EXCLUDED.top_paths);

-- ----------------------------------------------------------------------------
-- 3. Sub-second Multi-Hour Dashboard Query on Rollup Table (Plan & Execution)
-- ----------------------------------------------------------------------------
-- EXPLAIN the distributed rollup scan plan
EXPLAIN (ANALYZE)
SELECT
    tenant_id,
    sum(total_events) AS total_events,
    sum(error_count) AS total_errors,
    round(sum(total_latency_ms) / sum(total_events), 2) AS avg_latency_ms,
    round(hll_cardinality(hll_union_agg(unique_users))::numeric, 0) AS approx_unique_users
FROM hourly_event_rollups
WHERE tenant_id = 1
GROUP BY tenant_id;

-- Execute full dashboard query extracting top-3 paths from TopN sketch
WITH rollup_summary AS (
    SELECT
        tenant_id,
        sum(total_events) AS total_events,
        sum(error_count) AS total_errors,
        round(sum(total_latency_ms) / sum(total_events), 2) AS avg_latency_ms,
        round(hll_cardinality(hll_union_agg(unique_users))::numeric, 0) AS approx_unique_users,
        topn_union_agg(top_paths) AS combined_topn
    FROM hourly_event_rollups
    WHERE tenant_id = 1
    GROUP BY tenant_id
)
SELECT
    tenant_id,
    total_events,
    total_errors,
    avg_latency_ms,
    approx_unique_users,
    topn(combined_topn, 3) AS top_3_paths
FROM rollup_summary;

-- ----------------------------------------------------------------------------
-- 4. Statistical Accuracy Comparison: Exact vs HLL
-- ----------------------------------------------------------------------------
-- Verifies that HLL approximation error is within standard mathematical bound (< 2%).
WITH exact_metric AS (
    SELECT tenant_id, count(DISTINCT user_id) AS exact_users
    FROM analytics_events
    WHERE tenant_id = 1
    GROUP BY tenant_id
),
hll_metric AS (
    SELECT tenant_id, round(hll_cardinality(hll_union_agg(unique_users))::numeric, 0) AS hll_users
    FROM hourly_event_rollups
    WHERE tenant_id = 1
    GROUP BY tenant_id
)
SELECT
    e.tenant_id,
    e.exact_users,
    h.hll_users,
    round(abs(e.exact_users - h.hll_users)::numeric / e.exact_users * 100, 2) AS error_percent
FROM exact_metric e
JOIN hll_metric h ON h.tenant_id = e.tenant_id;

-- ----------------------------------------------------------------------------
-- 5. Cross-Tenant Fleet Aggregations Across All Shards
-- ----------------------------------------------------------------------------
WITH fleet_summary AS (
    SELECT
        tenant_id,
        sum(total_events) AS total_events,
        sum(error_count) AS total_errors,
        round(hll_cardinality(hll_union_agg(unique_users))::numeric, 0) AS distinct_users,
        topn_union_agg(top_paths) AS paths_sketch
    FROM hourly_event_rollups
    GROUP BY tenant_id
)
SELECT
    tenant_id,
    total_events,
    total_errors,
    distinct_users,
    topn(paths_sketch, 2) AS top_2_routes
FROM fleet_summary
ORDER BY tenant_id;
