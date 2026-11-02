# ==============================================================================
# Citus Distributed PostgreSQL Cluster - Makefile
# ==============================================================================

SHELL := /bin/bash
.DEFAULT_GOAL := help

# Load environment variables if .env exists
ifneq (,$(wildcard ./.env))
    include .env
    export
endif

COORDINATOR_CONTAINER ?= citus_coordinator
WORKER1_CONTAINER ?= citus_worker_1
WORKER2_CONTAINER ?= citus_worker_2
WORKER3_CONTAINER ?= citus_worker_3
POSTGRES_USER ?= postgres
POSTGRES_DB ?= postgres

.PHONY: help
help: ## Display this help message
	@echo "======================================================================"
	@echo " Citus Distributed PostgreSQL Cluster Management"
	@echo "======================================================================"
	@grep -E '^[a-zA-Z0-9_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-22s\033[0m %s\n", $$1, $$2}'

.PHONY: up
up: ## Start the Citus cluster (coordinator + 3 workers + pgbouncer)
	@echo "--> Starting Citus cluster containers..."
	docker compose up -d
	@echo "--> Waiting for cluster nodes to be healthy..."
	@./common/wait-for-cluster.sh

.PHONY: down
down: ## Stop and remove all containers, networks, and volumes
	@echo "--> Tearing down Citus cluster..."
	docker compose down -v --remove-orphans
	@echo "--> Cluster destroyed cleanly."

.PHONY: ps
ps: ## View cluster container status
	docker compose ps

.PHONY: logs
logs: ## Stream cluster container logs
	docker compose logs -f

.PHONY: setup
setup: up ## Initialize the Citus cluster metadata and register workers (Example 00)
	@echo "--> Running 00-cluster-setup..."
	docker exec -i $(COORDINATOR_CONTAINER) psql -U $(POSTGRES_USER) -d $(POSTGRES_DB) < examples/00-cluster-setup/schema.sql
	@echo "--> Cluster setup complete."

.PHONY: shell-coordinator
shell-coordinator: ## Open an interactive psql session on the coordinator node
	docker exec -it $(COORDINATOR_CONTAINER) psql -U $(POSTGRES_USER) -d $(POSTGRES_DB)

.PHONY: shell-worker-1
shell-worker-1: ## Open an interactive psql session on worker node 1
	docker exec -it $(WORKER1_CONTAINER) psql -U $(POSTGRES_USER) -d $(POSTGRES_DB)

.PHONY: shell-worker-2
shell-worker-2: ## Open an interactive psql session on worker node 2
	docker exec -it $(WORKER2_CONTAINER) psql -U $(POSTGRES_USER) -d $(POSTGRES_DB)

.PHONY: shell-pgbouncer
shell-pgbouncer: ## Open an interactive psql session through PgBouncer (port 6432)
	PGPASSWORD=$(POSTGRES_PASSWORD) psql -h localhost -p 6432 -U $(POSTGRES_USER) -d $(POSTGRES_DB)

.PHONY: verify-00
verify-00: ## Verify 00-cluster-setup
	@chmod +x examples/00-cluster-setup/verify.sh
	@./examples/00-cluster-setup/verify.sh

.PHONY: verify-01
verify-01: ## Verify 01-row-based-multitenant
	@chmod +x examples/01-row-based-multitenant/verify.sh
	@./examples/01-row-based-multitenant/verify.sh

.PHONY: verify-02
verify-02: ## Verify 02-schema-based-multitenant
	@chmod +x examples/02-schema-based-multitenant/verify.sh
	@./examples/02-schema-based-multitenant/verify.sh

.PHONY: verify-03
verify-03: ## Verify 03-reference-and-local-tables
	@chmod +x examples/03-reference-and-local-tables/verify.sh
	@./examples/03-reference-and-local-tables/verify.sh

.PHONY: verify-04
verify-04: ## Verify 04-colocation-and-joins
	@chmod +x examples/04-colocation-and-joins/verify.sh
	@./examples/04-colocation-and-joins/verify.sh

.PHONY: verify-05
verify-05: ## Verify 05-tenant-isolation
	@chmod +x examples/05-tenant-isolation/verify.sh
	@./examples/05-tenant-isolation/verify.sh

.PHONY: verify-06
verify-06: ## Verify 06-rebalancing-and-scaling
	@chmod +x examples/06-rebalancing-and-scaling/verify.sh
	@./examples/06-rebalancing-and-scaling/verify.sh

.PHONY: verify-all
verify-all: verify-00 verify-01 verify-02 verify-03 verify-04 verify-05 verify-06 ## Run verification across all implemented examples
	@echo "======================================================================"
	@echo " All implemented example verifications passed successfully!"
	@echo "======================================================================"

.PHONY: clean
clean: down ## Complete cleanup of cluster and local temporary artifacts
	rm -rf common/__pycache__ examples/*/__pycache__ examples/*/.pytest_cache
