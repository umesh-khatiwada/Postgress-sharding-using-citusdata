-- ============================================================================
-- Example 07: Real-Time Analytics
-- Schema Definition: Raw Events & Incremental Rollup Tables
-- ============================================================================

-- Ensure required extensions are active on coordinator and distributed to workers
CREATE EXTENSION IF NOT EXISTS citus;
CREATE EXTENSION IF NOT EXISTS hll;
CREATE EXTENSION IF NOT EXISTS topn;

-- Set shard count for real-time analytics
SET citus.shard_count = 6;

-- ----------------------------------------------------------------------------
-- 1. Raw Event Stream Table (High-volume ingested events)
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS analytics_events (
    tenant_id int NOT NULL,
    event_id bigint NOT NULL,
    user_id bigint NOT NULL,
    event_type text NOT NULL,
    path text NOT NULL,
    status_code int NOT NULL,
    latency_ms numeric(8,2) NOT NULL,
    payload jsonb,
    event_time timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (tenant_id, event_id)
);

-- ----------------------------------------------------------------------------
-- 2. Incremental Hourly Rollup Table (Pre-aggregated analytical cubes)
-- ----------------------------------------------------------------------------
-- Uses HyperLogLog (hll) for unionable distinct counts in O(1) space
-- Uses TopN (jsonb sketch) for tracking most frequent endpoints
CREATE TABLE IF NOT EXISTS hourly_event_rollups (
    tenant_id int NOT NULL,
    bucket_time timestamptz NOT NULL,
    total_events bigint NOT NULL DEFAULT 0,
    error_count bigint NOT NULL DEFAULT 0,
    total_latency_ms numeric(14,2) NOT NULL DEFAULT 0,
    unique_users hll NOT NULL DEFAULT hll_empty(),
    top_paths jsonb NOT NULL DEFAULT '{}'::jsonb,
    PRIMARY KEY (tenant_id, bucket_time)
);

-- ----------------------------------------------------------------------------
-- 3. Distribute Tables (Co-located by tenant_id)
-- ----------------------------------------------------------------------------
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM citus_tables WHERE table_name = 'analytics_events'::regclass) THEN
        PERFORM create_distributed_table('analytics_events', 'tenant_id', colocate_with => 'none');
    END IF;

    IF NOT EXISTS (SELECT 1 FROM citus_tables WHERE table_name = 'hourly_event_rollups'::regclass) THEN
        PERFORM create_distributed_table('hourly_event_rollups', 'tenant_id', colocate_with => 'analytics_events');
    END IF;
END $$;

-- Analytical indexes
CREATE INDEX IF NOT EXISTS idx_analytics_events_time ON analytics_events (tenant_id, event_time DESC);
CREATE INDEX IF NOT EXISTS idx_hourly_rollups_time ON hourly_event_rollups (tenant_id, bucket_time DESC);
