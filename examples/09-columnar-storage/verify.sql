-- ============================================================================
-- Example 09: Columnar Storage
-- Automated Verification Assertions
-- ============================================================================

DO $$
DECLARE
    v_heap_size bigint;
    v_columnar_size bigint;
    v_columnar_rows bigint;
    v_heap_rows bigint;
    v_ledger_rows bigint;
    v_hot_am text;
    v_cold_am text;
    v_updated_status text;
BEGIN
    RAISE NOTICE '------------------------------------------------------------';
    RAISE NOTICE 'Running Verification Suite: 09-columnar-storage';
    RAISE NOTICE '------------------------------------------------------------';

    -- 1. Verify distributed table registration
    IF NOT EXISTS (SELECT 1 FROM citus_tables WHERE table_name = 'historical_sales_columnar'::regclass) THEN
        RAISE EXCEPTION 'ASSERTION FAILED: Table historical_sales_columnar is not distributed';
    END IF;

    IF NOT EXISTS (SELECT 1 FROM citus_tables WHERE table_name = 'historical_sales_heap'::regclass) THEN
        RAISE EXCEPTION 'ASSERTION FAILED: Table historical_sales_heap is not distributed';
    END IF;

    IF NOT EXISTS (SELECT 1 FROM citus_tables WHERE table_name = 'partitioned_order_ledger'::regclass) THEN
        RAISE EXCEPTION 'ASSERTION FAILED: Table partitioned_order_ledger is not distributed';
    END IF;
    RAISE NOTICE '[PASS] All tables registered as distributed relations in Citus';

    -- 2. Verify Access Method configuration on hot vs cold partitions
    SELECT a.amname INTO v_hot_am
    FROM pg_class c JOIN pg_am a ON a.oid = c.relam
    WHERE c.relname = 'ledger_hot_2026_11';

    SELECT a.amname INTO v_cold_am
    FROM pg_class c JOIN pg_am a ON a.oid = c.relam
    WHERE c.relname = 'ledger_cold_2026_10';

    IF v_hot_am <> 'heap' OR v_cold_am <> 'columnar' THEN
        RAISE EXCEPTION 'ASSERTION FAILED: Expected hot=heap, cold=columnar. Found hot=%, cold=%', v_hot_am, v_cold_am;
    END IF;
    RAISE NOTICE '[PASS] Mixed partition storage verified: Hot partition uses %, Cold partition uses %', v_hot_am, v_cold_am;

    -- 3. Verify Row Count Parity
    SELECT count(*) INTO v_columnar_rows FROM historical_sales_columnar;
    SELECT count(*) INTO v_heap_rows FROM historical_sales_heap;
    SELECT count(*) INTO v_ledger_rows FROM partitioned_order_ledger;

    IF v_columnar_rows <> 20000 OR v_heap_rows <> 20000 THEN
        RAISE EXCEPTION 'ASSERTION FAILED: Expected 20,000 rows in both tables. Found columnar=%, heap=%',
            v_columnar_rows, v_heap_rows;
    END IF;

    IF v_ledger_rows <> 10000 THEN
        RAISE EXCEPTION 'ASSERTION FAILED: Expected 10,000 rows in partitioned ledger. Found %', v_ledger_rows;
    END IF;
    RAISE NOTICE '[PASS] Row count parity verified: Columnar=%, Heap=%, Ledger=%',
        v_columnar_rows, v_heap_rows, v_ledger_rows;

    -- 4. Verify Compression Ratio
    v_heap_size := citus_table_size('historical_sales_heap');
    v_columnar_size := citus_table_size('historical_sales_columnar');

    IF v_columnar_size >= v_heap_size THEN
        RAISE EXCEPTION 'ASSERTION FAILED: Columnar size (%) is not smaller than Heap size (%)',
            v_columnar_size, v_heap_size;
    END IF;
    RAISE NOTICE '[PASS] Columnar compression confirmed: Heap=% bytes vs Columnar=% bytes (Compression Ratio: %x)',
        v_heap_size, v_columnar_size, round(v_heap_size::numeric / v_columnar_size::numeric, 2);

    -- 5. Verify Hot Partition Mutation
    SELECT status INTO v_updated_status
    FROM partitioned_order_ledger
    WHERE store_id = 1 AND order_date = '2026-11-05' AND order_id = 4;

    IF v_updated_status <> 'PROCESSED' THEN
        RAISE EXCEPTION 'ASSERTION FAILED: Expected status PROCESSED on updated hot row, found %', v_updated_status;
    END IF;
    RAISE NOTICE '[PASS] Hot heap partition mutation successfully verified';

    RAISE NOTICE '------------------------------------------------------------';
    RAISE NOTICE 'ALL VERIFICATION ASSERTIONS PASSED FOR EXAMPLE 09';
    RAISE NOTICE '------------------------------------------------------------';
END $$;
