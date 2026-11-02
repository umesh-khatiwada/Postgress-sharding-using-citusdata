-- ==============================================================================
-- 04-colocation-and-joins: Demonstrations & Query Plans
-- Authoritative Docs: https://docs.citusdata.com/en/v14.2/performance/query_processing.html
-- ==============================================================================

-- ==============================================================================
-- 1. Inspect Colocation Groups in Citus Metadata
-- ==============================================================================
SELECT 
    c.colocationid,
    c.shardcount,
    c.distributioncolumntype::regtype AS column_type,
    string_agg(p.logicalrelid::text, ', ' ORDER BY p.logicalrelid::text) AS colocated_tables
FROM pg_dist_colocation c
JOIN pg_dist_partition p ON c.colocationid = p.colocationid
WHERE p.logicalrelid::text IN ('store_orders', 'order_items', 'store_orders_archive', 'warehouse_inventory')
GROUP BY c.colocationid, c.shardcount, c.distributioncolumntype;


-- ==============================================================================
-- 2. Single-Store Co-located Join (Router Query)
-- Joins store_orders and order_items on store_id and order_id.
-- Notice: "Task Count: 1" - executes directly on 1 worker with 0 network shuffle!
-- ==============================================================================
EXPLAIN (ANALYZE, VERBOSE)
SELECT 
    o.order_id,
    o.total_amount,
    count(i.item_id) AS total_items,
    sum(i.quantity) AS total_units
FROM store_orders o
JOIN order_items i ON o.store_id = i.store_id AND o.order_id = i.order_id
WHERE o.store_id = 1
GROUP BY o.order_id, o.total_amount
ORDER BY o.order_id;


-- ==============================================================================
-- 3. Parallel Multi-Shard Co-located Join (Scatter-Gather)
-- Aggregates orders and items across all stores without a store_id filter.
-- Notice: Each worker joins its local shards in parallel; coordinator merges summaries.
-- ==============================================================================
EXPLAIN (ANALYZE, VERBOSE)
SELECT 
    o.store_id,
    count(DISTINCT o.order_id) AS orders_count,
    count(i.item_id) AS items_sold,
    sum(i.quantity * i.unit_price) AS gross_merchandise_val
FROM store_orders o
JOIN order_items i ON o.store_id = i.store_id AND o.order_id = i.order_id
GROUP BY o.store_id
ORDER BY o.store_id;


-- ==============================================================================
-- 4. Non-Colocated Join (Repartition Join / MapMergeJob)
-- Joining order_items (sharded on store_id) with warehouse_inventory (sharded on warehouse_id).
-- Because these tables are partitioned on different keys and in different colocation groups,
-- Citus must dynamically repartition tuples across workers using a MapMergeJob!
-- ==============================================================================
SET citus.enable_repartition_joins = 'on';

EXPLAIN (VERBOSE)
SELECT 
    i.sku,
    sum(i.quantity) AS units_sold,
    coalesce(sum(w.quantity_available), 0) AS total_warehouse_stock
FROM order_items i
JOIN warehouse_inventory w ON i.sku = w.sku
GROUP BY i.sku
ORDER BY units_sold DESC;

SET citus.enable_repartition_joins = 'off';


-- ==============================================================================
-- 5. Subquery and Common Table Expression (CTE) Pushdown
-- When a CTE or subquery includes the distribution key, Citus pushes the entire
-- CTE down to the worker node for local evaluation.
-- ==============================================================================
EXPLAIN (ANALYZE, VERBOSE)
WITH high_value_orders AS (
    SELECT store_id, order_id, total_amount
    FROM store_orders
    WHERE store_id = 1 AND total_amount >= 100.00
)
SELECT 
    o.order_id,
    o.total_amount,
    i.sku,
    i.quantity
FROM high_value_orders o
JOIN order_items i ON o.store_id = i.store_id AND o.order_id = i.order_id
ORDER BY o.total_amount DESC;


-- ==============================================================================
-- 6. Parallel Co-located INSERT INTO ... SELECT
-- Archives completed orders directly into the co-located store_orders_archive table.
-- Because source and destination are co-located, each worker executes the INSERT..SELECT
-- locally in parallel without streaming any rows through the coordinator!
-- ==============================================================================
INSERT INTO store_orders_archive (store_id, order_id, total_amount)
SELECT store_id, order_id, total_amount
FROM store_orders
WHERE order_status = 'completed';

-- Verify archived count
SELECT count(*) AS total_archived_orders FROM store_orders_archive;


-- ==============================================================================
-- 7. Distributed Function Execution (create_distributed_function)
-- Calling calculate_store_revenue(store_id) executes directly on the worker holding
-- that store's shard.
-- ==============================================================================
SELECT calculate_store_revenue(1) AS store_1_revenue;
SELECT calculate_store_revenue(2) AS store_2_revenue;
SELECT calculate_store_revenue(3) AS store_3_revenue;
