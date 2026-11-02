# 00 - Cluster Setup

## Goal & Citus Features Used
Set up a multi-node Citus cluster comprising a coordinator node and independent worker nodes.
This example demonstrates:
- Enabling the Citus extension (`CREATE EXTENSION citus;`)
- Establishing coordinator identity within the network via [`citus_set_coordinator_host`](https://docs.citusdata.com/en/v14.2/develop/api_udf.html#citus-set-coordinator-host)
- Dynamically registering worker nodes via [`citus_add_node`](https://docs.citusdata.com/en/v14.2/develop/api_udf.html#citus-add-node)
- Inspecting cluster topology via [`pg_dist_node`](https://docs.citusdata.com/en/v14.2/develop/api_metadata.html#worker-node-tables) and [`citus_get_active_worker_nodes()`](https://docs.citusdata.com/en/v14.2/develop/api_udf.html#citus-get-active-worker-nodes)
- Validating inter-node network connectivity using [`citus_check_cluster_node_health()`](https://docs.citusdata.com/en/v14.2/develop/api_udf.html#citus-check-cluster-node-health)
- Configuring default sharding parameters (`citus.shard_count`, `citus.shard_replication_factor`)

---

## Architecture

```
                       +---------------------------+
                       |    citus_coordinator      |
                       |       (Port: 5432)        |
                       |  - Stores pg_dist_* meta  |
                       |  - Routes & plans queries |
                       +-------------+-------------+
                                     |
              +----------------------+----------------------+
              |                                             |
+-------------v-------------+                 +-------------v-------------+
|      citus_worker_1       |                 |      citus_worker_2       |
|       (Port: 5433)        |                 |       (Port: 5434)        |
|  - Holds table shards     |                 |  - Holds table shards     |
|  - Executes local queries |                 |  - Executes local queries |
+---------------------------+                 +---------------------------+
```

---

## File Structure

```
examples/00-cluster-setup/
├── README.md       # This guide
├── schema.sql      # Coordinator host assignment and worker node registration
├── queries.sql     # Metadata catalog introspection and health check queries
├── verify.sh       # Automated bash verification runner
├── verify.sql      # SQL assertions testing active nodes and connectivity
└── cleanup.sql     # Reset settings and node removal notes
```

---

## How Citus Discovers & Manages Nodes

1. **Coordinator Host**: Worker nodes need to contact the coordinator back (for two-phase commit callbacks, metadata synchronization, or distributed foreign keys). `citus_set_coordinator_host('citus_coordinator', 5432)` records this hostname in `pg_dist_node`.
2. **Adding Workers**: Calling `citus_add_node('citus_worker_1', 5432)` inserts a record into `pg_dist_node`. The coordinator connects to the worker via libpq and verifies the worker can be contacted and is running the same Citus version.
3. **Cluster Health Check**: `citus_check_cluster_node_health()` iterates over all registered nodes, attempts a query connection, and returns status flags for each node.

---

## Running the Example

### 1. Start the Docker Cluster
```bash
make up
```

### 2. Register Nodes & Apply Configuration
```bash
make setup
# OR:
docker exec -i citus_coordinator psql -U postgres -d postgres < examples/00-cluster-setup/schema.sql
```

### 3. Run Metadata Queries
```bash
docker exec -i citus_coordinator psql -U postgres -d postgres < examples/00-cluster-setup/queries.sql
```

### 4. Run Automated Verification
```bash
make verify-00
```

---

## What to Look For in Metadata

Run this in `psql` on `citus_coordinator`:

```sql
SELECT nodeid, nodename, nodeport, noderole, isactive FROM pg_dist_node;
```

Expected output:
```
 nodeid |     nodename      | nodeport | noderole | isactive 
--------+-------------------+----------+----------+----------
      1 | citus_worker_1    |     5432 | primary  | t
      2 | citus_worker_2    |     5432 | primary  | t
(2 rows)
```

Notice:
- `nodeid`: Unique identifier assigned to each worker.
- `nodename`: The Docker bridge network hostname.
- `isactive`: Indicates whether the coordinator will schedule shards on this node.
- `noderole`: Typically `primary`. For streaming replica worker pairs, Citus also supports `secondary`.

---

## Pitfalls & Trade-offs

1. **Docker vs Host Port Mapping**: Inside the Docker network, workers listen on port `5432`. When registering workers via `citus_add_node('citus_worker_1', 5432)`, pass the internal port (`5432`), NOT the host-mapped port (`5433`).
2. **Coordinator as a Single Point of Failure (SPOF)**: Citus coordinator metadata must be protected. In production, run coordinator and workers with high-availability tooling like Patroni, Kubernetes CloudNativePG, or Azure Cosmos DB for PostgreSQL.
3. **Mismatched Citus or PostgreSQL Versions**: Every node in the cluster must run identical major PostgreSQL versions and compatible Citus extension binaries.
4. **When NOT to shard**: If your dataset fits easily on a single standard PostgreSQL instance and does not experience write IOPS or storage bottlenecks, single-node Postgres is simpler to operate, backup, and maintain.
