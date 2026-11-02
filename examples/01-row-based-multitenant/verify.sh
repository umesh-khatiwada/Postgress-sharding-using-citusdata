#!/usr/bin/env bash
# ==============================================================================
# 01-row-based-multitenant: Verification Runner Script
# ==============================================================================

set -euo pipefail

COORDINATOR=${COORDINATOR_CONTAINER:-citus_coordinator}
POSTGRES_USER=${POSTGRES_USER:-postgres}
POSTGRES_DB=${POSTGRES_DB:-postgres}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "==> [01-row-based-multitenant] Applying schema and co-located distributed tables..."
docker exec -i "$COORDINATOR" psql -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d "$POSTGRES_DB" < "${SCRIPT_DIR}/schema.sql"

echo "==> [01-row-based-multitenant] Seeding multi-tenant dataset..."
docker exec -i "$COORDINATOR" psql -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d "$POSTGRES_DB" < "${SCRIPT_DIR}/data.sql"

echo "==> [01-row-based-multitenant] Running query demonstrations (router, co-located join, parallel analytics, DDL)..."
docker exec -i "$COORDINATOR" psql -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d "$POSTGRES_DB" < "${SCRIPT_DIR}/queries.sql"

echo "==> [01-row-based-multitenant] Testing cross-tenant RLS security violation (expecting rejection)..."
# Attempting to insert a Tenant 2 record while authenticated with Tenant 1 context
set +e
docker exec -i "$COORDINATOR" psql -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d "$POSTGRES_DB" << 'EOF' >/dev/null 2>&1
BEGIN;
SET citus.propagate_set_commands = 'local';
SET LOCAL ROLE tenant_app_user;
SET LOCAL app.tenant_id = '1';
-- Violation: tenant_id 2 does not match session tenant_id 1
INSERT INTO tasks (tenant_id, id, project_id, title) VALUES (2, 9999, 21, 'Malicious Cross-Tenant Task');
COMMIT;
EOF
VIOLATION_EXIT_CODE=$?
set -e

if [ "$VIOLATION_EXIT_CODE" -eq 0 ]; then
    echo "ERROR: Cross-tenant RLS insert succeeded when it should have failed!"
    exit 1
fi
echo "==> [01-row-based-multitenant] RLS breach successfully blocked by PostgreSQL policy engine."

echo "==> [01-row-based-multitenant] Running automated verification assertions..."
docker exec -i "$COORDINATOR" psql -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d "$POSTGRES_DB" < "${SCRIPT_DIR}/verify.sql"

echo "==> [01-row-based-multitenant] PASSED: All row-based multi-tenant tests passed successfully."
