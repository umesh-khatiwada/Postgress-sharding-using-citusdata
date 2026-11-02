#!/usr/bin/env bash
# ==============================================================================
# 05-tenant-isolation: Verification Runner Script
# ==============================================================================

set -euo pipefail

COORDINATOR=${COORDINATOR_CONTAINER:-citus_coordinator}
POSTGRES_USER=${POSTGRES_USER:-postgres}
POSTGRES_DB=${POSTGRES_DB:-postgres}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "==> [05-tenant-isolation] Applying schema and enabling tenant statistics tracking..."
docker exec -i "$COORDINATOR" psql -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d "$POSTGRES_DB" < "${SCRIPT_DIR}/schema.sql"

echo "==> [05-tenant-isolation] Seeding normal accounts and noisy neighbor dataset..."
docker exec -i "$COORDINATOR" psql -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d "$POSTGRES_DB" < "${SCRIPT_DIR}/data.sql"

echo "==> [05-tenant-isolation] Running demonstrations (hot tenant detection, shard isolation, node move)..."
docker exec -i "$COORDINATOR" psql -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d "$POSTGRES_DB" < "${SCRIPT_DIR}/queries.sql"

echo "==> [05-tenant-isolation] Running automated verification assertions..."
docker exec -i "$COORDINATOR" psql -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d "$POSTGRES_DB" < "${SCRIPT_DIR}/verify.sql"

echo "==> [05-tenant-isolation] PASSED: All tenant isolation tests passed successfully."
