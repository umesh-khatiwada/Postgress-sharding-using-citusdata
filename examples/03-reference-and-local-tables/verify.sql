-- ==============================================================================
-- 03-reference-and-local-tables: Verification Assertions
-- ==============================================================================

DO $$
DECLARE
    v_ref_count integer;
    v_dist_count integer;
    v_local_count integer;
    v_ref_placements integer;
    v_audit_join_count integer;
    v_eur_rate numeric;
    v_fk_blocked boolean := false;
BEGIN
    -- 1. Assert Table Types in citus_tables
    SELECT count(*) INTO v_ref_count
    FROM citus_tables
    WHERE citus_table_type = 'reference' AND table_name::text IN ('currencies', 'countries', 'plans');

    IF v_ref_count != 3 THEN
        RAISE EXCEPTION 'ASSERTION FAILED: Expected 3 reference tables, found %', v_ref_count;
    END IF;
    RAISE NOTICE 'SUCCESS: 3 reference tables verified in citus_tables.';

    SELECT count(*) INTO v_dist_count
    FROM citus_tables
    WHERE citus_table_type = 'distributed' AND table_name::text = 'subscriptions';

    IF v_dist_count != 1 THEN
        RAISE EXCEPTION 'ASSERTION FAILED: Expected 1 distributed subscriptions table, found %', v_dist_count;
    END IF;
    RAISE NOTICE 'SUCCESS: 1 distributed table (subscriptions) verified.';

    SELECT count(*) INTO v_local_count
    FROM citus_tables
    WHERE citus_table_type = 'local' AND table_name::text IN ('admin_audit_logs', 'global_system_settings');

    IF v_local_count != 2 THEN
        RAISE EXCEPTION 'ASSERTION FAILED: Expected 2 coordinator-local tables, found %', v_local_count;
    END IF;
    RAISE NOTICE 'SUCCESS: 2 coordinator-local tables verified.';

    -- 2. Assert Full Cluster Replication for Reference Tables
    -- Each reference table must have placements on coordinator + both workers (3 nodes)
    SELECT count(DISTINCT nodename) INTO v_ref_placements
    FROM citus_shards
    WHERE table_name::text = 'plans';

    IF v_ref_placements < 3 THEN
        RAISE EXCEPTION 'ASSERTION FAILED: plans reference table expected on at least 3 nodes, found %', v_ref_placements;
    END IF;
    RAISE NOTICE 'SUCCESS: Reference table replicated across all % nodes.', v_ref_placements;

    -- 3. Assert Coordinator-Local Table Joins
    SELECT count(*) INTO v_audit_join_count
    FROM admin_audit_logs a
    JOIN subscriptions s ON a.target_tenant_id = s.tenant_id
    JOIN plans p ON s.plan_id = p.id;

    IF v_audit_join_count != 3 THEN
        RAISE EXCEPTION 'ASSERTION FAILED: Expected 3 audit join records, got %', v_audit_join_count;
    END IF;
    RAISE NOTICE 'SUCCESS: Coordinator-local join produced 3 matching records.';

    -- 4. Assert 2PC Reference Table Write Synchronization
    SELECT exchange_rate_usd INTO v_eur_rate
    FROM currencies
    WHERE code = 'EUR';

    IF v_eur_rate != 1.0925 THEN
        RAISE EXCEPTION 'ASSERTION FAILED: EUR exchange rate was not updated to 1.0925, found %', v_eur_rate;
    END IF;
    RAISE NOTICE 'SUCCESS: Reference table write verified (EUR exchange rate = %).', v_eur_rate;

    RAISE NOTICE '======================================================================';
    RAISE NOTICE ' ALL 03-REFERENCE-AND-LOCAL-TABLES ASSERTIONS PASSED!';
    RAISE NOTICE '======================================================================';
END $$;
