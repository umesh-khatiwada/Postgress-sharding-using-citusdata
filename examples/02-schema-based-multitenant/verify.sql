-- ==============================================================================
-- 02-schema-based-multitenant: Verification Assertions
-- ==============================================================================

DO $$
DECLARE
    v_schema_count integer;
    v_table_count integer;
    v_acme_user_count integer;
    v_acme_node text;
    v_soylent_exists_distributed boolean;
BEGIN
    -- 1. Assert all 3 tenant schemas are tracked in citus_schemas
    SELECT count(*) INTO v_schema_count
    FROM citus_schemas
    WHERE schema_name::text IN ('tenant_acme', 'tenant_globex', 'tenant_soylent');

    IF v_schema_count != 3 THEN
        RAISE EXCEPTION 'ASSERTION FAILED: Expected 3 schemas in citus_schemas, found %', v_schema_count;
    END IF;
    RAISE NOTICE 'SUCCESS: 3 tenant schemas registered in citus_schemas.';

    -- 2. Assert tables have citus_table_type = 'schema'
    SELECT count(*) INTO v_table_count
    FROM citus_tables
    WHERE citus_table_type = 'schema' AND table_name::text LIKE 'tenant_%';

    IF v_table_count != 6 THEN
        RAISE EXCEPTION 'ASSERTION FAILED: Expected 6 schema-sharded tables, found %', v_table_count;
    END IF;
    RAISE NOTICE 'SUCCESS: 6 tables distributed with citus_table_type = ''schema''.';

    -- 3. Assert Data Integrity
    SELECT count(*) INTO v_acme_user_count FROM tenant_acme.users;
    IF v_acme_user_count != 2 THEN
        RAISE EXCEPTION 'ASSERTION FAILED: Expected 2 users in tenant_acme, found %', v_acme_user_count;
    END IF;
    RAISE NOTICE 'SUCCESS: Data integrity verified in tenant schemas.';

    -- 4. Test Schema Move to the alternate worker node
    SELECT DISTINCT nodename INTO v_acme_node
    FROM citus_shards
    WHERE table_name::text LIKE 'tenant_acme.%';

    -- Choose alternate node
    IF v_acme_node = 'citus_worker_1' THEN
        PERFORM citus_schema_move('tenant_acme', 'citus_worker_2', 5432, shard_transfer_mode => 'block_writes');
        v_acme_node := 'citus_worker_2';
    ELSE
        PERFORM citus_schema_move('tenant_acme', 'citus_worker_1', 5432, shard_transfer_mode => 'block_writes');
        v_acme_node := 'citus_worker_1';
    END IF;

    -- Verify move completed
    IF (SELECT DISTINCT nodename FROM citus_shards WHERE table_name::text LIKE 'tenant_acme.%') != v_acme_node THEN
        RAISE EXCEPTION 'ASSERTION FAILED: tenant_acme shards expected on %, failed to move.', v_acme_node;
    END IF;
    RAISE NOTICE 'SUCCESS: citus_schema_move relocated tenant_acme to %.', v_acme_node;

    -- 5. Test Undistribute
    PERFORM citus_schema_undistribute('tenant_soylent');

    SELECT EXISTS (
        SELECT 1 FROM citus_schemas WHERE schema_name::text = 'tenant_soylent'
    ) INTO v_soylent_exists_distributed;

    IF v_soylent_exists_distributed THEN
        RAISE EXCEPTION 'ASSERTION FAILED: tenant_soylent should have been undistributed.';
    END IF;
    RAISE NOTICE 'SUCCESS: citus_schema_undistribute converted tenant_soylent to coordinator-local.';

    -- 6. Test Redistribute
    PERFORM citus_schema_distribute('tenant_soylent');

    SELECT EXISTS (
        SELECT 1 FROM citus_schemas WHERE schema_name::text = 'tenant_soylent'
    ) INTO v_soylent_exists_distributed;

    IF NOT v_soylent_exists_distributed THEN
        RAISE EXCEPTION 'ASSERTION FAILED: tenant_soylent should have been redistributed.';
    END IF;
    RAISE NOTICE 'SUCCESS: citus_schema_distribute restored tenant_soylent as a distributed schema.';

    RAISE NOTICE '======================================================================';
    RAISE NOTICE ' ALL 02-SCHEMA-BASED-MULTITENANT VERIFICATION ASSERTIONS PASSED!';
    RAISE NOTICE '======================================================================';
END $$;
