#!/usr/bin/env bash
# ==============================================================================
# Citus Distributed Cluster - Teardown and Destruction Script
# ==============================================================================
# Stops and removes all Citus containers, associated volumes, networks,
# and local temporary test artifacts to return the environment to a clean state.
#
# Usage:
#   ./common/destroy-cluster.sh
#   ./common/destroy-cluster.sh --all   # Also removes downloaded docker images
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

cd "${REPO_ROOT}"

REMOVE_IMAGES=false
if [[ "${1:-}" == "--all" || "${1:-}" == "--images" ]]; then
    REMOVE_IMAGES=true
fi

echo "======================================================================"
echo " Tearing Down & Destroying Citus Cluster Services"
echo "======================================================================"

# 1. Stop and remove all containers, volumes, and networks via Docker Compose
echo "--> Stopping and removing all Docker Compose services, networks, and volumes..."
docker compose down -v --remove-orphans

# 2. Defensive cleanup: check for any lingering containers matching "citus_"
LINGERING_CONTAINERS=$(docker ps -aq --filter "name=citus_" || true)
if [[ -n "${LINGERING_CONTAINERS}" ]]; then
    echo "--> Cleaning up lingering Citus containers: ${LINGERING_CONTAINERS}..."
    docker rm -f ${LINGERING_CONTAINERS} 2>/dev/null || true
fi

# 3. Defensive cleanup: remove any lingering volumes matching "*citus*"
LINGERING_VOLUMES=$(docker volume ls -q --filter "name=citus" || true)
if [[ -n "${LINGERING_VOLUMES}" ]]; then
    echo "--> Cleaning up lingering Citus volumes: ${LINGERING_VOLUMES}..."
    docker volume rm ${LINGERING_VOLUMES} 2>/dev/null || true
fi

# 4. Defensive cleanup: remove Citus custom network if still present
if docker network inspect citus-network >/dev/null 2>&1; then
    echo "--> Removing custom bridge network 'citus-network'..."
    docker network rm citus-network 2>/dev/null || true
fi

# 5. Remove local temporary python and pytest caches
echo "--> Cleaning local temporary cache files..."
rm -rf common/__pycache__ examples/*/__pycache__ examples/*/.pytest_cache

# 6. Optionally remove Docker images if requested
if [[ "${REMOVE_IMAGES}" == "true" ]]; then
    echo "--> Removing Citus and PgBouncer Docker images..."
    docker rmi citusdata/citus:14.2.0-pg16 edoburu/pgbouncer:v1.24.1-p0 2>/dev/null || true
fi

echo "----------------------------------------------------------------------"
echo "Verification:"
REMAINING=$(docker ps --filter "name=citus_" --format "{{.Names}}" || true)
if [[ -z "${REMAINING}" ]]; then
    echo " [OK] All Citus cluster services, containers, networks, and volumes"
    echo "      have been completely destroyed. Ports 5432-5435 & 6432 are freed."
else
    echo " [WARN] The following containers are still active: ${REMAINING}"
    exit 1
fi
echo "======================================================================"
