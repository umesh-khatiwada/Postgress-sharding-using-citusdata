-- ==============================================================================
-- Example 10: Normal PostgreSQL vs Citus Distributed PostgreSQL (1M Benchmark)
-- Verification Test Suite & Assertions
-- ==============================================================================

DO $$
DECLARE
    v_normal_count BIGINT;
    v_citus_count BIGINT;
    v_merchants_count BIGINT;
    v_shard_count INT;
    v_worker_count INT;
    v_normal_sum NUMERIC(14,2);
    v_citus_sum NUMERIC(14,2);
    v_mismatches INT;
BEGIN
    RAISE NOTICE '======================================================================';
    RAISE NOTICE ' RUNNING VERIFICATION ASSERTIONS FOR EXAMPLE 10 (1M BENCHMARK)';
    RAISE NOTICE '======================================================================';

    -- 1. Verify Row Counts in Tables
    SELECT count(*) INTO v_normal_count FROM normal_transactions;
    SELECT count(*) INTO v_citus_count FROM citus_transactions;
    SELECT count(*) INTO v_merchants_count FROM merchants;

    IF v_normal_count NOT IN (1000000, 10000000) THEN
        RAISE EXCEPTION 'Assertion Failed: normal_transactions has % rows, expected 1,000,000 or 10,000,000', v_normal_count;
    END IF;
    RAISE NOTICE 'SUCCESS: normal_transactions contains exactly % rows.', to_char(v_normal_count, 'FM999,999,999');

    IF v_citus_count <> v_normal_count THEN
        RAISE EXCEPTION 'Assertion Failed: Row count mismatch! Normal=%, Citus=%', v_normal_count, v_citus_count;
    END IF;
    RAISE NOTICE 'SUCCESS: citus_transactions matches normal table with exactly % rows.', to_char(v_citus_count, 'FM999,999,999');

    IF v_merchants_count <> 1000 THEN
        RAISE EXCEPTION 'Assertion Failed: merchants has % rows, expected 1,000', v_merchants_count;
    END IF;
    RAISE NOTICE 'SUCCESS: merchants reference table contains exactly 1,000 rows.';

    -- 2. Verify Citus Metadata and Shard Distribution
    SELECT count(DISTINCT shardid) INTO v_shard_count
    FROM citus_shards
    WHERE table_name::text = 'citus_transactions';

    IF v_shard_count < 8 THEN
        RAISE EXCEPTION 'Assertion Failed: citus_transactions shard count is %, expected at least 8', v_shard_count;
    END IF;
    RAISE NOTICE 'SUCCESS: citus_transactions has % distributed shards.', v_shard_count;

    SELECT count(DISTINCT nodename) INTO v_worker_count
    FROM citus_shards
    WHERE table_name::text = 'citus_transactions';

    IF v_worker_count < 2 THEN
        RAISE EXCEPTION 'Assertion Failed: citus_transactions only placed on % nodes, expected at least 2', v_worker_count;
    END IF;
    RAISE NOTICE 'SUCCESS: citus_transactions shards are distributed across % active worker nodes.', v_worker_count;

    -- 3. Verify Exact Total Volume (Sum of amount) Match
    SELECT round(sum(amount), 2) INTO v_normal_sum FROM normal_transactions;
    SELECT round(sum(amount), 2) INTO v_citus_sum FROM citus_transactions;

    IF v_normal_sum <> v_citus_sum THEN
        RAISE EXCEPTION 'Assertion Failed: Total amount mismatch! Normal=%, Citus=%', v_normal_sum, v_citus_sum;
    END IF;
    RAISE NOTICE 'SUCCESS: Total transaction volume matches to the exact penny: $%', v_citus_sum;

    -- 4. Verify Dimension Aggregation Groupings Match Exactly
    WITH normal_agg AS (
        SELECT transaction_type, status, count(*) AS cnt, round(sum(amount), 2) AS sm
        FROM normal_transactions
        GROUP BY transaction_type, status
    ),
    citus_agg AS (
        SELECT transaction_type, status, count(*) AS cnt, round(sum(amount), 2) AS sm
        FROM citus_transactions
        GROUP BY transaction_type, status
    )
    SELECT count(*) INTO v_mismatches
    FROM normal_agg n
    FULL OUTER JOIN citus_agg c 
      ON n.transaction_type = c.transaction_type AND n.status = c.status
    WHERE n.cnt IS DISTINCT FROM c.cnt OR n.sm IS DISTINCT FROM c.sm;

    IF v_mismatches > 0 THEN
        RAISE EXCEPTION 'Assertion Failed: % group aggregations differed between normal and citus tables!', v_mismatches;
    END IF;
    RAISE NOTICE 'SUCCESS: Dimension grouped aggregates (type x status) match 100%% identically.';

    -- 5. Verify Distributed Reference Table Join Results Match
    WITH normal_join AS (
        SELECT m.category, count(t.transaction_id) AS cnt, round(sum(t.amount), 2) AS vol
        FROM normal_transactions t
        JOIN merchants m ON t.merchant_id = m.merchant_id
        WHERE t.status = 'SUCCESS'
        GROUP BY m.category
    ),
    citus_join AS (
        SELECT m.category, count(t.transaction_id) AS cnt, round(sum(t.amount), 2) AS vol
        FROM citus_transactions t
        JOIN merchants m ON t.merchant_id = m.merchant_id
        WHERE t.status = 'SUCCESS'
        GROUP BY m.category
    )
    SELECT count(*) INTO v_mismatches
    FROM normal_join n
    FULL OUTER JOIN citus_join c ON n.category = c.category
    WHERE n.cnt IS DISTINCT FROM c.cnt OR n.vol IS DISTINCT FROM c.vol;

    IF v_mismatches > 0 THEN
        RAISE EXCEPTION 'Assertion Failed: % category join results differed!', v_mismatches;
    END IF;
    RAISE NOTICE 'SUCCESS: Distributed reference table joins match 100%% identically.';

    RAISE NOTICE '======================================================================';
    RAISE NOTICE ' ALL VERIFICATION ASSERTIONS PASSED FOR EXAMPLE 10';
    RAISE NOTICE '======================================================================';
END $$;
