#!/usr/bin/env bash
# ==============================================================================
# 02-schema-based-multitenant: Verification Runner Script
# ==============================================================================

set -euo pipefail

COORDINATOR=${COORDINATOR_CONTAINER:-citus_coordinator}
POSTGRES_USER=${POSTGRES_USER:-postgres}
POSTGRES_DB=${POSTGRES_DB:-postgres}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "==> [02-schema-based-multitenant] Applying schema-based sharding configuration and tables..."
docker exec -i "$COORDINATOR" psql -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d "$POSTGRES_DB" < "${SCRIPT_DIR}/schema.sql"

echo "==> [02-schema-based-multitenant] Seeding multi-tenant data across schemas..."
docker exec -i "$COORDINATOR" psql -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d "$POSTGRES_DB" < "${SCRIPT_DIR}/data.sql"

echo "==> [02-schema-based-multitenant] Running query demonstrations (routing, moves, undistribute)..."
docker exec -i "$COORDINATOR" psql -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d "$POSTGRES_DB" < "${SCRIPT_DIR}/queries.sql"

echo "==> [02-schema-based-multitenant] Running automated verification assertions..."
docker exec -i "$COORDINATOR" psql -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d "$POSTGRES_DB" < "${SCRIPT_DIR}/verify.sql"

echo "==> [02-schema-based-multitenant] PASSED: All schema-based multi-tenant tests passed successfully."
