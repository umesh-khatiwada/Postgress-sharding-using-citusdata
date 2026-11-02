-- ==============================================================================
-- 05-tenant-isolation: Seed Data
-- ==============================================================================

-- 1. Insert Accounts
INSERT INTO accounts (id, name, tier) VALUES
    (1,   'Stark Technologies', 'standard'),
    (2,   'Wayne Enterprises',  'standard'),
    (3,   'Cyberdyne Systems',  'standard'),
    (999, 'Titan Mega Corp',    'enterprise_noisy');

-- 2. Seed Standard Accounts Metrics
INSERT INTO account_metrics (account_id, metric_id, metric_name, metric_value) VALUES
    (1, 101, 'cpu_load_pct',   42.5),
    (1, 102, 'memory_used_mb', 1024.0),
    (2, 201, 'cpu_load_pct',   55.0),
    (2, 202, 'memory_used_mb', 2048.0),
    (3, 301, 'cpu_load_pct',   31.2),
    (3, 302, 'memory_used_mb',  512.0);

-- 3. Seed Noisy Neighbor Metrics (Account 999 generates large series of metric points)
INSERT INTO account_metrics (account_id, metric_id, metric_name, metric_value)
SELECT 
    999, 
    g, 
    'telemetry_sensor_' || (g % 20)::text,
    random() * 1000.0
FROM generate_series(1, 1000) AS g;
