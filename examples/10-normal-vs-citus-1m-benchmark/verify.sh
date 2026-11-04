#!/usr/bin/env bash
# ==============================================================================
# Example 10: Normal PostgreSQL vs Citus Distributed PostgreSQL (1M Benchmark)
# Automated Test & Verification Suite
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

echo "=== [10-normal-vs-citus-1m-benchmark] Starting Test Suite ==="

# 1. Health check coordinator
echo "--> Verifying Citus coordinator connection..."
docker compose exec -T coordinator pg_isready -U postgres -d postgres

# 2. Deploy Schema
echo "--> Applying schema.sql (normal table, reference table, Citus distributed table with 8 shards)..."
docker compose exec -T coordinator psql -U postgres -d postgres -v ON_ERROR_STOP=1 < "${SCRIPT_DIR}/schema.sql"

# 3. Populate 1,000,000 rows
echo "--> Ingesting 1,000,000 rows into normal and Citus distributed tables (data.sql)..."
docker compose exec -T coordinator psql -U postgres -d postgres -v ON_ERROR_STOP=1 < "${SCRIPT_DIR}/data.sql"

# 4. Run automated assertions
echo "--> Running verification assertions (verify.sql)..."
docker compose exec -T coordinator psql -U postgres -d postgres -v ON_ERROR_STOP=1 < "${SCRIPT_DIR}/verify.sql"

echo "=== [10-normal-vs-citus-1m-benchmark] ALL CHECKS PASSED SUCCESSFULLY ==="
