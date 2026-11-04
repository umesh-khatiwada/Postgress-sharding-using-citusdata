#!/usr/bin/env bash
# ==============================================================================
# Example 10: Normal PostgreSQL vs Citus Distributed PostgreSQL (1M Benchmark)
# Benchmark Execution Script
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

echo "=== [10-normal-vs-citus-1m-benchmark] Running Benchmark Suite ==="

# Check if tables exist, if not run verify.sh first to initialize and populate
if ! docker compose exec -T coordinator psql -U postgres -d postgres -c "SELECT 1 FROM citus_transactions LIMIT 1;" >/dev/null 2>&1; then
    echo "--> Tables not yet populated. Running setup & data loading (1,000,000 rows)..."
    "${SCRIPT_DIR}/verify.sh"
fi

# Run the benchmark runner
python3 "${SCRIPT_DIR}/benchmark.py" "$@"
