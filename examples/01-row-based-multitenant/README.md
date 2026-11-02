# 01 - Row-Based Multi-Tenant (SaaS Architecture)

## Goal & Citus Features Used
Demonstrate the canonical B2B SaaS multi-tenant architecture on Citus, as detailed in the [Citus Multi-Tenant Use-Case Guide](https://www.citusdata.com/use-cases/multi-tenant-apps).
Features highlighted:
- [`create_distributed_table(table, distribution_column, colocate_with => ...)`](https://docs.citusdata.com/en/v14.2/develop/api_udf.html#create-distributed-table)
- **Table Co-location**: grouping shards belonging to related tables onto the same worker nodes.
- **Router Queries (Single-Shard Routing)**: queries with `tenant_id` filter routed directly to 1 worker.
- **Co-located Joins**: joining multi-tenant tables on `tenant_id` locally without inter-node data transfer.
- **Scatter-Gather Parallel Analytics**: cross-tenant aggregation executing concurrently across all worker shards.
- **Distributed Row-Level Security (RLS)**: enforcing tenant data isolation using `current_setting('app.tenant_id')` with [`citus.propagate_set_commands = 'local'`](https://docs.citusdata.com/en/v14.2/develop/api_guc.html#citus-propagate-set-commands).
- **Distributed DDL Propagation**: schema modifications automatically propagated to all physical shard tables.

---

## Architectural Principles

In a Citus row-based multi-tenant application:
1. **The Tenant ID is Ubiquitous**: `tenant_id` must be present in every distributed table.
2. **Composite Primary Keys**: Every table's primary key must include `tenant_id`: `PRIMARY KEY (tenant_id, id)`.
3. **Composite Foreign Keys**: Foreign keys must include `tenant_id`: `FOREIGN KEY (tenant_id, project_id) REFERENCES projects(tenant_id, id)`. This allows PostgreSQL on each worker to enforce referential integrity within local shards.
4. **Co-location**: Distributing all tables on `tenant_id` and specifying `colocate_with => 'tenants'` places shard $N$ of `users`, shard $N$ of `projects`, and shard $N$ of `tasks` on the exact same worker.

```
Worker Node 1                                Worker Node 2
+------------------------------------+       +------------------------------------+
| Shard 102001                       |       | Shard 102002                       |
|   tenants (Tenant 1: Acme)         |       |   tenants (Tenant 2: Globex)       |
|   users   (Tenant 1 users)         |       |   users   (Tenant 2 users)         |
|   projects(Tenant 1 projects)      |       |   projects(Tenant 2 projects)      |
|   tasks   (Tenant 1 tasks)         |       |   tasks   (Tenant 2 tasks)         |
|   events  (Tenant 1 events)        |       |   events  (Tenant 2 events)        |
+------------------------------------+       +------------------------------------+
        ^                                            ^
        |                                            |
        +---------------------+----------------------+
                              |
                     Coordinator Node
                 Routes by hash(tenant_id)
```

---

## File Structure

```
examples/01-row-based-multitenant/
├── README.md       # This guide
├── schema.sql      # Multi-tenant tables, composite keys, distribution, RLS policies
├── data.sql        # Realistic multi-tenant seed data (4 tenants, users, projects, tasks)
├── queries.sql     # Router queries, co-located joins, cross-tenant analytics, DDL demo
├── verify.sh       # Bash verification runner with RLS exploit security test
├── verify.sql      # SQL assertions testing co-location, counts, and RLS enforcement
├── cleanup.sql     # Drop tables and test roles
└── app/            # Python / Psycopg 3 demo application
    ├── app.py
    ├── requirements.txt
    └── README.md
```

---

## Running the Example

### 1. Initialize Cluster (if not already running)
```bash
make setup
```

### 2. Apply Schema & Seed Data
```bash
docker exec -i citus_coordinator psql -U postgres -d postgres < examples/01-row-based-multitenant/schema.sql
docker exec -i citus_coordinator psql -U postgres -d postgres < examples/01-row-based-multitenant/data.sql
```

### 3. Run Query Demonstrations
```bash
docker exec -i citus_coordinator psql -U postgres -d postgres < examples/01-row-based-multitenant/queries.sql
```

### 4. Run Automated Verification Suite
```bash
make verify-01
```

---

## What to Look For in EXPLAIN Plans

### 1. Router Query (Single Shard Execution)
```sql
EXPLAIN (ANALYZE, VERBOSE)
SELECT * FROM tasks WHERE tenant_id = 1 AND status = 'in_progress';
```
Look for:
```
Custom Scan (Citus Adaptive)
  Task Count: 1
  Tasks Shown: One of 1
  ->  Task
        Node: host=citus_worker_1 port=5432 dbname=postgres
        Query: SELECT ... FROM public.tasks_102034 tasks WHERE ...
```
- **`Task Count: 1`**: Citus calculated `hash(tenant_id=1)` and knew only one worker and one shard hold this data.
- The coordinator does not scatter to other workers. Latency is identical to single-node PostgreSQL.

### 2. Co-Located Join (Zero Network Traffic)
```sql
EXPLAIN (ANALYZE, VERBOSE)
SELECT t.title, p.name FROM tasks t 
JOIN projects p ON t.tenant_id = p.tenant_id AND t.project_id = p.id
WHERE t.tenant_id = 1;
```
Look for:
- Citus sends a single SQL query containing the `JOIN` to the worker.
- The worker executes the join locally in memory/disk. No tuples cross the network between workers!

### 3. Cross-Tenant Analytics (Scatter-Gather)
```sql
EXPLAIN (ANALYZE, VERBOSE)
SELECT tenant_id, count(*) FROM tasks GROUP BY tenant_id;
```
Look for:
```
Custom Scan (Citus Adaptive)
  Task Count: 4
```
- Query executed in parallel across all 4 shards across all workers.
- Each worker computes a partial aggregation; the coordinator merges the partial results.

---

## Deep Dive: Row-Level Security (RLS) on Citus

Row-Level Security allows SaaS applications to pool database connections under a single PostgreSQL role (e.g. `tenant_app_user`) while guaranteeing that no tenant can read or write another tenant's rows.

### The Two Critical Rules for Citus RLS:
1. **Unprivileged Role**: PostgreSQL superusers (`postgres`) **always bypass RLS**. The app must connect as (or `SET ROLE` to) an unprivileged role.
2. **GUC Propagation**: In Citus, session variables set on the coordinator are not sent to workers by default (`citus.propagate_set_commands = 'none'`). You must configure:
   ```sql
   ALTER SYSTEM SET citus.propagate_set_commands = 'local';
   SELECT pg_reload_conf();
   ```
   Then within each transaction:
   ```sql
   BEGIN;
   SET LOCAL app.tenant_id = '1';
   SELECT * FROM tasks; -- Only returns Tenant 1 tasks!
   COMMIT;
   ```
   When the transaction ends, `SET LOCAL` is automatically discarded, preventing connection pool contamination.

---

## Pitfalls & Trade-offs

1. **Unique Constraints Must Include Distribution Column**: In Citus, unique constraints (including `PRIMARY KEY`) on distributed tables must contain the distribution column. You cannot have a global unique constraint on `id` alone; it must be `(tenant_id, id)`.
2. **Missing `tenant_id` in Queries**: If a query omits `WHERE tenant_id = ...`, Citus must fall back to a full scatter-gather query across all shards. In high-throughput OLTP systems, missing distribution keys cause high connection overhead and throughput degradation.
3. **Tenant Skew ("Noisy Neighbors")**: If one tenant generates 90% of your data (e.g., Apple or Amazon in an enterprise SaaS), that tenant's shard will grow disproportionately. Citus provides `isolate_tenant_to_new_shard()` (covered in Example 05) to isolate large tenants onto dedicated shards.
4. **Cross-Tenant Foreign Keys**: You cannot create a foreign key between two tables distributed on different keys, or across different tenants.
