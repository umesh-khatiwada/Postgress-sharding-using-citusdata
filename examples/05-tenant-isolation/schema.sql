-- ==============================================================================
-- 05-tenant-isolation: Schema Definition
-- Noisy Neighbor Isolation with isolate_tenant_to_new_shard and citus_stat_tenants
-- Authoritative Docs: https://docs.citusdata.com/en/v14.2/admin_guide/cluster_management.html#tenant-isolation
-- ==============================================================================

-- 1. Enable tenant statistics tracking across all nodes in the cluster
SELECT run_command_on_all_nodes('ALTER SYSTEM SET citus.stat_tenants_track = ''all''');
SELECT run_command_on_all_nodes('SELECT pg_reload_conf()');
SELECT citus_stat_tenants_reset();

-- 2. Ensure worker 3 is registered in pg_dist_node as a dedicated scale-out node
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_dist_node 
        WHERE nodename = 'citus_worker_3' AND nodeport = 5432
    ) THEN
        PERFORM citus_add_node('citus_worker_3', 5432);
        RAISE NOTICE 'Added dedicated worker node: citus_worker_3:5432';
    END IF;
END $$;

-- 3. Drop existing demo tables if present
DROP TABLE IF EXISTS account_metrics CASCADE;
DROP TABLE IF EXISTS accounts CASCADE;

-- 4. Create Multi-Tenant Tables with an independent colocation group
CREATE TABLE accounts (
    id bigint PRIMARY KEY,
    name text NOT NULL,
    tier text NOT NULL DEFAULT 'standard',
    created_at timestamptz NOT NULL DEFAULT now()
);
-- Use colocate_with => 'none' so this example has its own isolated colocation group
SELECT create_distributed_table('accounts', 'id', colocate_with => 'none');

CREATE TABLE account_metrics (
    account_id bigint NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
    metric_id bigint NOT NULL,
    metric_name text NOT NULL,
    metric_value numeric(12, 4) NOT NULL,
    recorded_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (account_id, metric_id)
);
SELECT create_distributed_table('account_metrics', 'account_id', colocate_with => 'accounts');
