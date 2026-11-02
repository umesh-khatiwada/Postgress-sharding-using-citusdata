-- ==============================================================================
-- 05-tenant-isolation: Cleanup Script
-- ==============================================================================

DROP TABLE IF EXISTS account_metrics CASCADE;
DROP TABLE IF EXISTS accounts CASCADE;

SELECT run_command_on_all_nodes('ALTER SYSTEM RESET citus.stat_tenants_track');
SELECT run_command_on_all_nodes('SELECT pg_reload_conf()');
SELECT citus_stat_tenants_reset();
