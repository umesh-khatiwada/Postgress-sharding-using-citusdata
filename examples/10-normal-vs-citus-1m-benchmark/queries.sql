-- ==============================================================================
-- Example 10: Normal PostgreSQL vs Citus Distributed PostgreSQL (1M Benchmark)
-- Comparative Queries & EXPLAIN ANALYZE Inspection
-- ==============================================================================

-- ------------------------------------------------------------------------------
-- 0. INSPECT SHARD TOPOLOGY & DATA SPREAD IN CITUS
-- ------------------------------------------------------------------------------
\echo '======================================================================'
\echo ' CITUS SHARD PLACEMENT & ROW DISTRIBUTION'
\echo '======================================================================'

SELECT 
    table_name,
    shardid,
    nodename,
    nodeport,
    shard_size
FROM citus_shards
WHERE table_name::text = 'citus_transactions'
ORDER BY shardid;

-- ------------------------------------------------------------------------------
-- 1. FULL TABLE AGGREGATION SCAN (1,000,000 ROWS)
-- Normal: Sequential scan across 1M rows on coordinator.
-- Citus:  Parallel Task execution across all worker shards concurrently.
-- ------------------------------------------------------------------------------
\echo '======================================================================'
\echo ' QUERY 1: Full-Table Aggregation Scan'
\echo '======================================================================'

\echo '--> [Normal Postgres] Full Aggregation:'
SELECT
    count(*) AS total_transactions,
    round(sum(amount), 2) AS total_volume,
    round(avg(amount), 2) AS avg_amount,
    min(amount) AS min_amount,
    max(amount) AS max_amount
FROM normal_transactions;

\echo '--> [Citus Postgres] Distributed Full Aggregation:'
SELECT
    count(*) AS total_transactions,
    round(sum(amount), 2) AS total_volume,
    round(avg(amount), 2) AS avg_amount,
    min(amount) AS min_amount,
    max(amount) AS max_amount
FROM citus_transactions;

-- ------------------------------------------------------------------------------
-- 2. DIMENSION GROUPED AGGREGATION
-- Normal: Sort / HashAggregate on single machine.
-- Citus:  Partial aggregates pushed down to worker nodes; tiny result sets
--         merged on coordinator.
-- ------------------------------------------------------------------------------
\echo '======================================================================'
\echo ' QUERY 2: Dimension Grouped Aggregation'
\echo '======================================================================'

\echo '--> [Normal Postgres] Grouped Aggregation:'
SELECT
    transaction_type,
    status,
    count(*) AS tx_count,
    round(sum(amount), 2) AS total_amount,
    round(avg(amount), 2) AS avg_amount
FROM normal_transactions
GROUP BY transaction_type, status
ORDER BY total_amount DESC;

\echo '--> [Citus Postgres] Distributed Grouped Aggregation:'
SELECT
    transaction_type,
    status,
    count(*) AS tx_count,
    round(sum(amount), 2) AS total_amount,
    round(avg(amount), 2) AS avg_amount
FROM citus_transactions
GROUP BY transaction_type, status
ORDER BY total_amount DESC;

-- ------------------------------------------------------------------------------
-- 3. HIGH-CARDINALITY FILTERED AGGREGATION (TOP MERCHANTS)
-- Filters 1M rows down to 'SUCCESS' in date range, aggregates by 1,000 merchants.
-- ------------------------------------------------------------------------------
\echo '======================================================================'
\echo ' QUERY 3: High-Cardinality Filtered Aggregation (Top 10 Merchants)'
\echo '======================================================================'

\echo '--> [Normal Postgres] Top Merchants:'
SELECT
    merchant_id,
    count(*) AS successful_txs,
    round(sum(amount), 2) AS gross_sales
FROM normal_transactions
WHERE status = 'SUCCESS' 
  AND created_at >= TIMESTAMP '2026-03-01 00:00:00Z'
GROUP BY merchant_id
ORDER BY gross_sales DESC
LIMIT 10;

\echo '--> [Citus Postgres] Distributed Top Merchants:'
SELECT
    merchant_id,
    count(*) AS successful_txs,
    round(sum(amount), 2) AS gross_sales
