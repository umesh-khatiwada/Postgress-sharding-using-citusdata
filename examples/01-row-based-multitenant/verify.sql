-- ==============================================================================
-- 01-row-based-multitenant: Verification Assertions
-- ==============================================================================

-- 1. Metadata, Colocation, and Overall Dataset Assertions
DO $$
DECLARE
    v_table_count integer;
    v_distinct_colocations integer;
    v_tenant_count integer;
    v_task_count integer;
    v_column_exists boolean;
BEGIN
    -- Assert all 5 tables are registered in citus_tables
    SELECT count(*) INTO v_table_count
    FROM citus_tables
    WHERE table_name::text IN ('tenants', 'users', 'projects', 'tasks', 'events');

    IF v_table_count != 5 THEN
        RAISE EXCEPTION 'ASSERTION FAILED: Expected 5 distributed tables in citus_tables, found %', v_table_count;
    END IF;
    RAISE NOTICE 'SUCCESS: All 5 multi-tenant tables are registered as distributed tables.';

    -- Assert Co-location: All 5 tables must share the SAME colocation_id
    SELECT count(DISTINCT colocation_id) INTO v_distinct_colocations
    FROM citus_tables
    WHERE table_name::text IN ('tenants', 'users', 'projects', 'tasks', 'events');

    IF v_distinct_colocations != 1 THEN
        RAISE EXCEPTION 'ASSERTION FAILED: Tables are NOT co-located! Found % distinct colocation IDs.', v_distinct_colocations;
    END IF;
    RAISE NOTICE 'SUCCESS: All 5 tables are verified to share the identical colocation group.';

    -- Assert Total Seed Counts across cluster
    SELECT count(*) INTO v_tenant_count FROM tenants;
    IF v_tenant_count != 4 THEN
        RAISE EXCEPTION 'ASSERTION FAILED: Expected 4 tenants, found %', v_tenant_count;
    END IF;

    SELECT count(*) INTO v_task_count FROM tasks;
    IF v_task_count != 15 THEN
        RAISE EXCEPTION 'ASSERTION FAILED: Expected 15 tasks across all tenants, found %', v_task_count;
    END IF;
    RAISE NOTICE 'SUCCESS: Cluster dataset verified (4 tenants, 15 tasks).';

    -- Test DDL column migration on tasks table
    SELECT EXISTS (
        SELECT 1 
        FROM information_schema.columns 
        WHERE table_name = 'tasks' AND column_name = 'tags'
    ) INTO v_column_exists;

    IF NOT v_column_exists THEN
        RAISE EXCEPTION 'ASSERTION FAILED: DDL column migration `tags` not found on tasks table.';
    END IF;
    RAISE NOTICE 'SUCCESS: DDL migration verified (column `tags` present across shards).';
END $$;


-- 2. Row-Level Security (RLS) Isolation Assertions under unprivileged role
-- Test Tenant 1 (Acme Corp: expects exactly 6 tasks)
BEGIN;
SET citus.propagate_set_commands = 'local';
SET LOCAL ROLE tenant_app_user;
SET LOCAL app.tenant_id = '1';
DO $$
DECLARE
    v_count integer;
BEGIN
    SELECT count(*) INTO v_count FROM tasks;
    IF v_count != 6 THEN
        RAISE EXCEPTION 'ASSERTION FAILED: Tenant 1 RLS isolation expected 6 tasks, got %', v_count;
    END IF;
    RAISE NOTICE 'SUCCESS: Tenant 1 RLS policy verified (exactly 6 tasks visible).';
END $$;
COMMIT;

-- Test Tenant 2 (Globex Logistics: expects exactly 4 tasks)
BEGIN;
SET citus.propagate_set_commands = 'local';
SET LOCAL ROLE tenant_app_user;
SET LOCAL app.tenant_id = '2';
DO $$
DECLARE
    v_count integer;
BEGIN
    SELECT count(*) INTO v_count FROM tasks;
    IF v_count != 4 THEN
        RAISE EXCEPTION 'ASSERTION FAILED: Tenant 2 RLS isolation expected 4 tasks, got %', v_count;
    END IF;
    RAISE NOTICE 'SUCCESS: Tenant 2 RLS policy verified (exactly 4 tasks visible).';
END $$;
COMMIT;
