-- ============================================================================
-- Example 08: Time-Series Partitioning
-- Schema Definition: Distributed Declarative Partitioning
-- ============================================================================

-- Ensure Citus extension is installed
CREATE EXTENSION IF NOT EXISTS citus;

-- Configure shard count for time-series lab
SET citus.shard_count = 4;

-- ----------------------------------------------------------------------------
-- 1. Partitioned Table Root Definition
-- ----------------------------------------------------------------------------
-- Primary key in a range-partitioned table MUST include both the distribution
-- column (tenant_id) and the partition column (metric_time).
CREATE TABLE IF NOT EXISTS server_metrics (
    tenant_id int NOT NULL,
    metric_time timestamptz NOT NULL,
    server_id text NOT NULL,
    cpu_utilization numeric(5,2) NOT NULL,
    memory_utilization numeric(5,2) NOT NULL,
    disk_io_ops int NOT NULL,
    network_bytes_in bigint NOT NULL,
    network_bytes_out bigint NOT NULL,
    PRIMARY KEY (tenant_id, metric_time, server_id)
) PARTITION BY RANGE (metric_time);

-- ----------------------------------------------------------------------------
-- 2. Distribute Partitioned Table Across Citus Shards
-- ----------------------------------------------------------------------------
-- Citus distributes the parent table by hash on tenant_id.
-- All child partitions inherit this distribution key and shard count.
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM citus_tables WHERE table_name = 'server_metrics'::regclass) THEN
        PERFORM create_distributed_table('server_metrics', 'tenant_id', colocate_with => 'none');
    END IF;
END $$;

-- ----------------------------------------------------------------------------
-- 3. Automated Time Partition Creation
-- ----------------------------------------------------------------------------
-- Creates daily partitions spanning from 3 days ago through 2 days in the future.
SELECT create_time_partitions(
    table_name => 'server_metrics',
    partition_interval => '1 day'::interval,
    end_at => now() + interval '2 days',
    start_from => now() - interval '3 days'
);

-- Index on child partitions is automatically propagated by PostgreSQL
CREATE INDEX IF NOT EXISTS idx_server_metrics_server ON server_metrics (tenant_id, server_id, metric_time DESC);
