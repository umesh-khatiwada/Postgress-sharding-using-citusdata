-- ============================================================================
-- Example 07: Real-Time Analytics
-- Automated Verification Assertions
-- ============================================================================

DO $$
DECLARE
    v_raw_count bigint;
    v_rollup_count bigint;
    v_colocation_raw int;
    v_colocation_rollup int;
    v_exact_users bigint;
    v_hll_users numeric;
    v_error_pct numeric;
    v_top_routes text;
BEGIN
    RAISE NOTICE '------------------------------------------------------------';
    RAISE NOTICE 'Running Verification Suite: 07-realtime-analytics';
    RAISE NOTICE '------------------------------------------------------------';

    -- 1. Verify distributed table registration
    IF NOT EXISTS (SELECT 1 FROM citus_tables WHERE table_name = 'analytics_events'::regclass) THEN
        RAISE EXCEPTION 'ASSERTION FAILED: analytics_events is not distributed';
    END IF;

    IF NOT EXISTS (SELECT 1 FROM citus_tables WHERE table_name = 'hourly_event_rollups'::regclass) THEN
        RAISE EXCEPTION 'ASSERTION FAILED: hourly_event_rollups is not distributed';
    END IF;
    RAISE NOTICE '[PASS] Tables analytics_events and hourly_event_rollups are registered in Citus';

    -- 2. Verify co-location group match
    SELECT colocation_id INTO v_colocation_raw FROM citus_tables WHERE table_name = 'analytics_events'::regclass;
    SELECT colocation_id INTO v_colocation_rollup FROM citus_tables WHERE table_name = 'hourly_event_rollups'::regclass;

    IF v_colocation_raw <> v_colocation_rollup THEN
        RAISE EXCEPTION 'ASSERTION FAILED: Colocation mismatch (% vs %)', v_colocation_raw, v_colocation_rollup;
    END IF;
    RAISE NOTICE '[PASS] Both tables reside in identical colocation group %', v_colocation_raw;

    -- 3. Verify raw event ingestion volume
    SELECT count(*) INTO v_raw_count FROM analytics_events;
    IF v_raw_count < 20000 THEN
        RAISE EXCEPTION 'ASSERTION FAILED: Expected >= 20,000 raw events, found %', v_raw_count;
    END IF;
    RAISE NOTICE '[PASS] Raw event volume verified: % events', v_raw_count;

    -- 4. Verify rollup table population
    SELECT count(*) INTO v_rollup_count FROM hourly_event_rollups;
    IF v_rollup_count < 40 THEN
        RAISE EXCEPTION 'ASSERTION FAILED: Expected >= 40 rollup rows, found %', v_rollup_count;
    END IF;
    RAISE NOTICE '[PASS] Pre-aggregated rollup table verified: % hourly buckets', v_rollup_count;

    -- 5. Verify HLL statistical accuracy (tolerance < 3.0%)
    SELECT count(DISTINCT user_id) INTO v_exact_users
    FROM analytics_events
    WHERE tenant_id = 1;

    SELECT round(hll_cardinality(hll_union_agg(unique_users))::numeric, 0) INTO v_hll_users
    FROM hourly_event_rollups
    WHERE tenant_id = 1;

    v_error_pct := round(abs(v_exact_users - v_hll_users)::numeric / v_exact_users * 100, 2);

    IF v_error_pct > 3.0 THEN
        RAISE EXCEPTION 'ASSERTION FAILED: HLL error % exceeds 3.0%% tolerance (Exact: %, HLL: %)',
            v_error_pct, v_exact_users, v_hll_users;
    END IF;
    RAISE NOTICE '[PASS] HyperLogLog accuracy confirmed: Exact=%, HLL=%, Error=% %% (under 3.0%% bound)',
        v_exact_users, v_hll_users, v_error_pct;

    -- 6. Verify TopN sketch aggregation functionality
    SELECT topn(topn_union_agg(top_paths), 1)::text INTO v_top_routes
    FROM hourly_event_rollups
    WHERE tenant_id = 1
    LIMIT 1;

    IF v_top_routes IS NULL OR length(v_top_routes) = 0 THEN
        RAISE EXCEPTION 'ASSERTION FAILED: TopN sketch did not return valid routes';
    END IF;
    RAISE NOTICE '[PASS] TopN sketch query successfully extracted top route: %', v_top_routes;

    RAISE NOTICE '------------------------------------------------------------';
    RAISE NOTICE 'ALL VERIFICATION ASSERTIONS PASSED FOR EXAMPLE 07';
    RAISE NOTICE '------------------------------------------------------------';
END $$;
