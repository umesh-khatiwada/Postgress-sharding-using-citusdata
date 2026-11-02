#!/usr/bin/env bash
# ============================================================================
# Example 08: Time-Series Partitioning - Verification Script
# ============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

echo "=== [08-timeseries-partitioning] Starting Test Suite ==="

# 1. Health check coordinator
echo "--> Verifying Citus coordinator connection..."
docker compose exec -T coordinator pg_isready -U postgres -d postgres

# 2. Deploy Schema & Automated Partitions
echo "--> Applying schema.sql (declarative partitioning + create_time_partitions)..."
docker compose exec -T coordinator psql -U postgres -d postgres -v ON_ERROR_STOP=1 < "${SCRIPT_DIR}/schema.sql"

# 3. Load Seed Telemetry Data
echo "--> Ingesting 16,000 multi-day metrics via data.sql..."
docker compose exec -T coordinator psql -U postgres -d postgres -v ON_ERROR_STOP=1 < "${SCRIPT_DIR}/data.sql"

# 4. Execute Demonstration Queries
echo "--> Executing queries.sql (partition inspection, pruning in EXPLAIN, retention cleanup)..."
docker compose exec -T coordinator psql -U postgres -d postgres -v ON_ERROR_STOP=1 < "${SCRIPT_DIR}/queries.sql"

# 5. Run Automated Assertions
echo "--> Running automated verification assertions..."
docker compose exec -T coordinator psql -U postgres -d postgres -v ON_ERROR_STOP=1 < "${SCRIPT_DIR}/verify.sql"

echo "=== [08-timeseries-partitioning] ALL CHECKS PASSED SUCCESSFULLY ==="
