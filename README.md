# Postgress-sharding-using-citusdata

A comprehensive, production-grade learning repository and reference implementation for **Citus**—the open-source PostgreSQL extension that transforms PostgreSQL into a distributed, horizontally scalable database.

![License](https://img.shields.io/badge/license-Apache%202.0-blue)
![Citus](https://img.shields.io/badge/Citus-14.2.0-informational)
![PostgreSQL](https://img.shields.io/badge/PostgreSQL-16-336791)
![Docker Compose](https://img.shields.io/badge/docker-compose-2496ED)

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
| **02** | [Schema-Based Multi-Tenant](examples/02-schema-based-multitenant/) | `citus.enable_schema_based_sharding`, `citus_schemas`, `citus_schema_move`, `citus_schema_undistribute`/`distribute`, Decision Matrix | **Implemented & Verified** |
| **03** | [Reference & Local Tables](examples/03-reference-and-local-tables/) | `create_reference_table`, `citus_add_local_table_to_metadata`, Coordinator-local joins, Zero-shuffle joins, 2PC writes | **Implemented & Verified** |
| **04** | [Co-location & Joins](examples/04-colocation-and-joins/) | Colocated vs Repartition Joins, `MapMergeJob`, Subqueries/CTEs, `INSERT..SELECT`, `COPY`, `create_distributed_function` | **Implemented & Verified** |
| **05** | [Tenant Isolation](examples/05-tenant-isolation/) | `isolate_tenant_to_new_shard`, `citus_stat_tenants`, Hot tenant mitigation, Relocation to dedicated worker 3 | **Implemented & Verified** |
| **06** | [Rebalancing & Scaling](examples/06-rebalancing-and-scaling/) | `citus_rebalance_start`, `citus_rebalance_status`, `citus_move_shard_placement`, `citus_split_shard_by_split_points`, `citus_drain_node`, `rebalance_table_shards` | **Implemented & Verified** |
| **07** | [Real-Time Analytics](examples/07-realtime-analytics/) | Incremental Rollups, Parallel Aggregates, `hll` HyperLogLog, `topn` Sketches, Sub-millisecond Dashboards | **Implemented & Verified** |
| **08** | [Time-Series Partitioning](examples/08-timeseries-partitioning/) | Distributed Native Partitioning, `create_time_partitions`, `drop_old_time_partitions`, Automated retention, Partition pruning | **Implemented & Verified** |
| **09** | [Columnar Storage](examples/09-columnar-storage/) | `USING columnar`, `alter_columnar_table_set` (zstd/lz4), Projection elimination, Mixed hot heap / cold columnar partitions | **Implemented & Verified** |
| **10** | [Normal vs Citus Scale Benchmark (1M & 10M)](examples/10-normal-vs-citus-1m-benchmark/) | Single-node PostgreSQL vs Citus distributed cluster benchmark at scale (1M and 10M rows input, 8 query archetypes, 5.08x ingestion speedup, 4.48x distinct count acceleration, `EXPLAIN ANALYZE` comparison) | **Implemented & Verified** |
| **11** | Distributed Transactions | 2-Phase Commit (2PC), `citus.multi_shard_commit_protocol`, Distributed deadlocks | Planned |
| **12** | Query from Any Node (MX) | Citus MX, Worker metadata sync, read/write scaling without coordinator bottleneck | Planned |
| **13** | Connection Pooling | PgBouncer configuration, Citus transaction pool vs session pool mode | Planned |
| **14** | High-Throughput CRUD | `pgbench` benchmarks: single-node PostgreSQL vs distributed Citus cluster | Planned |
| **15** | Monitoring & Tuning | `citus_stat_statements`, `citus_shards`, `citus_tables`, executor GUCs | Planned |
| **16** | Failure & HA | Worker failover, Patroni / CloudNativePG discussion, disaster recovery | Planned |
| **17** | Migration from Single Node | Online table distribution, foreign key refactoring, dual-write checklists | Planned |

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

### 5. Tear Down and Destroy All Cluster Services
Tears down all containers, custom networks, persistent volumes, and test caches cleanly:
```bash
# Using Makefile
make down
# or alias
make destroy

# Using standalone shell script
./destroy.sh
# To also delete downloaded Docker images:
./destroy.sh --all
```

### 6. Pre-Download Docker Images (Optional)
```bash
make download
# or
make pull
```

---

## Configuration

Copy `.env.example` to `.env` to override defaults (the Makefile and `docker-compose.yml` fall back to the same defaults if `.env` is absent). The defaults are for **local lab use only**; change the password for anything beyond that.

| Variable | Default | Purpose |
| :--- | :--- | :--- |
| `CITUS_IMAGE` | `citusdata/citus:14.2.0-pg16` | Citus image used by coordinator and workers |
| `POSTGRES_USER` | `postgres` | Superuser name |
| `POSTGRES_PASSWORD` | `<set-a-password>` (example file ships a local-only default) | Superuser password |
| `POSTGRES_DB` | `postgres` | Default database |
| `COORDINATOR_PORT` | `5432` | Host port of the coordinator |
| `WORKER1_PORT` / `WORKER2_PORT` / `WORKER3_PORT` | `5433` / `5434` / `5435` | Host ports of the workers |
| `PGBOUNCER_PORT` | `6432` | Host port of PgBouncer |
| `STANDALONE_PORT` | `5431` | Host port of the plain `postgres:16` container used as the benchmark baseline (Example 10) |
| `COMPOSE_PROJECT_NAME` | `citus_lab` | Docker Compose project prefix |

## Make Targets

Run `make help` for the full list. Highlights:

| Target | Description |
| :--- | :--- |
| `make up` / `make down` | Start the cluster / destroy containers, networks and volumes |
| `make setup` | Register workers (Example 00) |
| `make verify-NN` | Run the assertions for example `NN` (`00` to `10`) |
| `make verify-all` | Run every verification |
| `make load-1m`, `make load-10m` | Ingest 1M / 10M rows into the normal and Citus tables (Example 10) |
| `make benchmark-1m`, `make benchmark-10m` | Run the comparative benchmark |
| `make shell-coordinator`, `shell-worker-1`, `shell-worker-2`, `shell-pgbouncer` | Open `psql` sessions |

> Benchmark figures quoted in the matrix above come from the author's runs and depend on hardware; re-run `make benchmark-1m` to reproduce.

## Repository Layout

```
.
├── README.md
├── Makefile                       # Cluster lifecycle, setup, verify and benchmark targets
├── docker-compose.yml             # Coordinator, 3 workers, PgBouncer, standalone Postgres
├── destroy.sh                     # Standalone teardown (--all also removes images)
├── .env.example                   # Environment defaults
├── LICENSE                        # Apache 2.0
├── .github/workflows/ci.yml       # CI
├── docker/                        # Additional compose file and notes
├── common/                        # citus_helpers.sql, wait-for-cluster.sh, destroy-cluster.sh
└── examples/
    ├── 00-cluster-setup/ ... 10-normal-vs-citus-1m-benchmark/
    │   └── each: README.md, schema.sql, data.sql, queries.sql, verify.sh/.sql, cleanup.sql
    └── 01-row-based-multitenant/app/   # Python psycopg 3 demo app
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

---

## License

Released under the [Apache License 2.0](LICENSE).

## Author

Umesh Khatiwada - [github.com/umesh-khatiwada](https://github.com/umesh-khatiwada)