FROM citus_transactions
WHERE status = 'SUCCESS' 
  AND created_at >= TIMESTAMP '2026-03-01 00:00:00Z'
GROUP BY merchant_id
ORDER BY gross_sales DESC
LIMIT 10;

-- ------------------------------------------------------------------------------
-- 4. DISTRIBUTED REFERENCE TABLE JOIN (Zero-Shuffle Join)
-- Normal: Standard Hash Join between transactions and merchants.
-- Citus:  Merchants is a Reference Table (replicated on all workers).
--         Workers execute the join locally with zero network cross-talk!
-- ------------------------------------------------------------------------------
\echo '======================================================================'
\echo ' QUERY 4: Distributed Reference Table Join (Category Revenue)'
\echo '======================================================================'

\echo '--> [Normal Postgres] Join:'
SELECT
    m.category,
    count(t.transaction_id) AS total_orders,
    round(sum(t.amount), 2) AS category_revenue,
    round(avg(t.amount), 2) AS avg_basket_size
FROM normal_transactions t
JOIN merchants m ON t.merchant_id = m.merchant_id
WHERE t.status = 'SUCCESS'
GROUP BY m.category
ORDER BY category_revenue DESC;

\echo '--> [Citus Postgres] Distributed Reference Table Join:'
SELECT
    m.category,
    count(t.transaction_id) AS total_orders,
    round(sum(t.amount), 2) AS category_revenue,
    round(avg(t.amount), 2) AS avg_basket_size
FROM citus_transactions t
JOIN merchants m ON t.merchant_id = m.merchant_id
WHERE t.status = 'SUCCESS'
GROUP BY m.category
ORDER BY category_revenue DESC;

-- ------------------------------------------------------------------------------
-- 5. POINT / ROUTER QUERY (Tenant / Account Lookup)
-- Citus uses the Router Planner to send the query directly to the 1 shard
-- containing account_id = 4250, bypassing all other shards.
-- ------------------------------------------------------------------------------
\echo '======================================================================'
\echo ' QUERY 5: Point / Router Query (Account 4250 Recent Transactions)'
\echo '======================================================================'

\echo '--> [Normal Postgres] Point Lookup:'
SELECT
    transaction_id,
    account_id,
    created_at,
    amount,
    transaction_type,
    status
FROM normal_transactions
WHERE account_id = 4250
ORDER BY created_at DESC
LIMIT 10;

\echo '--> [Citus Postgres] Distributed Router Query:'
SELECT
    transaction_id,
    account_id,
    created_at,
    amount,
    transaction_type,
    status
FROM citus_transactions
WHERE account_id = 4250
ORDER BY created_at DESC
LIMIT 10;

-- ------------------------------------------------------------------------------
-- 6. DISTINCT COUNT & TIME BUCKETING
-- Grouping by month and counting unique accounts.
-- ------------------------------------------------------------------------------
\echo '======================================================================'
\echo ' QUERY 6: Monthly Distinct Accounts & Volume'
\echo '======================================================================'

\echo '--> [Normal Postgres] Monthly Summary:'
SELECT
    date_trunc('month', created_at) AS tx_month,
    count(DISTINCT account_id) AS active_accounts,
    count(*) AS total_txs,
    round(sum(amount), 2) AS monthly_volume
FROM normal_transactions
GROUP BY date_trunc('month', created_at)
ORDER BY tx_month;

\echo '--> [Citus Postgres] Distributed Monthly Summary:'
SELECT
    date_trunc('month', created_at) AS tx_month,
    count(DISTINCT account_id) AS active_accounts,
    count(*) AS total_txs,
    round(sum(amount), 2) AS monthly_volume
FROM citus_transactions
GROUP BY date_trunc('month', created_at)
ORDER BY tx_month;

-- ------------------------------------------------------------------------------
-- 7. CROSS-BORDER ANALYTICAL FILTER & TOP SPEND
-- Filters by amount threshold (> $700) and joins with Country.
-- ------------------------------------------------------------------------------
\echo '======================================================================'
\echo ' QUERY 7: Cross-Border Country Volume (> $700 Transactions)'
\echo '======================================================================'

