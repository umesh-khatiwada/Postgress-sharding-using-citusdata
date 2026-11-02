#!/usr/bin/env bash
# ==============================================================================
# 03-reference-and-local-tables: Verification Runner Script
# ==============================================================================

set -euo pipefail

COORDINATOR=${COORDINATOR_CONTAINER:-citus_coordinator}
POSTGRES_USER=${POSTGRES_USER:-postgres}
POSTGRES_DB=${POSTGRES_DB:-postgres}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "==> [03-reference-and-local-tables] Applying reference and local table schemas..."
docker exec -i "$COORDINATOR" psql -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d "$POSTGRES_DB" < "${SCRIPT_DIR}/schema.sql"

echo "==> [03-reference-and-local-tables] Seeding reference, distributed, and local data..."
docker exec -i "$COORDINATOR" psql -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d "$POSTGRES_DB" < "${SCRIPT_DIR}/data.sql"

echo "==> [03-reference-and-local-tables] Running query demonstrations (local joins, local table joins, 2PC updates)..."
docker exec -i "$COORDINATOR" psql -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d "$POSTGRES_DB" < "${SCRIPT_DIR}/queries.sql"

echo "==> [03-reference-and-local-tables] Testing foreign key integrity to reference table (expecting rejection)..."
set +e
docker exec -i "$COORDINATOR" psql -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d "$POSTGRES_DB" << 'EOF' >/dev/null 2>&1
-- Invalid plan_id 'nonexistent_plan' should be rejected by foreign key constraint
INSERT INTO subscriptions (tenant_id, id, plan_id, currency_code, billing_country, status)
VALUES (1, 999, 'nonexistent_plan', 'USD', 'US', 'active');
EOF
FK_EXIT_CODE=$?
set -e

if [ "$FK_EXIT_CODE" -eq 0 ]; then
    echo "ERROR: Foreign key violation was permitted into distributed table!"
    exit 1
fi
echo "==> [03-reference-and-local-tables] Foreign key violation to reference table successfully enforced."

echo "==> [03-reference-and-local-tables] Running automated verification assertions..."
docker exec -i "$COORDINATOR" psql -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d "$POSTGRES_DB" < "${SCRIPT_DIR}/verify.sql"

echo "==> [03-reference-and-local-tables] PASSED: All reference and local table tests passed successfully."
