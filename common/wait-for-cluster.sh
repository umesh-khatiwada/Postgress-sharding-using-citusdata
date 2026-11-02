#!/usr/bin/env bash
# ==============================================================================
# Wait for Citus Coordinator and Workers to be healthy and accept connections
# ==============================================================================

set -euo pipefail

COORDINATOR=${COORDINATOR_CONTAINER:-citus_coordinator}
WORKERS=("${WORKER1_CONTAINER:-citus_worker_1}" "${WORKER2_CONTAINER:-citus_worker_2}" "${WORKER3_CONTAINER:-citus_worker_3}")
MAX_ATTEMPTS=30
SLEEP_SECS=1

echo "Checking coordinator ($COORDINATOR)..."
attempt=0
until docker exec "$COORDINATOR" pg_isready -U postgres -d postgres >/dev/null 2>&1; do
    attempt=$((attempt + 1))
    if [ "$attempt" -ge "$MAX_ATTEMPTS" ]; then
        echo "Error: Coordinator ($COORDINATOR) timed out waiting for ready status."
        exit 1
    fi
    sleep "$SLEEP_SECS"
done
echo "Coordinator ($COORDINATOR) is ready."

for worker in "${WORKERS[@]}"; do
    echo "Checking worker ($worker)..."
    attempt=0
    until docker exec "$worker" pg_isready -U postgres -d postgres >/dev/null 2>&1; do
        attempt=$((attempt + 1))
        if [ "$attempt" -ge "$MAX_ATTEMPTS" ]; then
            echo "Warning: Worker ($worker) did not become ready in time."
            break
        fi
        sleep "$SLEEP_SECS"
    done
    echo "Worker ($worker) is ready."
done

echo "All Citus cluster nodes are accepting connections."
