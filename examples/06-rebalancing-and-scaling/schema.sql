-- ============================================================================
-- Example 06: Rebalancing & Scaling
-- Schema Definition
-- ============================================================================

-- Ensure Citus extension is active
CREATE EXTENSION IF NOT EXISTS citus;

-- Configure shard count for this scenario (6 shards allow clean distribution across 2 or 3 workers)
SET citus.shard_count = 6;

-- Fleet metadata table
CREATE TABLE IF NOT EXISTS sensor_fleets (
    fleet_id bigint PRIMARY KEY,
    fleet_name text NOT NULL,
    region text NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now()
);

-- IoT Sensor Events table (high-volume time-stamped events)
CREATE TABLE IF NOT EXISTS sensor_events (
    fleet_id bigint NOT NULL,
    event_id bigint NOT NULL,
    device_id text NOT NULL,
    battery_level numeric(5,2) NOT NULL,
    temperature numeric(5,2) NOT NULL,
    payload jsonb,
    recorded_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (fleet_id, event_id),
    CONSTRAINT fk_fleet FOREIGN KEY (fleet_id) REFERENCES sensor_fleets(fleet_id) ON DELETE CASCADE
);

-- Distribute both tables on fleet_id (co-located)
-- Check citus_tables first to guarantee idempotency
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM citus_tables WHERE table_name = 'sensor_fleets'::regclass) THEN
        PERFORM create_distributed_table('sensor_fleets', 'fleet_id', colocate_with => 'none');
    END IF;

    IF NOT EXISTS (SELECT 1 FROM citus_tables WHERE table_name = 'sensor_events'::regclass) THEN
        PERFORM create_distributed_table('sensor_events', 'fleet_id', colocate_with => 'sensor_fleets');
    END IF;
END $$;

-- Indexes on distributed tables automatically propagate to all worker shards
CREATE INDEX IF NOT EXISTS idx_sensor_events_fleet_recorded ON sensor_events(fleet_id, recorded_at DESC);
CREATE INDEX IF NOT EXISTS idx_sensor_events_device ON sensor_events(fleet_id, device_id);
