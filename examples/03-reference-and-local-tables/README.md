# 03 - Reference & Local Tables

## Goal & Citus Features Used
Demonstrate how Citus manages tables that do not require sharding across nodes:
- [`create_reference_table(table_name)`](https://docs.citusdata.com/en/v14.2/develop/reference_tables.html): Replicating lookup data to **every node** in the cluster.
- **Local Distributed Joins**: Joining distributed tables (`subscriptions`) with reference tables (`plans`, `currencies`, `countries`) locally with zero inter-worker network overhead.
- **Cross-Type Foreign Keys**: Defining foreign keys from distributed tables to reference tables.
- **Two-Phase Commit (2PC) Writes**: Maintaining synchronized consistency across all replica placements.
- **Coordinator-Local Tables**: Retaining admin/system tables exclusively on the coordinator.
- [`citus_add_local_table_to_metadata(table_name)`](https://docs.citusdata.com/en/v14.2/develop/api_udf.html#citus-add-local-table-to-metadata): Registering coordinator-local tables so the Citus distributed planner can join them with distributed datasets.

---

## Architecture: Reference vs Distributed vs Local Tables

```
                    Coordinator Node
           +---------------------------------+
           | citus_tables metadata           |
           | currencies  (Reference Replica) |
           | plans       (Reference Replica) |
           | admin_audit_logs (Local Table)  |
           +----------------+----------------+
                            |
           +----------------+----------------+
           |                                 |
+----------v----------------------+ +--------v-----------------------+
|          Worker Node 1          | |          Worker Node 2         |
| - currencies (Reference Replica)| | - currencies (Reference Replica)|
| - plans      (Reference Replica)| | - plans      (Reference Replica)|
| - subscriptions (Shard 102001)  | | - subscriptions (Shard 102002) |
+---------------------------------+ +--------------------------------+
```

### Table Categories

1. **Distributed Table (`subscriptions`)**:
   Hash-partitioned by `tenant_id`. Shards are sliced and balanced across worker nodes.
2. **Reference Table (`plans`, `currencies`, `countries`)**:
   Replicated in full to **all worker nodes and the coordinator**. Reads are 100% local on whatever worker is executing the query.
3. **Local Table (`admin_audit_logs`, `global_system_settings`)**:
   Resides physically only on the coordinator. Registered in Citus metadata via `citus_add_local_table_to_metadata()` to enable cross-table joins with distributed tables.

---

## File Structure

```
examples/03-reference-and-local-tables/
├── README.md       # This guide
├── schema.sql      # Reference tables, distributed table with FKs, coordinator-local tables
├── data.sql        # Seed data (currencies, countries, plans, subscriptions, audit logs)
├── queries.sql     # Zero-shuffle local joins, distributed subplans, 2PC write demo
├── verify.sh       # Executable test runner with foreign key violation test
├── verify.sql      # SQL assertions testing replication factor, join results, 2PC sync
└── cleanup.sql     # Clean table teardown
```

---

## Running the Example

```bash
make verify-03
# OR manually:
./examples/03-reference-and-local-tables/verify.sh
```

---

## What to Look For in Metadata & EXPLAIN

### 1. Replicated Placements in `citus_shards`
```sql
SELECT table_name::text, shardid, nodename, nodeport 
FROM citus_shards 
WHERE table_name::text = 'plans';
```
Output:
```
 table_name | shardid |     nodename      | nodeport 
------------+---------+-------------------+----------
 plans      |  102168 | citus_coordinator |     5432
 plans      |  102168 | citus_worker_1    |     5432
 plans      |  102168 | citus_worker_2    |     5432
```
Notice that shard `102168` exists on **all 3 nodes**.

### 2. Zero-Shuffle Distributed Join
```sql
EXPLAIN (ANALYZE, VERBOSE)
SELECT s.tenant_id, p.name, c.name, curr.symbol
FROM subscriptions s
JOIN plans p ON s.plan_id = p.id
JOIN countries c ON s.billing_country = c.code
JOIN currencies curr ON s.currency_code = curr.code
WHERE s.tenant_id = 1;
```
Look for:
```
Custom Scan (Citus Adaptive)
  Task Count: 1
  Node: host=citus_worker_1 port=5432
  Query: SELECT ... FROM subscriptions JOIN plans JOIN countries JOIN currencies ...
```
Because copies of `plans`, `countries`, and `currencies` exist on `citus_worker_1`, the worker executes the join directly against its local tables using standard PostgreSQL nested loops and index scans. No data is fetched over the network from other workers!

### 3. Distributed Subplan with Coordinator-Local Tables
```sql
EXPLAIN (ANALYZE, VERBOSE)
SELECT a.action, p.name 
FROM admin_audit_logs a 
JOIN subscriptions s ON a.target_tenant_id = s.tenant_id 
JOIN plans p ON s.plan_id = p.id;
```
Look for:
```
Distributed Subplan
  Result destination: Send to 2 nodes
  Query: SELECT action, target_tenant_id FROM admin_audit_logs ...
```
Citus reads the local table on the coordinator, broadcasts the intermediate keys to the workers, executes the join on the workers, and merges the result.

---

## Pitfalls & Trade-offs

1. **Write Overhead on Reference Tables**:
   Because reference tables are replicated to every node, every `INSERT`, `UPDATE`, or `DELETE` uses a Two-Phase Commit (2PC) protocol across all nodes. Modifying reference tables is slower than modifying distributed tables.
   - **Recommendation**: Use reference tables exclusively for small, slowly-changing datasets (<100,000 rows, such as lookup codes, plans, countries). Never use reference tables for high-frequency writes or event streams.
2. **Cluster Scaling Impact**:
   When you add a new worker node to the Citus cluster (`citus_add_node`), Citus automatically copies all reference tables to the new node so it is immediately ready for local joins. If reference tables are gigabytes in size, adding workers takes longer.
3. **Foreign Key Direction**:
   - Supported: Distributed table $\rightarrow$ Reference table (e.g. `subscriptions.plan_id` $\rightarrow$ `plans.id`).
   - Unsupported: Reference table $\rightarrow$ Distributed table (a table replicated on all nodes cannot reference a table partitioned across nodes).
