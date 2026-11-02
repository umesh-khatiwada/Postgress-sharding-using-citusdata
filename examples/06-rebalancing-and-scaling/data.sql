-- ============================================================================
-- Example 06: Rebalancing & Scaling
-- Seed Data Generator
-- ============================================================================

-- Insert 12 Fleets
INSERT INTO sensor_fleets (fleet_id, fleet_name, region)
VALUES
    (1,  'Nordic Logistics Fleet Alpha', 'eu-north'),
    (2,  'Nordic Logistics Fleet Beta',  'eu-north'),
    (3,  'Alpine Transit Alpine One',    'eu-central'),
    (4,  'Alpine Transit Alpine Two',    'eu-central'),
    (5,  'Pacific Cargo Express 1',      'us-west'),
    (6,  'Pacific Cargo Express 2',      'us-west'),
    (7,  'Atlantic Freight Alpha',       'us-east'),
    (8,  'Atlantic Freight Beta',        'us-east'),
    (9,  'Tokyo Urban Delivery 1',       'ap-northeast'),
    (10, 'Tokyo Urban Delivery 2',       'ap-northeast'),
    (11, 'Singapore Straits Maritime 1', 'ap-southeast'),
    (12, 'Singapore Straits Maritime 2', 'ap-southeast')
ON CONFLICT (fleet_id) DO NOTHING;

-- Insert 12,000 Sensor Readings (1,000 readings per fleet)
-- Uses generate_series to generate realistic IoT battery and temperature telemetry
INSERT INTO sensor_events (fleet_id, event_id, device_id, battery_level, temperature, payload, recorded_at)
SELECT
    f.fleet_id,
    (f.fleet_id * 100000) + s.i AS event_id,
    'DEV-' || f.fleet_id || '-' || (s.i % 20 + 1) AS device_id,
    ROUND((60 + (random() * 40))::numeric, 2) AS battery_level,
    ROUND((15 + (random() * 25))::numeric, 2) AS temperature,
    jsonb_build_object(
        'firmware', 'v2.4.1',
        'signal_strength_dbm', -60 - (s.i % 30),
        'status', CASE WHEN random() > 0.05 THEN 'OK' ELSE 'WARN' END
    ) AS payload,
    now() - ((s.i || ' minutes')::interval) AS recorded_at
FROM sensor_fleets f
CROSS JOIN generate_series(1, 1000) AS s(i)
ON CONFLICT (fleet_id, event_id) DO NOTHING;

-- Analyze to update distribution statistics
ANALYZE sensor_fleets;
ANALYZE sensor_events;