\echo '--> [Normal Postgres] Cross-Border Volume:'
SELECT
    m.country,
    t.transaction_type,
    count(*) AS high_value_count,
    round(sum(t.amount), 2) AS total_spend,
    round(max(t.amount), 2) AS peak_amount
FROM normal_transactions t
JOIN merchants m ON t.merchant_id = m.merchant_id
WHERE t.amount > 700.00 
  AND t.status IN ('SUCCESS', 'PENDING')
GROUP BY m.country, t.transaction_type
ORDER BY total_spend DESC
LIMIT 10;

\echo '--> [Citus Postgres] Distributed Cross-Border Volume:'
SELECT
    m.country,
    t.transaction_type,
    count(*) AS high_value_count,
    round(sum(t.amount), 2) AS total_spend,
    round(max(t.amount), 2) AS peak_amount
FROM citus_transactions t
JOIN merchants m ON t.merchant_id = m.merchant_id
WHERE t.amount > 700.00 
  AND t.status IN ('SUCCESS', 'PENDING')
GROUP BY m.country, t.transaction_type
ORDER BY total_spend DESC
LIMIT 10;

-- ------------------------------------------------------------------------------
-- 8. STATISTICAL PERCENTILES (Median, P95, P99)
-- ------------------------------------------------------------------------------
\echo '======================================================================'
\echo ' QUERY 8: Percentile Distribution (Median, P95, P99)'
\echo '======================================================================'

\echo '--> [Normal Postgres] Percentiles:'
SELECT
    round(percentile_cont(0.50) WITHIN GROUP (ORDER BY amount)::numeric, 2) AS median_amount,
    round(percentile_cont(0.95) WITHIN GROUP (ORDER BY amount)::numeric, 2) AS p95_amount,
    round(percentile_cont(0.99) WITHIN GROUP (ORDER BY amount)::numeric, 2) AS p99_amount
FROM normal_transactions
WHERE created_at >= TIMESTAMP '2026-03-01 00:00:00Z';

\echo '--> [Citus Postgres] Distributed Percentiles:'
SELECT
    round(percentile_cont(0.50) WITHIN GROUP (ORDER BY amount)::numeric, 2) AS median_amount,
    round(percentile_cont(0.95) WITHIN GROUP (ORDER BY amount)::numeric, 2) AS p95_amount,
    round(percentile_cont(0.99) WITHIN GROUP (ORDER BY amount)::numeric, 2) AS p99_amount
FROM citus_transactions
WHERE created_at >= TIMESTAMP '2026-03-01 00:00:00Z';

-- ------------------------------------------------------------------------------
-- 9. EXPLAIN ANALYZE COMPARISON FOR QUERY 1 & QUERY 4
-- ------------------------------------------------------------------------------
\echo '======================================================================'
\echo ' EXPLAIN (ANALYZE, BUFFERS) - QUERY 1 (Full Aggregation)'
\echo '======================================================================'

\echo '--> Normal PostgreSQL Query Plan:'
EXPLAIN (ANALYZE, BUFFERS)
SELECT count(*), round(sum(amount), 2), round(avg(amount), 2)
FROM normal_transactions;

\echo '--> Citus Distributed Query Plan:'
EXPLAIN (ANALYZE, BUFFERS)
SELECT count(*), round(sum(amount), 2), round(avg(amount), 2)
FROM citus_transactions;

\echo '======================================================================'
\echo ' EXPLAIN (ANALYZE, BUFFERS) - QUERY 4 (Reference Table Join)'
\echo '======================================================================'

\echo '--> Normal PostgreSQL Query Plan:'
EXPLAIN (ANALYZE, BUFFERS)
SELECT m.category, count(*), round(sum(t.amount), 2)
FROM normal_transactions t
JOIN merchants m ON t.merchant_id = m.merchant_id
WHERE t.status = 'SUCCESS'
GROUP BY m.category;

\echo '--> Citus Distributed Query Plan:'
EXPLAIN (ANALYZE, BUFFERS)
SELECT m.category, count(*), round(sum(t.amount), 2)
FROM citus_transactions t
JOIN merchants m ON t.merchant_id = m.merchant_id
WHERE t.status = 'SUCCESS'
GROUP BY m.category;
