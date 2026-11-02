-- ==============================================================================
-- 01-row-based-multitenant: Demonstrations & Query Plans
-- Authoritative Docs: https://docs.citusdata.com/en/v14.2/performance/query_processing.html
-- ==============================================================================

-- ==============================================================================
-- 1. Metadata Inspection: Shards & Co-location
-- ==============================================================================

-- Verify that all tables belong to the exact same colocation_id
SELECT 
    table_name::text AS table_name,
    citus_table_type,
    distribution_column,
    colocation_id,
    shard_count
FROM citus_tables
ORDER BY table_name;

-- Verify colocation group properties
SELECT 
    c.colocationid,
    c.shardcount,
    c.distributioncolumntype::regtype AS column_type,
    string_agg(p.logicalrelid::text, ', ' ORDER BY p.logicalrelid::text) AS colocated_tables
FROM pg_dist_colocation c
JOIN pg_dist_partition p ON c.colocationid = p.colocationid
GROUP BY c.colocationid, c.shardcount, c.distributioncolumntype;


-- ==============================================================================
-- 2. Router Query (Single-Tenant Query Routing)
-- When a query filters by the distribution key (tenant_id = 1), Citus routes the
-- query directly to the single worker node holding that tenant's shard.
-- Notice: "Task Count: 1" in EXPLAIN output!
-- ==============================================================================
EXPLAIN (ANALYZE, VERBOSE)
SELECT 
    id, 
    title, 
    status, 
    priority, 
    due_date 
FROM tasks 
WHERE tenant_id = 1 
  AND status = 'in_progress'
ORDER BY priority DESC;


-- ==============================================================================
-- 3. Co-located Joins (Zero Network Shuffle)
-- Because tasks, projects, and users are co-located on tenant_id, the join
-- executes entirely on the local PostgreSQL worker with NO cross-node traffic.
-- ==============================================================================
EXPLAIN (ANALYZE, VERBOSE)
SELECT 
    t.title AS task_title,
    t.status AS task_status,
    p.name AS project_name,
    u.name AS assignee_name
FROM tasks t
JOIN projects p ON t.tenant_id = p.tenant_id AND t.project_id = p.id
LEFT JOIN users u ON t.tenant_id = u.tenant_id AND t.assigned_to_user_id = u.id
WHERE t.tenant_id = 1
ORDER BY t.id;


-- ==============================================================================
-- 4. Cross-Tenant Parallel Analytics (Scatter-Gather Distributed Query)
-- Admin queries without a tenant_id filter execute across all shards in parallel.
-- Citus pushes aggregations down to each worker, then computes the final merge
-- on the coordinator node.
-- Notice: "Task Count: 4" in EXPLAIN output!
-- ==============================================================================
EXPLAIN (ANALYZE, VERBOSE)
SELECT 
    t.name AS tenant_name,
    t.plan AS tenant_plan,
    count(DISTINCT u.id) AS total_users,
    count(DISTINCT p.id) AS total_projects,
    count(tk.id) AS total_tasks,
    count(CASE WHEN tk.status = 'done' THEN 1 END) AS completed_tasks
FROM tenants t
LEFT JOIN users u ON t.id = u.tenant_id
LEFT JOIN projects p ON t.id = p.tenant_id
LEFT JOIN tasks tk ON t.id = tk.tenant_id
GROUP BY t.id, t.name, t.plan
ORDER BY total_tasks DESC;


-- ==============================================================================
-- 5. Row-Level Security (RLS) Isolation Verification
-- Connect as unprivileged application role 'tenant_app_user'
-- ==============================================================================

-- Test Session 1: Tenant 1 (Acme Corp)
BEGIN;
SET citus.propagate_set_commands = 'local';
SET LOCAL ROLE tenant_app_user;
SET LOCAL app.tenant_id = '1';

-- App runs a broad SELECT; RLS automatically restricts rows to Tenant 1
SELECT 'Tenant 1 Context' AS context, id, title, status FROM tasks;

COMMIT;

-- Test Session 2: Tenant 2 (Globex Logistics)
BEGIN;
SET citus.propagate_set_commands = 'local';
SET LOCAL ROLE tenant_app_user;
SET LOCAL app.tenant_id = '2';

-- App runs the same broad SELECT; RLS now restricts rows to Tenant 2
SELECT 'Tenant 2 Context' AS context, id, title, status FROM tasks;

COMMIT;


-- ==============================================================================
-- 6. Schema Migration Demonstration (DDL Propagation)
-- DDL commands issued on coordinator automatically propagate to all worker shards!
-- ==============================================================================

-- Add a new column to the distributed table
ALTER TABLE tasks ADD COLUMN tags text[] DEFAULT '{}'::text[];

-- Update tags for tenant 1's tasks
UPDATE tasks 
SET tags = ARRAY['citus', 'distributed-sql'] 
WHERE tenant_id = 1 AND id = 1001;

-- Verify updated column
SELECT tenant_id, id, title, tags FROM tasks WHERE tenant_id = 1 AND id = 1001;
