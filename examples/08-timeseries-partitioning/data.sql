-- ============================================================================
-- Example 08: Time-Series Partitioning
-- Seed Data Generator: 16,000 Server Telemetry Metrics Across 4 Days
-- ============================================================================

INSERT INTO server_metrics (
    tenant_id,
    metric_time,
    server_id,
    cpu_utilization,
    memory_utilization,
    disk_io_ops,
    network_bytes_in,
    network_bytes_out
)
SELECT
    t.tenant_id,
    -- Spread timestamps across the last 4 days in 15-minute increments
    date_trunc('day', now()) - (((s.i % 4) || ' days')::interval) + (((s.i % 96) * 15 || ' minutes')::interval) AS metric_time,
    'srv-node-' || ((s.i % 10) + 1) AS server_id,
    ROUND((10 + ((s.i * 13) % 85) + (random() * 5))::numeric, 2) AS cpu_utilization,
    ROUND((20 + ((s.i * 7) % 75) + (random() * 4))::numeric, 2) AS memory_utilization,
    (50 + ((s.i * 17) % 2500))::int AS disk_io_ops,
    (1048576 + ((s.i * 65536) % 52428800))::bigint AS network_bytes_in,
    (524288 + ((s.i * 32768) % 26214400))::bigint AS network_bytes_out
FROM generate_series(1, 4) AS t(tenant_id)
CROSS JOIN generate_series(1, 4000) AS s(i)
ON CONFLICT (tenant_id, metric_time, server_id) DO NOTHING;

-- Analyze to update distribution and partition statistics
ANALYZE server_metrics;
