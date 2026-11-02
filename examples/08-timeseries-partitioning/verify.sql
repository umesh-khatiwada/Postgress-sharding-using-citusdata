-- ============================================================================
-- Example 08: Time-Series Partitioning
-- Automated Verification Assertions
-- ============================================================================

DO $$
DECLARE
    v_partition_count int;
    v_shards_per_part int;
    v_row_count bigint;
BEGIN
    RAISE NOTICE '------------------------------------------------------------';
    RAISE NOTICE 'Running Verification Suite: 08-timeseries-partitioning';
    RAISE NOTICE '------------------------------------------------------------';

    -- 1. Verify parent table is distributed
    IF NOT EXISTS (SELECT 1 FROM citus_tables WHERE table_name = 'server_metrics'::regclass) THEN
        RAISE EXCEPTION 'ASSERTION FAILED: Table server_metrics is not registered as distributed';
    END IF;
    RAISE NOTICE '[PASS] Root table server_metrics is registered as distributed';

    -- 2. Verify child partitions exist
    SELECT count(*) INTO v_partition_count
    FROM pg_inherits
    WHERE inhparent = 'server_metrics'::regclass;

    IF v_partition_count < 4 THEN
        RAISE EXCEPTION 'ASSERTION FAILED: Expected >= 4 active partitions, found %', v_partition_count;
    END IF;
    RAISE NOTICE '[PASS] Time-series partitions created and active (% partitions)', v_partition_count;

    -- 3. Verify every child partition has distributed shards on workers
    SELECT count(DISTINCT cs.table_name) INTO v_shards_per_part
    FROM citus_shards cs
    JOIN pg_inherits i ON cs.table_name = i.inhrelid::regclass
    WHERE i.inhparent = 'server_metrics'::regclass;

    IF v_shards_per_part <> v_partition_count THEN
        RAISE EXCEPTION 'ASSERTION FAILED: Sharded partitions (%) does not match catalog partition count (%)',
            v_shards_per_part, v_partition_count;
    END IF;
    RAISE NOTICE '[PASS] All % active child partitions have corresponding distributed shards on workers', v_shards_per_part;

    -- 4. Verify data retention integrity after drop_old_time_partitions
    SELECT count(*) INTO v_row_count FROM server_metrics;
    IF v_row_count = 0 THEN
        RAISE EXCEPTION 'ASSERTION FAILED: Table server_metrics has 0 rows after partition pruning';
    END IF;
    RAISE NOTICE '[PASS] Active row count after retention cleanup verified: % rows', v_row_count;

    RAISE NOTICE '------------------------------------------------------------';
    RAISE NOTICE 'ALL VERIFICATION ASSERTIONS PASSED FOR EXAMPLE 08';
    RAISE NOTICE '------------------------------------------------------------';
END $$;
