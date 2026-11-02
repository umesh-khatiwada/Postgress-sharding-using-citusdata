-- ==============================================================================
-- 00-cluster-setup: Verification Assertions
-- ==============================================================================

DO $$
DECLARE
    v_citus_version text;
    v_active_workers integer;
    v_health_errors integer;
BEGIN
    -- 1. Check Citus extension is installed
    SELECT citus_version() INTO v_citus_version;
    IF v_citus_version IS NULL OR v_citus_version = '' THEN
        RAISE EXCEPTION 'ASSERTION FAILED: Citus extension is not installed or returned empty version.';
    END IF;
    RAISE NOTICE 'SUCCESS: Citus extension detected: %', split_part(v_citus_version, ',', 1);

    -- 2. Verify active worker nodes in pg_dist_node
    SELECT count(*) INTO v_active_workers 
    FROM pg_dist_node 
    WHERE isactive = true AND noderole = 'primary' AND nodename LIKE 'citus_worker_%';

    IF v_active_workers < 2 THEN
        RAISE EXCEPTION 'ASSERTION FAILED: Expected at least 2 active primary worker nodes, found %', v_active_workers;
    END IF;
    RAISE NOTICE 'SUCCESS: % active primary worker nodes registered.', v_active_workers;

    -- 3. Verify health checks pass for all nodes
    SELECT count(*) INTO v_health_errors
    FROM citus_check_cluster_node_health()
    WHERE result = false;

    IF v_health_errors > 0 THEN
        RAISE EXCEPTION 'ASSERTION FAILED: % nodes failed the health check.', v_health_errors;
    END IF;
    RAISE NOTICE 'SUCCESS: All registered cluster nodes passed health check.';
END $$;
