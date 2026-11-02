#!/usr/bin/env bash
# ============================================================================
# Example 06: Rebalancing & Scaling - Verification Script
# ============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

echo "=== [06-rebalancing-and-scaling] Starting Test Suite ==="

# 1. Health check coordinator
echo "--> Verifying Citus coordinator connection..."
docker compose exec -T coordinator pg_isready -U postgres -d postgres

# 2. Deploy Schema
echo "--> Applying schema.sql..."
docker compose exec -T coordinator psql -U postgres -d postgres -v ON_ERROR_STOP=1 < "${SCRIPT_DIR}/schema.sql"

# 3. Load Initial Telemetry Data
echo "--> Loading data.sql (12 fleets, 12,000 sensor events)..."
docker compose exec -T coordinator psql -U postgres -d postgres -v ON_ERROR_STOP=1 < "${SCRIPT_DIR}/data.sql"

# 4. Launch Concurrent Writer in background to prove zero/low-downtime shard moves
echo "--> Starting concurrent background writer to prove online shard mobility..."
(
  for i in $(seq 1 40); do
    docker compose exec -T coordinator psql -U postgres -d postgres -c \
      "INSERT INTO sensor_events (fleet_id, event_id, device_id, battery_level, temperature, recorded_at) \
       VALUES (1, 9000000 + $i, 'DEV-WRITER-CONCURRENT', 88.5, 24.1, now()) \
       ON CONFLICT DO NOTHING;" >/dev/null 2>&1 || true
    sleep 0.05
  done
) &
WRITER_PID=$!

# 5. Execute Shard Moves, Splitting, Draining, and Rebalancing
echo "--> Executing queries.sql (manual move, split, drain, restore, rebalance)..."
docker compose exec -T coordinator psql -U postgres -d postgres -v ON_ERROR_STOP=1 < "${SCRIPT_DIR}/queries.sql"

# 6. Wait for concurrent writer to conclude
echo "--> Waiting for background writer to complete..."
wait "${WRITER_PID}" || true

# 7. Run automated assertions
echo "--> Running automated verification assertions..."
docker compose exec -T coordinator psql -U postgres -d postgres -v ON_ERROR_STOP=1 < "${SCRIPT_DIR}/verify.sql"

echo "=== [06-rebalancing-and-scaling] ALL CHECKS PASSED SUCCESSFULLY ==="
