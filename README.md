# Postgress-sharding-using-citusdata

A comprehensive, production-grade learning repository and reference implementation for **Citus**—the open-source PostgreSQL extension that transforms PostgreSQL into a distributed, horizontally scalable database.

> **Primary Reference**: [Citus Multi-Tenant Use Cases](https://www.citusdata.com/use-cases/multi-tenant-apps)  
> **Authoritative Documentation**: [docs.citusdata.com](https://docs.citusdata.com)

---

## Pinned Versions

| Component | Pinned Version | Docker Image Tag | Notes |
| :--- | :--- | :--- | :--- |
| **Citus Extension** | `14.2.0` | `citusdata/citus:14.2.0-pg16` | Latest stable major release series |
| **PostgreSQL** | `16.14` | Embedded in `citus:14.2.0-pg16` | Debian GNU/Linux base |
| **PgBouncer** | `1.24.1` | `edoburu/pgbouncer:v1.24.1-p0` | Session pooling with Citus support |
| **Python Client** | `3.10+` | `psycopg[binary] >= 3.1.18` | Standard modern DB driver |

---

## Cluster Architecture

The local development cluster runs via Docker Compose with 1 coordinator node, 2 active primary worker nodes, 1 standby worker node (for online rebalancing and scaling demos), and an optional PgBouncer proxy.

```mermaid
flowchart TD
    Client["Client / Application\n(Python, psql, Backend API)"]
    PgBouncer["PgBouncer Connection Pooler\n(Port 6432)"]

    subgraph CitusCluster ["Docker Bridge Network: citus-network"]
        Coordinator["citus_coordinator\n(Port 5432)\n- Distributed Query Planner\n- Metadata Catalog (pg_dist_*)\n- 2PC Transaction Coordinator"]
        
        Worker1["citus_worker_1\n(Port 5433 -> 5432)\n- Shards: 102001, 102003\n- Local Table Partitions\n- Local Indexes"]
        
        Worker2["citus_worker_2\n(Port 5434 -> 5432)\n- Shards: 102002, 102004\n- Local Table Partitions\n- Local Indexes"]
        
        Worker3["citus_worker_3 (Standby)\n(Port 5435 -> 5432)\n- Online Rebalance Target\n- Scale-Out Node (Example 06)"]
    end

    Client -->|Direct psql / Admin| Coordinator
    Client -->|Pooled App Traffic| PgBouncer
    PgBouncer --> Coordinator
    
    Coordinator -->|Router Query / Parallel Pushdown| Worker1
    Coordinator -->|Router Query / Parallel Pushdown| Worker2
    Coordinator -.->|citus_add_node (Example 06)| Worker3
```

---

## Feature-to-Example Matrix

| # | Example Module | Core Citus Features & Functions | Status |
| :- | :--- | :--- | :--- |
| **00** | [Cluster Setup](examples/00-cluster-setup/) | `CREATE EXTENSION citus`, `citus_set_coordinator_host`, `citus_add_node`, `pg_dist_node`, `citus_check_cluster_node_health` | **Implemented & Verified** |
| **01** | [Row-Based Multi-Tenant](examples/01-row-based-multitenant/) | `create_distributed_table(..., colocate_with)`, Composite Primary/Foreign Keys, Router Queries, Co-located Joins, Scatter-Gather Analytics, Distributed RLS, DDL Propagation | **Implemented & Verified** |
| **02** | Schema-Based Multi-Tenant | `citus.enable_schema_based_sharding`, `citus_schemas`, `citus_schema_move`, `citus_schema_distribute` | Planned |
| **03** | Reference & Local Tables | `create_reference_table`, `citus_add_local_table_to_metadata`, Coordinator-local joins | Planned |
| **04** | Co-location & Joins | Colocated vs Repartition Joins, Subqueries/CTEs, `INSERT..SELECT`, `create_distributed_function` | Planned |
| **05** | Tenant Isolation | `isolate_tenant_to_new_shard`, `citus_stat_tenants`, Hot tenant mitigation | Planned |
| **06** | Rebalancing & Scaling | `citus_rebalance_start`, `citus_rebalance_status`, `citus_split_shard_by_split_points`, `citus_drain_node` | Planned |
| **07** | Real-Time Analytics | Incremental Rollups, Parallel Aggregates, `hll` HyperLogLog, `topn` | Planned |
| **08** | Time-Series Partitioning | Distributed Native Partitioning, automated retention, partition pruning | Planned |
| **09** | Columnar Storage | `USING columnar`, compression (zstd/lz4), Mixed hot row / cold columnar storage | Planned |
| **10** | Distributed Transactions | 2-Phase Commit (2PC), `citus.multi_shard_commit_protocol`, Distributed deadlocks | Planned |
| **11** | Query from Any Node (MX) | Citus MX, Worker metadata sync, read/write scaling without coordinator bottleneck | Planned |
| **12** | Connection Pooling | PgBouncer configuration, Citus transaction pool vs session pool mode | Planned |
| **13** | High-Throughput CRUD | `pgbench` benchmarks: single-node PostgreSQL vs distributed Citus cluster | Planned |
| **14** | Monitoring & Tuning | `citus_stat_statements`, `citus_shards`, `citus_tables`, executor GUCs | Planned |
| **15** | Failure & HA | Worker failover, Patroni / CloudNativePG discussion, disaster recovery | Planned |
| **16** | Migration from Single Node | Online table distribution, foreign key refactoring, dual-write checklists | Planned |

---

## Quickstart

### Prerequisites
- Docker Engine `20.10+` and Docker Compose `v2+`
- `make` and standard POSIX shell (`bash`)
- Optional: Python `3.10+` for running the application demo

### 1. Launch the Cluster
```bash
# Start coordinator, 3 workers, and PgBouncer
make up

# View running services
make ps
```

### 2. Initialize the Cluster (Example 00)
Registers workers with the coordinator and applies baseline GUCs:
```bash
make setup
```

### 3. Run Automated Verifications
Every example includes an automated assertion test suite:
```bash
# Verify 00-cluster-setup
make verify-00

# Verify 01-row-based-multitenant
make verify-01

# Run all implemented verifications
make verify-all
```

### 4. Interactive Shell Access
```bash
# Connect to coordinator
make shell-coordinator

# Connect to worker 1 directly
make shell-worker-1

# Connect to PgBouncer
make shell-pgbouncer
```

### 5. Tear Down Cluster
```bash
make down
```

---

## Repository Layout

```
.
├── README.md                      # Overview, architecture, quickstart, matrix
├── Makefile                       # Cluster lifecycle, setup, and verification targets
├── docker-compose.yml             # Pinned Citus 14.2 cluster definition
├── .env.example                   # Environment defaults and pinned image tags
├── .gitignore
├── LICENSE                        # Apache 2.0
├── .github/
│   └── workflows/ci.yml           # Automated CI running make verify-all
├── docker/                        # Compose files and container configs
├── common/                        # Shared SQL diagnostics and health checks
│   ├── citus_helpers.sql          # Topology, sharding, and colocation inspector
│   └── wait-for-cluster.sh        # Healthcheck poll script
└── examples/
    ├── 00-cluster-setup/          # Node registration, health checks, GUC tuning
    ├── 01-row-based-multitenant/  # SaaS schema, co-location, RLS, DDL migration
    │   └── app/                   # Python psycopg 3 demo application
    └── [02-16 folders...]         # Scaffolded upcoming modules
```

---

## Troubleshooting & Key Citus Rules

### 1. Why did `UNIQUE` or `PRIMARY KEY` creation fail?
> In Citus distributed tables, any `PRIMARY KEY` or `UNIQUE` constraint **must include the distribution column** (e.g. `PRIMARY KEY (tenant_id, id)`). Standalone unique constraints across arbitrary columns cannot be verified without cross-worker communication on every single write, which would destroy OLTP throughput.

### 2. Why did `FOREIGN KEY ... ON DELETE SET NULL` fail?
> Citus supports `ON DELETE CASCADE` and `ON DELETE RESTRICT` for co-located foreign keys. Citus explicitly does **not** support `ON DELETE SET NULL` when the distribution key is part of the foreign key constraint, because setting the distribution key to `NULL` would violate shard routing.

### 3. Why did Row-Level Security (RLS) return 0 rows or bypass checks?
> - **Superuser Bypass**: In PostgreSQL, the `postgres` superuser bypasses RLS policies unconditionally. Applications must connect as an unprivileged role (`tenant_app_user`).
> - **GUC Propagation**: Session variables (such as `SET LOCAL app.tenant_id = '1'`) are not propagated to Citus workers by default (`citus.propagate_set_commands = 'none'`). You must configure:
>   ```sql
>   ALTER SYSTEM SET citus.propagate_set_commands = 'local';
>   SELECT pg_reload_conf();
>   ```
>   and wrap queries in a transaction: `BEGIN; SET LOCAL app.tenant_id = '...'; ... COMMIT;`.

---

## Continuous Integration (CI)
GitHub Actions automatically boots the Docker Compose cluster, applies Example 00 setup, runs all verification suites, and tests clean teardown on every commit. See [`.github/workflows/ci.yml`](.github/workflows/ci.yml).
