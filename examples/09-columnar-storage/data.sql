-- ============================================================================
-- Example 09: Columnar Storage
-- Seed Data Generator: Sales Telemetry & Mixed Ledger Records
-- ============================================================================

-- Ensure idempotent execution by truncating tables before seeding
TRUNCATE historical_sales_columnar;
TRUNCATE historical_sales_heap;
TRUNCATE partitioned_order_ledger;

-- 1. Insert 20,000 records into historical_sales_columnar
INSERT INTO historical_sales_columnar (
    store_id, order_id, customer_id, category, quantity, unit_price, total_amount, order_date, status, notes
)
SELECT
    (s.i % 4 + 1) AS store_id,
    s.i AS order_id,
    (s.i % 500 + 1000) AS customer_id,
    CASE (s.i % 5)
        WHEN 0 THEN 'Electronics'
        WHEN 1 THEN 'Furniture'
        WHEN 2 THEN 'Appliances'
        WHEN 3 THEN 'Apparel'
        ELSE 'Groceries'
    END AS category,
    (s.i % 10 + 1) AS quantity,
    ROUND((15.50 + ((s.i * 7) % 450))::numeric, 2) AS unit_price,
    ROUND(((s.i % 10 + 1) * (15.50 + ((s.i * 7) % 450)))::numeric, 2) AS total_amount,
    date '2026-01-01' + ((s.i % 300) || ' days')::interval AS order_date,
    CASE (s.i % 3) WHEN 0 THEN 'COMPLETED' WHEN 1 THEN 'SHIPPED' ELSE 'RETURNED' END AS status,
    repeat('Transactional receipt metadata details with extensive description payload; ', 3) AS notes
FROM generate_series(1, 20000) AS s(i);

-- 2. Insert exact identical 20,000 records into historical_sales_heap
INSERT INTO historical_sales_heap (
    store_id, order_id, customer_id, category, quantity, unit_price, total_amount, order_date, status, notes
)
SELECT
    store_id, order_id, customer_id, category, quantity, unit_price, total_amount, order_date, status, notes
FROM historical_sales_columnar;

-- 3. Populate Mixed Hot/Cold Ledger:
-- 5,000 records into Hot November 2026 Partition (heap)
INSERT INTO partitioned_order_ledger (store_id, order_id, order_date, amount, status, notes)
SELECT
    (s.i % 4 + 1) AS store_id,
    s.i AS order_id,
    date '2026-11-01' + ((s.i % 28) || ' days')::interval AS order_date,
    ROUND((25.00 + (s.i % 350))::numeric, 2) AS amount,
    'ACTIVE' AS status,
    'Hot operational entry' AS notes
FROM generate_series(1, 5000) AS s(i)
ON CONFLICT (store_id, order_date, order_id) DO NOTHING;

-- 5,000 records into Cold October 2026 Partition (columnar)
-- Note: Columnar tables do not support ON CONFLICT speculative insertions; use standard INSERT
INSERT INTO partitioned_order_ledger (store_id, order_id, order_date, amount, status, notes)
SELECT
    (s.i % 4 + 1) AS store_id,
    100000 + s.i AS order_id,
    date '2026-10-01' + ((s.i % 30) || ' days')::interval AS order_date,
    ROUND((25.00 + (s.i % 350))::numeric, 2) AS amount,
    'ARCHIVED' AS status,
    'Cold archived historical entry' AS notes
FROM generate_series(1, 5000) AS s(i);

-- Analyze tables
ANALYZE historical_sales_columnar;
ANALYZE historical_sales_heap;
ANALYZE partitioned_order_ledger;
