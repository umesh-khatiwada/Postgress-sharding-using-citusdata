-- ============================================================================
-- Example 09: Columnar Storage
-- Demonstration Queries: Benchmarks, Projections, and Hot/Cold Partitions
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. Inspect Columnar Storage Options and Compression Metadata
-- ----------------------------------------------------------------------------
SELECT
    relation,
    chunk_group_row_limit,
    stripe_row_limit,
    compression,
    compression_level
FROM columnar.options
WHERE relation::text IN ('historical_sales_columnar', 'ledger_cold_2026_10');

-- ----------------------------------------------------------------------------
-- 2. Storage Footprint Comparison (Heap vs Columnar with zstd)
-- ----------------------------------------------------------------------------
SELECT
    'historical_sales_heap' AS storage_format,
    pg_size_pretty(citus_table_size('historical_sales_heap')) AS formatted_size,
    citus_table_size('historical_sales_heap') AS bytes
UNION ALL
SELECT
    'historical_sales_columnar' AS storage_format,
    pg_size_pretty(citus_table_size('historical_sales_columnar')) AS formatted_size,
    citus_table_size('historical_sales_columnar') AS bytes;

-- Calculate Compression Ratio
SELECT
    round(
        citus_table_size('historical_sales_heap')::numeric /
        NULLIF(citus_table_size('historical_sales_columnar'), 0)::numeric,
        2
    ) AS compression_ratio_x;

-- ----------------------------------------------------------------------------
-- 3. Analytical Scan on Columnar Table (Projection Elimination in EXPLAIN)
-- ----------------------------------------------------------------------------
-- ColumnarScan reads ONLY the requested columns (category, quantity, unit_price, total_amount),
-- skipping large textual notes and unused IDs completely from disk I/O.
EXPLAIN (ANALYZE, VERBOSE)
SELECT
    category,
    sum(quantity) AS total_quantity,
    sum(total_amount) AS total_revenue,
    round(avg(unit_price), 2) AS avg_price
FROM historical_sales_columnar
GROUP BY category
ORDER BY total_revenue DESC;

-- ----------------------------------------------------------------------------
-- 4. Analytical Scan on Heap Table (Full Row Decode Comparison)
-- ----------------------------------------------------------------------------
EXPLAIN (ANALYZE, VERBOSE)
SELECT
    category,
    sum(quantity) AS total_quantity,
    sum(total_amount) AS total_revenue,
    round(avg(unit_price), 2) AS avg_price
FROM historical_sales_heap
GROUP BY category
ORDER BY total_revenue DESC;

-- ----------------------------------------------------------------------------
-- 5. Unified Query Over Mixed Hot (Heap) and Cold (Columnar) Partitions
-- ----------------------------------------------------------------------------
-- Citus and PostgreSQL transparently query across both storage formats in a
-- single query plan.
EXPLAIN (ANALYZE, VERBOSE)
SELECT
    date_trunc('month', order_date)::date AS ledger_month,
    status,
    count(*) AS total_orders,
    sum(amount) AS total_amount
FROM partitioned_order_ledger
GROUP BY 1, 2
ORDER BY 1, 2;

-- ----------------------------------------------------------------------------
-- 6. Hot vs Cold Partition Mutability Demonstration
-- ----------------------------------------------------------------------------
-- Active Hot Partition (heap) allows singleton updates:
UPDATE partitioned_order_ledger
SET status = 'PROCESSED'
WHERE store_id = 1 AND order_date = '2026-11-05' AND order_id = 4;

SELECT store_id, order_id, order_date, status
FROM partitioned_order_ledger
WHERE store_id = 1 AND order_date = '2026-11-05' AND order_id = 4;
