#!/usr/bin/env bash
# ============================================================================
# Example 07: Real-Time Analytics - Verification Script
# ============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

echo "=== [07-realtime-analytics] Starting Test Suite ==="

# 1. Health check coordinator
echo "--> Verifying Citus coordinator connection..."
docker compose exec -T coordinator pg_isready -U postgres -d postgres

# 2. Deploy Schema
echo "--> Applying schema.sql (raw events & hourly rollup tables with HLL and TopN)..."
docker compose exec -T coordinator psql -U postgres -d postgres -v ON_ERROR_STOP=1 < "${SCRIPT_DIR}/schema.sql"

# 3. Load Seed Event Telemetry
echo "--> Ingesting 20,000 real-time events via data.sql..."
docker compose exec -T coordinator psql -U postgres -d postgres -v ON_ERROR_STOP=1 < "${SCRIPT_DIR}/data.sql"

# 4. Execute Demonstration Queries (Parallel aggs, incremental rollups, HLL/TopN queries)
echo "--> Executing queries.sql (distributed aggregations, rollups, and accuracy checks)..."
docker compose exec -T coordinator psql -U postgres -d postgres -v ON_ERROR_STOP=1 < "${SCRIPT_DIR}/queries.sql"

# 5. Run Automated Assertions
echo "--> Running automated verification assertions..."
docker compose exec -T coordinator psql -U postgres -d postgres -v ON_ERROR_STOP=1 < "${SCRIPT_DIR}/verify.sql"

echo "=== [07-realtime-analytics] ALL CHECKS PASSED SUCCESSFULLY ==="
