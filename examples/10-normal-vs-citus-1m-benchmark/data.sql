-- ==============================================================================
-- Example 10: Normal PostgreSQL vs Citus Distributed PostgreSQL (1M Benchmark)
-- Seed Data Generator (1,000 Merchants + 1,000,000 Transactions)
-- ==============================================================================

-- 1. Populate Dimension / Reference Table: merchants (1,000 records)
INSERT INTO merchants (merchant_id, name, category, country, created_at)
SELECT
    m AS merchant_id,
    'Merchant-' || m AS name,
    (ARRAY[
        'Retail', 'Electronics', 'Groceries', 'Travel', 'Streaming',
        'Dining', 'Apparel', 'Healthcare', 'Utilities', 'Entertainment'
    ])[(m % 10) + 1] AS category,
    (ARRAY['USA', 'GBR', 'DEU', 'FRA', 'JPN', 'CAN', 'AUS', 'SGP', 'IND', 'BRA'])[(m % 10) + 1] AS country,
    TIMESTAMP '2025-01-01 00:00:00Z' + (m * INTERVAL '1 hour') AS created_at
FROM generate_series(1, 1000) m
ON CONFLICT (merchant_id) DO NOTHING;

-- 2. Populate Normal Postgres Baseline Table with 1,000,000 Rows
--    Deterministic pseudo-random distribution using fixed seed
SELECT setseed(0.42);

INSERT INTO normal_transactions (
    transaction_id, account_id, merchant_id, created_at, amount, transaction_type, status
)
SELECT
    i AS transaction_id,
    (i % 10000) + 1 AS account_id,
    (i % 1000) + 1 AS merchant_id,
    TIMESTAMP '2026-01-01 00:00:00Z' + (i * INTERVAL '15 seconds') AS created_at,
    ROUND((1.00 + (random() * 999.00))::numeric, 2) AS amount,
    (ARRAY['PURCHASE', 'TRANSFER', 'WITHDRAWAL', 'REFUND'])[(i % 4) + 1] AS transaction_type,
    (ARRAY['SUCCESS', 'PENDING', 'FAILED', 'BLOCKED'])[(i % 4) + 1] AS status
FROM generate_series(1, 1000000) i;

-- 3. Ingest the Exact Same 1,000,000 Rows into Citus Distributed Table
--    Citus router partitions incoming rows by hash(account_id) and pushes them
--    in parallel streams across all worker shards.
INSERT INTO citus_transactions
SELECT * FROM normal_transactions;

-- 4. Update optimizer statistics on both tables
VACUUM ANALYZE merchants;
VACUUM ANALYZE normal_transactions;
VACUUM ANALYZE citus_transactions;
