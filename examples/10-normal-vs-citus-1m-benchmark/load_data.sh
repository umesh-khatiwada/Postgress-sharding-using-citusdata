#!/usr/bin/env bash
# ==============================================================================
# Example 10: High-Speed Deterministic Ingestion Script (1M or 10M Rows)
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCALE="${1:-10M}"

case "$SCALE" in
    10M|10m|10000000)
        ROWS=10000000
        ACCOUNTS=50000
        STEP_SECONDS=2
        LABEL="10,000,000 (10M)"
        ;;
    1M|1m|1000000)
        ROWS=1000000
        ACCOUNTS=10000
        STEP_SECONDS=15
        LABEL="1,000,000 (1M)"
        ;;
    *)
        echo "Usage: $0 [1M|10M]"
        exit 1
        ;;
esac

echo "======================================================================"
echo " INGESTION BENCHMARK: Loading ${LABEL} Records"
echo "======================================================================"

# Ensure merchants table exists and has 1,000 records
docker compose exec -T coordinator psql -U postgres -d postgres -c "
INSERT INTO merchants (merchant_id, name, category, country, created_at)
SELECT
    m AS merchant_id,
    'Merchant-' || m AS name,
    (ARRAY['Retail', 'Electronics', 'Groceries', 'Travel', 'Streaming', 'Dining', 'Apparel', 'Healthcare', 'Utilities', 'Entertainment'])[(m % 10) + 1] AS category,
    (ARRAY['USA', 'GBR', 'DEU', 'FRA', 'JPN', 'CAN', 'AUS', 'SGP', 'IND', 'BRA'])[(m % 10) + 1] AS country,
    TIMESTAMP '2025-01-01 00:00:00Z' + (m * INTERVAL '1 hour') AS created_at
FROM generate_series(1, 1000) m
ON CONFLICT (merchant_id) DO NOTHING;
" >/dev/null

echo "--> Truncating existing table data..."
docker compose exec -T coordinator psql -U postgres -d postgres -c "
TRUNCATE normal_transactions;
TRUNCATE citus_transactions;
" >/dev/null

echo "--> Ingesting ${LABEL} rows into Standard PostgreSQL (normal_transactions)..."
START_NORMAL=$(date +%s%N)
docker compose exec -T coordinator psql -U postgres -d postgres -c "
SELECT setseed(0.42);
INSERT INTO normal_transactions (
    transaction_id, account_id, merchant_id, created_at, amount, transaction_type, status
)
SELECT
    i AS transaction_id,
    (i % ${ACCOUNTS}) + 1 AS account_id,
    (i % 1000) + 1 AS merchant_id,
    TIMESTAMP '2026-01-01 00:00:00Z' + (i * INTERVAL '${STEP_SECONDS} seconds') AS created_at,
    ROUND((1.00 + (random() * 999.00))::numeric, 2) AS amount,
    (ARRAY['PURCHASE', 'TRANSFER', 'WITHDRAWAL', 'REFUND'])[(i % 4) + 1] AS transaction_type,
    (ARRAY['SUCCESS', 'PENDING', 'FAILED', 'BLOCKED'])[(i % 4) + 1] AS status
FROM generate_series(1, ${ROWS}) i;
" >/dev/null
END_NORMAL=$(date +%s%N)
NORMAL_ELAPSED_MS=$(( (END_NORMAL - START_NORMAL) / 1000000 ))
NORMAL_RPS=$(( ROWS * 1000 / (NORMAL_ELAPSED_MS > 0 ? NORMAL_ELAPSED_MS : 1) ))
echo "    Normal PG Finished in: ${NORMAL_ELAPSED_MS} ms (~${NORMAL_RPS} rows/sec)"

echo "--> Ingesting ${LABEL} rows into Citus Distributed PostgreSQL (citus_transactions)..."
START_CITUS=$(date +%s%N)
docker compose exec -T coordinator psql -U postgres -d postgres -c "
INSERT INTO citus_transactions
SELECT * FROM normal_transactions;
" >/dev/null
END_CITUS=$(date +%s%N)
CITUS_ELAPSED_MS=$(( (END_CITUS - START_CITUS) / 1000000 ))
CITUS_RPS=$(( ROWS * 1000 / (CITUS_ELAPSED_MS > 0 ? CITUS_ELAPSED_MS : 1) ))
SPEEDUP=$(awk "BEGIN {printf \"%.2f\", ${NORMAL_ELAPSED_MS} / (${CITUS_ELAPSED_MS} > 0 ? ${CITUS_ELAPSED_MS} : 1)}")
echo "    Citus PG Finished in : ${CITUS_ELAPSED_MS} ms (~${CITUS_RPS} rows/sec) ==> Speedup: ${SPEEDUP}x"

echo "--> Running ANALYZE on both tables..."
docker compose exec -T coordinator psql -U postgres -d postgres -c "ANALYZE normal_transactions;" >/dev/null
docker compose exec -T coordinator psql -U postgres -d postgres -c "ANALYZE citus_transactions;" >/dev/null

echo "======================================================================"
echo " Ingestion of ${LABEL} records completed successfully!"
echo "======================================================================"
