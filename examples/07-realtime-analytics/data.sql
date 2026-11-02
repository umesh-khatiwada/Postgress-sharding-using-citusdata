-- ============================================================================
-- Example 07: Real-Time Analytics
-- Seed Data Generator: 20,000 High-Cardinality Streaming Events
-- ============================================================================

INSERT INTO analytics_events (
    tenant_id,
    event_id,
    user_id,
    event_type,
    path,
    status_code,
    latency_ms,
    payload,
    event_time
)
SELECT
    t.tenant_id,
    (t.tenant_id * 1000000) + s.i AS event_id,
    (t.tenant_id * 10000) + (s.i % 800 + 1) AS user_id,
    CASE (s.i % 4)
        WHEN 0 THEN 'pageview'
        WHEN 1 THEN 'api_call'
        WHEN 2 THEN 'click'
        ELSE 'conversion'
    END AS event_type,
    CASE (s.i % 5)
        WHEN 0 THEN '/api/v1/products'
        WHEN 1 THEN '/api/v1/checkout'
        WHEN 2 THEN '/api/v1/search'
        WHEN 3 THEN '/api/v1/users'
        ELSE '/'
    END AS path,
    CASE
        WHEN s.i % 33 = 0 THEN 500
        WHEN s.i % 25 = 0 THEN 404
        WHEN s.i % 20 = 0 THEN 400
        WHEN s.i % 10 = 0 THEN 201
        ELSE 200
    END AS status_code,
    ROUND((10 + ((s.i * 7) % 240) + (random() * 5))::numeric, 2) AS latency_ms,
    jsonb_build_object(
        'browser', CASE (s.i % 3) WHEN 0 THEN 'Chrome' WHEN 1 THEN 'Firefox' ELSE 'Safari' END,
        'country', CASE (t.tenant_id) WHEN 1 THEN 'US' WHEN 2 THEN 'DE' WHEN 3 THEN 'JP' ELSE 'GB' END
    ) AS payload,
    -- Spread events across 10 hours
    date_trunc('hour', now()) - (((s.i % 10) || ' hours')::interval) + (((s.i % 60) || ' minutes')::interval)
FROM generate_series(1, 4) AS t(tenant_id)
CROSS JOIN generate_series(1, 5000) AS s(i)
ON CONFLICT (tenant_id, event_id) DO NOTHING;

-- Analyze to build query optimizer distribution statistics
ANALYZE analytics_events;
