-- ============================================================================
-- Example 06: Rebalancing & Scaling
-- Demonstration Queries
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. Inspect Initial Shard Placements Across Worker Nodes
-- ----------------------------------------------------------------------------
-- Citus exposes metadata views showing where each shard replica is located.
SELECT
    table_name,
    shardid,
    nodename,
    nodeport,
    shard_size
FROM citus_shards
WHERE table_name::text IN ('sensor_fleets', 'sensor_events')
ORDER BY table_name, shardid;

-- Summary of shard count per node for sensor_fleets
SELECT
    n.nodename,
    n.nodeport,
    n.shouldhaveshards,
    count(s.shardid) AS total_shards
FROM pg_dist_node n
LEFT JOIN citus_shards s ON s.nodename = n.nodename AND s.table_name = 'sensor_fleets'::regclass
WHERE n.nodecluster = 'default'
GROUP BY n.nodename, n.nodeport, n.shouldhaveshards
ORDER BY n.nodename;

-- ----------------------------------------------------------------------------
-- 2. Manual Shard Relocation (citus_move_shard_placement)
-- ----------------------------------------------------------------------------
-- When you want fine-grained control over a specific shard placement:
DO $$
DECLARE
    v_shard_id bigint;
    v_src_node text;
    v_dst_node text;
BEGIN
    SELECT shardid, nodename
    INTO v_shard_id, v_src_node
    FROM citus_shards
    WHERE table_name = 'sensor_fleets'::regclass
      AND nodename = 'citus_worker_1'
    LIMIT 1;

    v_dst_node := 'citus_worker_2';

    IF v_shard_id IS NOT NULL THEN
        RAISE NOTICE 'Moving shard % from % to %...', v_shard_id, v_src_node, v_dst_node;
        PERFORM citus_move_shard_placement(
            v_shard_id,
            v_src_node, 5432,
            v_dst_node, 5432,
            shard_transfer_mode => 'block_writes'
        );
    END IF;
END $$;

-- ----------------------------------------------------------------------------
-- 3. Shard Splitting (citus_split_shard_by_split_points)
-- ----------------------------------------------------------------------------
-- If a shard experiences heavy growth, split it in two at its midpoint hash:
DO $$
DECLARE
    v_shard_id bigint;
    v_min bigint;
    v_max bigint;
    v_mid text;
    v_node1 int;
    v_node2 int;
BEGIN
    SELECT s.shardid, s.shardminvalue::bigint, s.shardmaxvalue::bigint
    INTO v_shard_id, v_min, v_max
    FROM pg_dist_shard s
    WHERE s.logicalrelid = 'sensor_fleets'::regclass
    ORDER BY s.shardid LIMIT 1;

    -- Calculate the exact midpoint of the 32-bit integer hash range
    v_mid := ((v_min + v_max) / 2)::text;

    SELECT nodeid INTO v_node1 FROM pg_dist_node WHERE shouldhaveshards = true ORDER BY nodeid ASC LIMIT 1;
    SELECT nodeid INTO v_node2 FROM pg_dist_node WHERE shouldhaveshards = true ORDER BY nodeid DESC LIMIT 1;

    RAISE NOTICE 'Splitting shard % (range % to %) at split point % onto nodes %, %...',
        v_shard_id, v_min, v_max, v_mid, v_node1, v_node2;

    PERFORM citus_split_shard_by_split_points(
        v_shard_id,
        ARRAY[v_mid],
        ARRAY[v_node1, v_node2],
        shard_transfer_mode => 'block_writes'
    );
END $$;

-- ----------------------------------------------------------------------------
-- 4. Node Draining (citus_drain_node)
-- ----------------------------------------------------------------------------
-- Evacuate all shards from citus_worker_3 for maintenance or node decommissioning
SELECT citus_drain_node('citus_worker_3', 5432, shard_transfer_mode => 'block_writes');

-- Verify that worker 3 has 0 shards and shouldhaveshards is false
SELECT
    n.nodename,
    n.shouldhaveshards,
    count(s.shardid) AS shard_count
FROM pg_dist_node n
LEFT JOIN citus_shards s ON s.nodename = n.nodename AND s.table_name = 'sensor_fleets'::regclass
GROUP BY n.nodename, n.shouldhaveshards
ORDER BY n.nodename;

-- ----------------------------------------------------------------------------
-- 5. Restore Node and Execute Cluster-Wide Shard Rebalancing
-- ----------------------------------------------------------------------------
-- Re-enable worker 3 to accept shards
SELECT citus_set_node_property('citus_worker_3', 5432, 'shouldhaveshards', true);

-- Rebalance table shards across all active nodes
SELECT rebalance_table_shards(shard_transfer_mode => 'block_writes');

-- Check rebalance status
SELECT * FROM citus_rebalance_status();

-- ----------------------------------------------------------------------------
-- 6. EXPLAIN Analytics Query Across Rebalanced Cluster
-- ----------------------------------------------------------------------------
-- Scatter-gather query distributed across all 3 workers
EXPLAIN (ANALYZE, VERBOSE)
SELECT
    f.region,
    count(e.event_id) AS total_events,
    ROUND(avg(e.temperature), 2) AS avg_temp,
    ROUND(min(e.battery_level), 2) AS min_battery
FROM sensor_fleets f
JOIN sensor_events e ON e.fleet_id = f.fleet_id
GROUP BY f.region
ORDER BY f.region;
