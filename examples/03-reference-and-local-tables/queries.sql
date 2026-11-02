-- ==============================================================================
-- 03-reference-and-local-tables: Demonstrations & Query Plans
-- ==============================================================================

-- ==============================================================================
-- 1. Metadata Inspection: Reference vs Distributed vs Local Tables
-- ==============================================================================

-- Observe table classification in citus_tables
SELECT 
    table_name::text,
    citus_table_type,
    distribution_column,
    shard_count
FROM citus_tables
WHERE table_name::text IN ('currencies', 'countries', 'plans', 'subscriptions', 'admin_audit_logs', 'global_system_settings')
ORDER BY citus_table_type, table_name;

-- Observe that reference tables are replicated to EVERY node in the cluster
SELECT 
    table_name::text,
    shardid,
    nodename,
    nodeport
FROM citus_shards
WHERE table_name::text IN ('currencies', 'countries', 'plans')
ORDER BY table_name, nodename;


-- ==============================================================================
-- 2. Local Joins between Distributed Table & Reference Tables
-- Because `plans`, `countries`, and `currencies` are replicated locally to every worker,
-- joining `subscriptions` with all 3 reference tables requires ZERO network hops!
-- Notice: "Task Count: 1" in EXPLAIN output!
-- ==============================================================================
EXPLAIN (ANALYZE, VERBOSE)
SELECT 
    s.tenant_id,
    p.name AS plan_name,
    p.price_monthly,
    c.name AS country_name,
    curr.code AS currency_code,
    curr.symbol AS currency_symbol
FROM subscriptions s
JOIN plans p ON s.plan_id = p.id
JOIN countries c ON s.billing_country = c.code
JOIN currencies curr ON s.currency_code = curr.code
WHERE s.tenant_id = 1;


-- ==============================================================================
-- 3. Querying Coordinator-Local Tables joined with Distributed & Reference Tables
-- Citus executes a Distributed Subplan to fetch distributed records to the coordinator,
-- then performs the join with the local table in coordinator memory.
-- ==============================================================================
EXPLAIN (ANALYZE, VERBOSE)
SELECT 
    a.id AS audit_id,
    a.admin_email,
    a.action,
    s.tenant_id,
    p.name AS plan_name,
    a.created_at
FROM admin_audit_logs a
JOIN subscriptions s ON a.target_tenant_id = s.tenant_id
JOIN plans p ON s.plan_id = p.id
ORDER BY a.created_at DESC;


-- ==============================================================================
-- 4. Two-Phase Commit (2PC) Atomic Writes to Reference Tables
-- When a reference table is updated, Citus uses a 2-phase commit to ensure
-- all copies across coordinator and workers remain strictly synchronized.
-- ==============================================================================
UPDATE currencies 
SET exchange_rate_usd = 1.0925 
WHERE code = 'EUR';

-- Verify update on coordinator
SELECT code, symbol, exchange_rate_usd FROM currencies WHERE code = 'EUR';
