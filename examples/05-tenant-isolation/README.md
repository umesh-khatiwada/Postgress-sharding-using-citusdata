# 05 - Tenant Isolation ("Noisy Neighbor" Mitigation)

## Goal & Citus Features Used
Address the classic distributed multi-tenant challenge: a single enterprise tenant generates 90% of the traffic or storage, starving smaller tenants on the same worker node ("noisy neighbor" problem).

Citus features demonstrated:
- Identifying hot tenants using [`citus_stat_tenants`](https://docs.citusdata.com/en/v14.2/admin_guide/cluster_management.html#tenant-monitoring) and [`citus.stat_tenants_track = 'all'`](https://docs.citusdata.com/en/v14.2/develop/api_guc.html#citus-stat-tenants-track).
- Carving out a dedicated single-tenant shard with [`isolate_tenant_to_new_shard(table, tenant_id, cascade_option)`](https://docs.citusdata.com/en/v14.2/develop/api_udf.html#isolate-tenant-to-new-shard).
- Relocating the isolated tenant to a dedicated physical hardware node using [`citus_move_shard_placement()`](https://docs.citusdata.com/en/v14.2/develop/api_udf.html#citus-move-shard-placement).
- Executing cluster-wide configuration via [`run_command_on_all_nodes()`](https://docs.citusdata.com/en/v14.2/develop/api_udf.html#run-command-on-all-nodes).

---

## Architecture: Isolating a Noisy Neighbor

```
=== BEFORE ISOLATION ===
Worker Node 1
+--------------------------------------------------------------+
| Shard 102001 (Hash Range: 1 to 500,000,000)                  |
| - Account 1   (Stark Tech: 10 QPS, 50 MB)                    |
| - Account 2   (Wayne Ent:  15 QPS, 80 MB)                    |
| - Account 999 (Titan Corp: 5,000 QPS, 200 GB) <-- NOISY!    |
+--------------------------------------------------------------+
Account 1 and 2 suffer high p99 latency and lock starvation!

=== STEP 1: isolate_tenant_to_new_shard('accounts', 999, 'cascade') ===
Worker Node 1
+------------------------------------+  +------------------------------------+
| Shard 102001 (Hash 1..499,999,999) |  | Shard 102050 (Dedicated to 999)    |
| - Account 1                        |  | - Account 999                      |
| - Account 2                        |  +------------------------------------+
+------------------------------------+

=== STEP 2: citus_move_shard_placement(102050, 'worker_1' -> 'worker_3') ===
Worker Node 1                           Dedicated Worker Node 3
+------------------------------------+  +------------------------------------+
| Shard 102001                       |  | Shard 102050                       |
| - Account 1 (Stark Tech)           |  | - Account 999 (Titan Corp)         |
| - Account 2 (Wayne Ent)            |  | -> 100% Dedicated CPU, RAM, & IOPS |
+------------------------------------+  +------------------------------------+
Small tenants are protected! Titan Corp gets dedicated enterprise performance.
```

---

## File Structure

```
examples/05-tenant-isolation/
├── README.md       # Architectural deep dive
├── schema.sql      # Enable tenant statistics, register worker 3, create accounts tables
├── data.sql        # Standard tenants and high-volume noisy neighbor dataset
├── queries.sql     # Workload generation, stat inspection, shard isolation, node move
├── verify.sh       # Executable test suite
├── verify.sql      # SQL assertions testing detection, dedicated shards, and worker placement
└── cleanup.sql     # Drop tables and reset tracking GUCs
```

---

## Running the Example

```bash
make verify-05
# OR manually:
./examples/05-tenant-isolation/verify.sh
```

---

## Step-by-Step Walkthrough

### 1. Enable Tenant Statistics Tracking
In `schema.sql`:
```sql
SELECT run_command_on_all_nodes('ALTER SYSTEM SET citus.stat_tenants_track = ''all''');
SELECT run_command_on_all_nodes('SELECT pg_reload_conf()');
```
Worker nodes record query frequency and CPU time per tenant.

### 2. Identify the Noisy Neighbor via `citus_stat_tenants`
```sql
SELECT nodeid, tenant_attribute, query_count_in_this_period, score 
FROM citus_stat_tenants(true)
ORDER BY score DESC LIMIT 5;
```
Output identifies `tenant_attribute = 999` with 100+ queries and high CPU score.

### 3. Carve Out a Dedicated Shard
```sql
SELECT isolate_tenant_to_new_shard(
    'accounts', 
    999, 
    cascade_option => 'cascade', 
    shard_transfer_mode => 'block_writes'
);
```
Inspect `pg_dist_shard`:
```sql
SELECT shardid, shardminvalue, shardmaxvalue 
FROM pg_dist_shard 
WHERE shardminvalue = '999' AND shardmaxvalue = '999';
```
Citus created a new dedicated shard where `shardminvalue == shardmaxvalue == '999'`. The `cascade` option automatically applied this split to `account_metrics` as well.

### 4. Relocate the Shard to Dedicated Hardware (`citus_worker_3`)
```sql
SELECT citus_move_shard_placement(
    shard_id, 
    'citus_worker_1', 5432, 
    'citus_worker_3', 5432, 
    shard_transfer_mode => 'block_writes'
);
```
Querying `citus_shards` confirms that Account 999's shards now live exclusively on `citus_worker_3:5432`.

---

## What to Look For in EXPLAIN
```sql
EXPLAIN (ANALYZE, VERBOSE)
SELECT count(*) FROM account_metrics WHERE account_id = 999;
```
Look for:
```
Custom Scan (Citus Adaptive)
  Task Count: 1
  Node: host=citus_worker_3 port=5432 dbname=postgres
```
All queries and writes for Account 999 route directly to dedicated `citus_worker_3`, completely bypassing `citus_worker_1` and `citus_worker_2`.

---

## Pitfalls & Trade-offs

1. **Shard Proliferation**:
   Isolating tenants splits existing shards into 3 new shards (lower hash range, isolated tenant, upper hash range). If you isolate 1,000 tenants, your cluster shard count will triple. Isolate only true outliers (e.g. top 1-5% enterprise tenants).
2. **Cascading Requirement**:
   Always pass `cascade_option => 'cascade'`. If omitted, only the root table is isolated, breaking co-location between `accounts` and child tables like `account_metrics`, which forces Citus into expensive non-colocated repartition joins!
3. **Table Locks During Shard Splitting**:
   `isolate_tenant_to_new_shard` takes a momentary lock on the shard to split and copy data. In high-concurrency production, run isolation during low-traffic windows or with `shard_transfer_mode => 'auto'` with `wal_level = logical`.
