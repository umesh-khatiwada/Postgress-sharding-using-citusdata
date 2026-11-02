-- ==============================================================================
-- Citus Diagnostic and Introspection Helper Queries
-- ==============================================================================

-- 1. Active Worker Nodes Summary
SELECT 
    nodeid,
    nodename,
    nodeport,
    noderole,
    nodecluster,
    isactive
FROM pg_dist_node
ORDER BY nodeid;

-- 2. Distributed Tables Summary
SELECT 
    table_name::text AS table_name,
    citus_table_type,
    distribution_column,
    colocation_id,
    shard_count,
    table_size
FROM citus_tables
ORDER BY table_name;

-- 3. Detailed Shard Distribution per Node
SELECT 
    t.table_name::text AS table_name,
    s.shardid,
    s.nodename,
    s.nodeport,
    pg_size_pretty(s.shard_size) AS shard_size
FROM citus_tables t
JOIN citus_shards s ON t.table_name = s.table_name
ORDER BY t.table_name, s.shardid;

-- 4. Colocation Groups Summary
SELECT 
    c.colocationid,
    c.shardcount,
    c.replicationfactor,
    c.distributioncolumntype::regtype AS column_type,
    string_agg(p.logicalrelid::text, ', ' ORDER BY p.logicalrelid::text) AS colocated_tables
FROM pg_dist_colocation c
JOIN pg_dist_partition p ON c.colocationid = p.colocationid
GROUP BY c.colocationid, c.shardcount, c.replicationfactor, c.distributioncolumntype
ORDER BY c.colocationid;

-- 5. Cluster Health Check
SELECT * FROM citus_check_cluster_node_health();
