# 02 - Schema-Based Multi-Tenant (Schema-Per-Tenant)

## Goal & Citus Features Used
Demonstrate schema-based sharding (introduced in Citus 12.0+), where each tenant is assigned their own PostgreSQL schema (`tenant_acme`, `tenant_globex`), and each schema is automatically placed on a Citus worker as a single co-located shard group.
Authoritative documentation: [Citus Schema Sharding Guide](https://docs.citusdata.com/en/v14.2/use_cases/schema_sharding.html).

Key features demonstrated:
- [`citus.enable_schema_based_sharding = 'on'`](https://docs.citusdata.com/en/v14.2/develop/api_guc.html#citus-enable-schema-based-sharding)
- Intercepting `CREATE SCHEMA` to auto-distribute schemas across worker nodes
- Introspecting schemas via the [`citus_schemas`](https://docs.citusdata.com/en/v14.2/develop/api_metadata.html#citus-schemas) view
- Dynamic tenant relocation via [`citus_schema_move(schema, target_node, target_port)`](https://docs.citusdata.com/en/v14.2/develop/api_udf.html#citus-schema-move)
- Converting schemas between coordinator-local and distributed storage via [`citus_schema_undistribute`](https://docs.citusdata.com/en/v14.2/develop/api_udf.html#citus-schema-undistribute) and [`citus_schema_distribute`](https://docs.citusdata.com/en/v14.2/develop/api_udf.html#citus-schema-distribute)
- Seamless query routing via PostgreSQL `search_path`

---

## Architectural Comparison: Row-Based vs Schema-Based Sharding

| Architectural Dimension | Row-Based Multi-Tenant (Example 01) | Schema-Based Multi-Tenant (Example 02) |
| :--- | :--- | :--- |
| **Data Separation** | Logical (shared tables filtered by `tenant_id` + RLS) | Physical namespace per tenant (`CREATE SCHEMA tenant_x`) |
| **Schema DDL Changes** | Requires adding `tenant_id` to every table, primary key, and foreign key | **Standard PostgreSQL DDL**: no `tenant_id` column or composite keys required |
| **Tenant Scalability** | **Massive**: Millions of tenants | **Moderate**: Up to a few thousand tenants (PostgreSQL catalog limitations) |
| **Query Routing** | `WHERE tenant_id = 1` | `SET search_path = tenant_x, public` |
| **Migrations / DDL** | Single `ALTER TABLE` modifies table across all tenants instantly | Migrations must iterate over every tenant schema (`N` DDL executions) |
| **Tenant Relocation** | Shard isolation: `isolate_tenant_to_new_shard()` | Instant relocation: `citus_schema_move()` |
| **Cross-Tenant Analytics** | Simple parallel SQL across tables (`GROUP BY tenant_id`) | Complex (requires querying across `N` schemas or union views) |
| **Best Suited For** | High-volume B2B/B2C SaaS with uniform schemas | Enterprise B2B SaaS with heavy custom schemas, microservices, or legacy migrations |

---

## File Structure

```
examples/02-schema-based-multitenant/
├── README.md       # Architectural deep dive and decision matrix
├── schema.sql      # Enable schema sharding, create tenant schemas and unmodified tables
├── data.sql        # Seed data across tenant schemas
├── queries.sql     # search_path routing, EXPLAIN plans, citus_schema_move, undistribute
├── verify.sh       # Executable test suite
├── verify.sql      # SQL assertions testing distribution, relocation, and schema catalogs
└── cleanup.sql     # Drop schemas and reset GUC
```

---

## Running the Example

### 1. Execute Setup & Automated Verification
```bash
make verify-02
# OR manually:
./examples/02-schema-based-multitenant/verify.sh
```

---

## What to Look For in Metadata & EXPLAIN

### 1. `citus_schemas` and `citus_tables`
Run on coordinator:
```sql
SELECT * FROM citus_schemas;
```
Output:
```
 schema_name   | colocation_id | schema_size | schema_owner 
---------------+---------------+-------------+--------------
 tenant_acme   |             9 | 64 kB       | postgres
 tenant_globex |            10 | 64 kB       | postgres
 tenant_soylent|            11 | 64 kB       | postgres
```
Notice:
- Each schema receives its own unique `colocation_id`.
- Every table inside `tenant_acme` (such as `users` and `orders`) automatically inherits this colocation ID.
- In `citus_tables`, `citus_table_type` is reported as `schema` with `shard_count = 1`.

### 2. Query Routing via `search_path`
```sql
SET search_path = tenant_acme, public;
EXPLAIN (ANALYZE, VERBOSE)
SELECT u.name, count(o.id) FROM users u JOIN orders o ON u.id = o.user_id GROUP BY u.name;
```
Look for:
```
Custom Scan (Citus Adaptive)
  Task Count: 1
  Node: host=citus_worker_1 port=5432 dbname=postgres
```
The coordinator plans the query against `tenant_acme.users` and `tenant_acme.orders`, sees that the schema's shard is located on `citus_worker_1`, and routes directly to that node with zero cross-shard chatter.

### 3. Moving a Tenant to Another Node
```sql
SELECT citus_schema_move('tenant_acme', 'citus_worker_2', 5432, shard_transfer_mode => 'block_writes');
```
Querying `citus_shards` confirms that all physical shard tables for `tenant_acme` moved atomically to `citus_worker_2:5432`.

---

## Pitfalls & Trade-offs

1. **PostgreSQL Catalog Bloat at High Tenant Counts**:
   PostgreSQL stores metadata for every table, index, sequence, and constraint in `pg_class` and `pg_attribute`. If you have 50 tables per tenant and 10,000 tenants, that results in 500,000 tables. Coordinator catalog queries, vacuuming, and memory usage will degrade. For >5,000 tenants, use **Row-Based Sharding** (Example 01).
2. **Schema Migration Overhead**:
   When releasing a new application version with a schema migration, a migration tool must execute DDL statements against every tenant schema in sequence (or with a worker pool), rather than a single atomic migration.
3. **Cross-Tenant Reporting**:
   Generating cross-tenant dashboards or billing reports requires querying across dozens or hundreds of independent schemas, which is slower and more cumbersome than row-based grouping.
4. **Logical Replication vs Block Writes during `citus_schema_move`**:
   The default transfer mode `auto` uses PostgreSQL logical replication for online moves, requiring `wal_level = logical`. In environments where logical replication is disabled, specify `shard_transfer_mode => 'block_writes'` to transfer using COPY with a momentary write lock.
