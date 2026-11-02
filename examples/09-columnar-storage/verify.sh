#!/usr/bin/env bash
# ============================================================================
# Example 09: Columnar Storage - Verification Script
# ============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

echo "=== [09-columnar-storage] Starting Test Suite ==="

# 1. Health check coordinator
echo "--> Verifying Citus coordinator connection..."
docker compose exec -T coordinator pg_isready -U postgres -d postgres

# 2. Ensure citus_columnar extension is present on all nodes
echo "--> Ensuring citus_columnar extension is loaded across coordinator and worker nodes..."
for node in coordinator worker-1 worker-2 worker-3; do
  docker compose exec -T "$node" psql -U postgres -d postgres -c \
    "SET citus.enable_ddl_propagation = off; CREATE EXTENSION IF NOT EXISTS citus_columnar;" >/dev/null 2>&1 || true
done

# 3. Deploy Schema
echo "--> Applying schema.sql (columnar, heap, and mixed hot/cold partitioned tables)..."
docker compose exec -T coordinator psql -U postgres -d postgres -v ON_ERROR_STOP=1 < "${SCRIPT_DIR}/schema.sql"

# 4. Load Seed Data
echo "--> Ingesting 20,000 sales records and 10,000 ledger records via data.sql..."
docker compose exec -T coordinator psql -U postgres -d postgres -v ON_ERROR_STOP=1 < "${SCRIPT_DIR}/data.sql"

# 5. Execute Demonstration Queries
echo "--> Executing queries.sql (storage footprint, columnar scans, hot/cold operations)..."
docker compose exec -T coordinator psql -U postgres -d postgres -v ON_ERROR_STOP=1 < "${SCRIPT_DIR}/queries.sql"

# 6. Run Automated Assertions
echo "--> Running automated verification assertions..."
docker compose exec -T coordinator psql -U postgres -d postgres -v ON_ERROR_STOP=1 < "${SCRIPT_DIR}/verify.sql"

echo "=== [09-columnar-storage] ALL CHECKS PASSED SUCCESSFULLY ==="
