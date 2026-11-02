-- ==============================================================================
-- 02-schema-based-multitenant: Demonstrations & Query Plans
-- ==============================================================================

-- 1. Inspect Distributed Schemas Catalog
SELECT 
    schema_name::text,
    colocation_id,
    schema_size,
    schema_owner
FROM citus_schemas
ORDER BY schema_name;

-- 2. Inspect Distributed Tables in Tenant Schemas
SELECT 
    table_name::text,
    citus_table_type,
    shard_count,
    colocation_id
FROM citus_tables
WHERE table_name::text LIKE 'tenant_%'
ORDER BY table_name;

-- 3. Inspect Physical Shard Placement Across Worker Nodes
SELECT 
    table_name::text,
    shardid,
    nodename,
    nodeport
FROM citus_shards
WHERE table_name::text LIKE 'tenant_%'
ORDER BY table_name;


-- ==============================================================================
-- 4. Application Query Routing via search_path
-- Notice how the application can simply set `search_path` to the active tenant schema.
-- In EXPLAIN, Citus routes the query directly to the single worker hosting that schema!
-- Notice: "Task Count: 1"!
-- ==============================================================================
SET search_path = tenant_acme, public;

EXPLAIN (ANALYZE, VERBOSE)
SELECT 
    u.name,
    u.email,
    count(o.id) AS total_orders,
    coalesce(sum(o.total_amount), 0) AS lifetime_value
FROM users u
LEFT JOIN orders o ON u.id = o.user_id
GROUP BY u.id, u.name, u.email
ORDER BY lifetime_value DESC;

RESET search_path;


-- ==============================================================================
-- 5. Moving a Tenant Schema Between Workers (citus_schema_move)
-- Allows relocating an entire tenant (all its tables, indexes, constraints)
-- from one worker node to another in a single atomic operation.
-- ==============================================================================

-- Inspect node before move
SELECT table_name::text, nodename, nodeport 
FROM citus_shards 
WHERE table_name::text LIKE 'tenant_acme.%';

-- Dynamically move tenant_acme to the other worker node
DO $$
DECLARE
    v_current_node text;
    v_target_node text;
BEGIN
    SELECT nodename INTO v_current_node 
    FROM citus_shards 
    WHERE table_name::text = 'tenant_acme.users' LIMIT 1;

    v_target_node := CASE WHEN v_current_node = 'citus_worker_1' THEN 'citus_worker_2' ELSE 'citus_worker_1' END;
    RAISE NOTICE 'Moving tenant_acme from % to %...', v_current_node, v_target_node;

    PERFORM citus_schema_move('tenant_acme', v_target_node, 5432, shard_transfer_mode => 'block_writes');
END $$;

-- Verify node after move
SELECT table_name::text, nodename, nodeport 
FROM citus_shards 
WHERE table_name::text LIKE 'tenant_acme.%';


-- ==============================================================================
-- 6. Undistribute and Redistribute a Schema
-- ==============================================================================

-- Move tenant_soylent back to coordinator-local storage
SELECT citus_schema_undistribute('tenant_soylent');

-- Verify it is now a local schema on the coordinator
SELECT schema_name::text FROM citus_schemas WHERE schema_name::text = 'tenant_soylent';

-- Redistribute tenant_soylent back to the worker nodes
SELECT citus_schema_distribute('tenant_soylent');

-- Verify it is once again a distributed schema
SELECT schema_name::text, colocation_id FROM citus_schemas WHERE schema_name::text = 'tenant_soylent';
