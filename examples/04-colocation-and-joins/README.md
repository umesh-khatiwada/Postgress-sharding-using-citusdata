# 04 - Co-location & Joins

## Goal & Citus Features Used
Master join processing in distributed PostgreSQL:
- **Table Co-location**: grouping related shards on identical worker nodes via [`create_distributed_table(..., colocate_with => '...')`](https://docs.citusdata.com/en/v14.2/sharding/data_modeling.html#table-colocation).
- **Zero-Shuffle Co-located Joins**: local query execution inside worker nodes without network transfer.
- **Non-Colocated Joins (Repartition Joins)**: understanding distributed shuffle execution via [`citus.enable_repartition_joins = 'on'`](https://docs.citusdata.com/en/v14.2/develop/api_guc.html#citus-enable-repartition-joins).
- **Subquery & CTE Pushdown**: allowing PostgreSQL to optimize and evaluate CTEs locally within shard boundaries.
- **Parallel Co-located `INSERT INTO ... SELECT`**: executing mass data ingestion/archiving across workers in parallel.
- **Streaming Bulk Ingestion with `COPY`**: streaming rows directly to worker shard endpoints.
- **Distributed Functions**: registering functions across workers via [`create_distributed_function(function_name, distribution_arg, colocate_with)`](https://docs.citusdata.com/en/v14.2/develop/api_udf.html#create-distributed-function).

---

## Architectural Comparison: Co-located vs Repartition Joins

```
=== CO-LOCATED JOIN (Zero Network Shuffle) ===
Worker 1                                    Worker 2
+------------------------------------+      +------------------------------------+
| Shard 102001 (store_orders)        |      | Shard 102002 (store_orders)        |
| Shard 102001 (order_items)         |      | Shard 102002 (order_items)         |
| -> Joined locally via Hash/NestLoop|      | -> Joined locally via Hash/NestLoop|
+------------------------------------+      +------------------------------------+
No data crosses the network. Millisecond latency!

=== NON-COLOCATED REPARTITION JOIN (MapMergeJob) ===
Worker 1                                    Worker 2
+----------------------+                    +----------------------+
| store_orders Shard 1 |                    | store_orders Shard 2 |
| inventory Shard 10   |                    | inventory Shard 20   |
+----------+-----------+                    +----------+-----------+
           \                 NETWORK SHUFFLE          /
            +-----------------------+----------------+
                                    |
+-----------------------------------v------------------------------------+
| MapMergeJob: intermediate tuples hashed and re-routed across network   |
| High CPU, high network bandwidth, high memory buffer consumption       |
+------------------------------------------------------------------------+
```

---

## File Structure

```
examples/04-colocation-and-joins/
├── README.md       # Comprehensive join architecture guide
├── schema.sql      # Co-located tables, non-colocated inventory, distributed function
├── data.sql        # Seed data (stores, orders, items, warehouse stock)
├── queries.sql     # Router joins, repartition joins, CTE pushdown, INSERT..SELECT
├── verify.sh       # Executable test suite with streaming COPY demonstration
├── verify.sql      # SQL assertions testing colocation, repartition GUC, and functions
└── cleanup.sql     # Drop tables and functions
```

---

## Running the Example

```bash
make verify-04
# OR manually:
./examples/04-colocation-and-joins/verify.sh
```

---

## What to Look For in EXPLAIN

### 1. Co-Located Join (Single Shard Execution)
```sql
EXPLAIN (ANALYZE, VERBOSE)
SELECT o.order_id, count(i.item_id)
FROM store_orders o 
JOIN order_items i ON o.store_id = i.store_id AND o.order_id = i.order_id
WHERE o.store_id = 1
GROUP BY o.order_id;
```
Look for:
```
Custom Scan (Citus Adaptive)
  Task Count: 1
  Node: host=citus_worker_1 port=5432
  Query: SELECT ... FROM store_orders_102001 o JOIN order_items_102001 i ...
```
- Citus generates a single SQL task sent directly to `citus_worker_1`.
- The worker executes standard PostgreSQL `Hash Join` or `Nested Loop` locally in memory.

### 2. Repartition Join (Distributed MapMergeJob)
```sql
SET citus.enable_repartition_joins = 'on';
EXPLAIN (VERBOSE)
SELECT i.sku, sum(i.quantity), sum(w.quantity_available)
FROM order_items i 
JOIN warehouse_inventory w ON i.sku = w.sku
GROUP BY i.sku;
```
Look for:
```
Custom Scan (Citus Adaptive)
  Task Count: 12
  -> MapMergeJob
        Map Task Count: 4
        Merge Task Count: 12
```
Because `order_items` is distributed by `store_id` and `warehouse_inventory` is distributed by `warehouse_id`, Citus must dynamically repartition the intermediate rows by `sku` and stream them across worker boundaries over the network!

### 3. Distributed Function Execution
```sql
SELECT calculate_store_revenue(1);
```
Under the hood, Citus routes the function execution to `citus_worker_1` (the node holding shard `store_orders` for `store_id = 1`), executes the query locally, and returns the result without any coordinator query planning overhead.

---

## Pitfalls & Trade-offs

1. **Repartition Joins in OLTP**:
   Keep `citus.enable_repartition_joins = 'off'` in OLTP production workloads. Non-colocated joins can saturate 10Gbps/100Gbps network interfaces and spike connection pool usage.
2. **Missing Shard Key in Joins**:
   Always include the distribution key in your join condition:
   `ON o.store_id = i.store_id AND o.order_id = i.order_id`. If `store_id` is omitted, Citus cannot verify co-location at plan time!
3. **Colocation Matching Rules**:
   Two tables are eligible for co-location only if:
   - Their distribution columns have **identical data types** (e.g. `bigint` with `bigint`).
   - They have the **same shard count** (`citus.shard_count`).
   - They have the **same replication factor**.
