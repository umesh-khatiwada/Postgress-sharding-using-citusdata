-- ==============================================================================
-- 04-colocation-and-joins: Verification Assertions
-- ==============================================================================

DO $$
DECLARE
    v_order_colocation integer;
    v_item_colocation integer;
    v_archive_colocation integer;
    v_warehouse_colocation integer;
    v_archived_count integer;
    v_store_1_rev numeric;
    v_store_2_rev numeric;
    v_repartition_count integer;
    v_repartition_failed boolean := false;
BEGIN
    -- 1. Assert Colocation IDs
    SELECT colocation_id INTO v_order_colocation FROM citus_tables WHERE table_name::text = 'store_orders';
    SELECT colocation_id INTO v_item_colocation FROM citus_tables WHERE table_name::text = 'order_items';
    SELECT colocation_id INTO v_archive_colocation FROM citus_tables WHERE table_name::text = 'store_orders_archive';
    SELECT colocation_id INTO v_warehouse_colocation FROM citus_tables WHERE table_name::text = 'warehouse_inventory';

    IF v_order_colocation != v_item_colocation OR v_order_colocation != v_archive_colocation THEN
        RAISE EXCEPTION 'ASSERTION FAILED: Orders, Items, and Archive are NOT co-located! (% vs % vs %)',
            v_order_colocation, v_item_colocation, v_archive_colocation;
    END IF;

    IF v_order_colocation = v_warehouse_colocation THEN
        RAISE EXCEPTION 'ASSERTION FAILED: Warehouse inventory should NOT share colocation ID with orders!';
    END IF;
    RAISE NOTICE 'SUCCESS: Table colocation verified (Colocated: %, Independent: %).', v_order_colocation, v_warehouse_colocation;

    -- 2. Test Repartition Join Behavior with GUC
    SET citus.enable_repartition_joins = 'off';
    BEGIN
        EXECUTE 'SELECT count(*) FROM order_items i JOIN warehouse_inventory w ON i.sku = w.sku' INTO v_repartition_count;
    EXCEPTION WHEN OTHERS THEN
        v_repartition_failed := true;
    END;

    IF NOT v_repartition_failed THEN
        RAISE EXCEPTION 'ASSERTION FAILED: Non-colocated join succeeded while citus.enable_repartition_joins was OFF!';
    END IF;
    RAISE NOTICE 'SUCCESS: Repartition join correctly blocked when citus.enable_repartition_joins = off.';

    -- Enable repartition join and assert execution
    SET citus.enable_repartition_joins = 'on';
    EXECUTE 'SELECT count(*) FROM order_items i JOIN warehouse_inventory w ON i.sku = w.sku' INTO v_repartition_count;
    IF v_repartition_count <= 0 THEN
        RAISE EXCEPTION 'ASSERTION FAILED: Repartition join returned 0 rows when enabled!';
    END IF;
    RAISE NOTICE 'SUCCESS: Repartition join executed via MapMergeJob (returned % rows).', v_repartition_count;
    SET citus.enable_repartition_joins = 'off';

    -- 3. Assert Co-located INSERT..SELECT Execution (12 seed orders + 2 COPY orders = 14)
    SELECT count(*) INTO v_archived_count FROM store_orders_archive;
    IF v_archived_count != 14 THEN
        RAISE EXCEPTION 'ASSERTION FAILED: Expected 14 archived orders, found %', v_archived_count;
    END IF;
    RAISE NOTICE 'SUCCESS: Co-located INSERT..SELECT verified (14 orders archived).';

    -- 4. Assert Distributed Function Execution (Includes seed + COPY orders)
    SELECT calculate_store_revenue(1) INTO v_store_1_rev;
    IF v_store_1_rev != 678.00 THEN
        RAISE EXCEPTION 'ASSERTION FAILED: Store 1 revenue expected 678.00, got %', v_store_1_rev;
    END IF;

    SELECT calculate_store_revenue(2) INTO v_store_2_rev;
    IF v_store_2_rev != 1048.25 THEN
        RAISE EXCEPTION 'ASSERTION FAILED: Store 2 revenue expected 1048.25, got %', v_store_2_rev;
    END IF;
    RAISE NOTICE 'SUCCESS: Distributed function calculate_store_revenue verified (Store 1: %, Store 2: %).',
        v_store_1_rev, v_store_2_rev;

    RAISE NOTICE '======================================================================';
    RAISE NOTICE ' ALL 04-COLOCATION-AND-JOINS ASSERTIONS PASSED!';
    RAISE NOTICE '======================================================================';
END $$;
