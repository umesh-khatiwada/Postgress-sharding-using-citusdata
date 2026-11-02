#!/usr/bin/env bash
# ==============================================================================
# 00-cluster-setup: Verification Runner Script
# ==============================================================================

set -euo pipefail

COORDINATOR=${COORDINATOR_CONTAINER:-citus_coordinator}
POSTGRES_USER=${POSTGRES_USER:-postgres}
POSTGRES_DB=${POSTGRES_DB:-postgres}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "==> [00-cluster-setup] Applying schema and node registration..."
docker exec -i "$COORDINATOR" psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" < "${SCRIPT_DIR}/schema.sql"

echo "==> [00-cluster-setup] Running metadata queries..."
docker exec -i "$COORDINATOR" psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" < "${SCRIPT_DIR}/queries.sql"

echo "==> [00-cluster-setup] Running automated verification assertions..."
docker exec -i "$COORDINATOR" psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" < "${SCRIPT_DIR}/verify.sql"

echo "==> [00-cluster-setup] PASSED: Cluster setup verified successfully."
