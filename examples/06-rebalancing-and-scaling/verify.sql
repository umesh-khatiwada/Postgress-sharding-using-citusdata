-- ============================================================================
-- Example 06: Rebalancing & Scaling
-- Automated Verification Assertions
-- ============================================================================

DO $$
DECLARE
    v_fleet_count bigint;
    v_event_count bigint;
    v_active_workers int;
    v_worker_shard_counts int[];
    v_fleets_shard_count int;
    v_events_shard_count int;
BEGIN
    RAISE NOTICE '------------------------------------------------------------';
    RAISE NOTICE 'Running Verification Suite: 06-rebalancing-and-scaling';
    RAISE NOTICE '------------------------------------------------------------';

    -- 1. Verify table distribution registration
    IF NOT EXISTS (SELECT 1 FROM citus_tables WHERE table_name = 'sensor_fleets'::regclass) THEN
        RAISE EXCEPTION 'ASSERTION FAILED: Table sensor_fleets is not registered as distributed';
    END IF;

    IF NOT EXISTS (SELECT 1 FROM citus_tables WHERE table_name = 'sensor_events'::regclass) THEN
        RAISE EXCEPTION 'ASSERTION FAILED: Table sensor_events is not registered as distributed';
    END IF;
    RAISE NOTICE '[PASS] Tables sensor_fleets and sensor_events are properly distributed';

    -- 2. Verify co-location shard counts match
    SELECT count(*) INTO v_fleets_shard_count FROM pg_dist_shard WHERE logicalrelid = 'sensor_fleets'::regclass;
    SELECT count(*) INTO v_events_shard_count FROM pg_dist_shard WHERE logicalrelid = 'sensor_events'::regclass;

    IF v_fleets_shard_count <> v_events_shard_count THEN
        RAISE EXCEPTION 'ASSERTION FAILED: Shard counts do not match between co-located tables: % vs %',
            v_fleets_shard_count, v_events_shard_count;
    END IF;
    RAISE NOTICE '[PASS] Co-located shard counts match perfectly (% shards each)', v_fleets_shard_count;

    -- 3. Verify active worker nodes in cluster
    SELECT count(*) INTO v_active_workers FROM pg_dist_node WHERE shouldhaveshards = true AND isactive = true;
    IF v_active_workers < 3 THEN
        RAISE EXCEPTION 'ASSERTION FAILED: Expected 3 active shard-holding workers, found %', v_active_workers;
    END IF;
    RAISE NOTICE '[PASS] All % worker nodes are active and configured to hold shards', v_active_workers;

    -- 4. Verify balanced placement across workers (every worker must hold at least 1 shard)
    IF EXISTS (
        SELECT 1
        FROM pg_dist_node n
        WHERE n.shouldhaveshards = true
          AND (SELECT count(*) FROM citus_shards s WHERE s.nodename = n.nodename AND s.table_name = 'sensor_fleets'::regclass) = 0
    ) THEN
        RAISE EXCEPTION 'ASSERTION FAILED: At least one active worker holds zero shards after rebalance';
    END IF;
    RAISE NOTICE '[PASS] All active worker nodes hold balanced shard placements';

    -- 5. Verify row count integrity
    SELECT count(*) INTO v_fleet_count FROM sensor_fleets;
    IF v_fleet_count < 12 THEN
        RAISE EXCEPTION 'ASSERTION FAILED: Expected at least 12 fleets, found %', v_fleet_count;
    END IF;

    SELECT count(*) INTO v_event_count FROM sensor_events;
    IF v_event_count < 12000 THEN
        RAISE EXCEPTION 'ASSERTION FAILED: Expected at least 12,000 sensor events, found %', v_event_count;
    END IF;
    RAISE NOTICE '[PASS] Row count integrity verified: % fleets, % events', v_fleet_count, v_event_count;

    RAISE NOTICE '------------------------------------------------------------';
    RAISE NOTICE 'ALL VERIFICATION ASSERTIONS PASSED FOR EXAMPLE 06';
    RAISE NOTICE '------------------------------------------------------------';
END $$;
