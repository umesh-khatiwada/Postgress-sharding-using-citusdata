#!/usr/bin/env bash
# ==============================================================================
# 04-colocation-and-joins: Verification Runner Script
# ==============================================================================

set -euo pipefail

COORDINATOR=${COORDINATOR_CONTAINER:-citus_coordinator}
POSTGRES_USER=${POSTGRES_USER:-postgres}
POSTGRES_DB=${POSTGRES_DB:-postgres}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "==> [04-colocation-and-joins] Applying schema, colocation, and distributed functions..."
docker exec -i "$COORDINATOR" psql -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d "$POSTGRES_DB" < "${SCRIPT_DIR}/schema.sql"

echo "==> [04-colocation-and-joins] Seeding store orders and inventory..."
docker exec -i "$COORDINATOR" psql -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d "$POSTGRES_DB" < "${SCRIPT_DIR}/data.sql"

echo "==> [04-colocation-and-joins] Demonstrating distributed streaming COPY..."
# Citus distributed COPY: Citus streams input rows directly to the corresponding worker shards
docker exec -i "$COORDINATOR" psql -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d "$POSTGRES_DB" << 'EOF'
COPY store_orders (store_id, order_id, customer_id, order_status, total_amount) FROM STDIN WITH (FORMAT csv);
1,199,599,completed,77.50
2,299,699,completed,88.25
\.
EOF
echo "==> [04-colocation-and-joins] Distributed COPY completed successfully."

echo "==> [04-colocation-and-joins] Running query demonstrations (joins, repartition, CTEs, INSERT..SELECT)..."
docker exec -i "$COORDINATOR" psql -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d "$POSTGRES_DB" < "${SCRIPT_DIR}/queries.sql"

echo "==> [04-colocation-and-joins] Running automated verification assertions..."
docker exec -i "$COORDINATOR" psql -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d "$POSTGRES_DB" < "${SCRIPT_DIR}/verify.sql"

echo "==> [04-colocation-and-joins] PASSED: All colocation and join tests passed successfully."
