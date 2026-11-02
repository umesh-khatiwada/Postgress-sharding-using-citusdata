-- ==============================================================================
-- 05-tenant-isolation: Verification Assertions
-- ==============================================================================

DO $$
DECLARE
    v_hot_tracked boolean;
    v_titan_shard_node text;
    v_titan_metric_count integer;
    v_stark_metric_count integer;
BEGIN
    -- 1. Assert Tenant 999 was tracked as hot tenant in citus_stat_tenants
    -- Accounts for either current period or prior period rollover
    SELECT EXISTS (
        SELECT 1 FROM citus_stat_tenants(true)
        WHERE tenant_attribute = '999' 
          AND (query_count_in_this_period + query_count_in_last_period) >= 50
    ) INTO v_hot_tracked;

    IF NOT v_hot_tracked THEN
        RAISE EXCEPTION 'ASSERTION FAILED: Tenant 999 was not detected as a hot tenant in citus_stat_tenants!';
    END IF;
    RAISE NOTICE 'SUCCESS: Hot tenant 999 successfully detected via citus_stat_tenants.';

    -- 2. Assert Dedicated Shard Creation & Placement on Dedicated Hardware Node (citus_worker_3)
    -- In pg_dist_shard, single-tenant isolated shards have shardminvalue == shardmaxvalue
    SELECT cs.nodename INTO v_titan_shard_node
    FROM citus_shards cs
    JOIN pg_dist_shard s ON cs.shardid = s.shardid
    WHERE cs.table_name::text = 'account_metrics'
      AND s.shardminvalue = s.shardmaxvalue
    ORDER BY cs.shardid DESC
    LIMIT 1;

    IF v_titan_shard_node != 'citus_worker_3' THEN
        RAISE EXCEPTION 'ASSERTION FAILED: Isolated shard for account_metrics expected on citus_worker_3, found on %',
            v_titan_shard_node;
    END IF;
    RAISE NOTICE 'SUCCESS: Isolated shard for tenant 999 relocated onto dedicated worker node citus_worker_3.';

    -- 3. Assert Data Integrity for Hot Tenant & Standard Tenants
    SELECT count(*) INTO v_titan_metric_count FROM account_metrics WHERE account_id = 999;
    IF v_titan_metric_count != 1000 THEN
        RAISE EXCEPTION 'ASSERTION FAILED: Titan Media metrics count expected 1000, got %', v_titan_metric_count;
    END IF;

    SELECT count(*) INTO v_stark_metric_count FROM account_metrics WHERE account_id = 1;
    IF v_stark_metric_count != 2 THEN
        RAISE EXCEPTION 'ASSERTION FAILED: Stark Tech metrics count expected 2, got %', v_stark_metric_count;
    END IF;
    RAISE NOTICE 'SUCCESS: Data integrity verified post-isolation (Tenant 999: % metrics, Tenant 1: % metrics).',
        v_titan_metric_count, v_stark_metric_count;

    RAISE NOTICE '======================================================================';
    RAISE NOTICE ' ALL 05-TENANT-ISOLATION VERIFICATION ASSERTIONS PASSED!';
    RAISE NOTICE '======================================================================';
END $$;
