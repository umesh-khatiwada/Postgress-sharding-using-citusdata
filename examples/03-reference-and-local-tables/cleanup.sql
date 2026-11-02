-- ==============================================================================
-- 03-reference-and-local-tables: Cleanup Script
-- ==============================================================================

DROP TABLE IF EXISTS subscriptions CASCADE;
DROP TABLE IF EXISTS countries CASCADE;
DROP TABLE IF EXISTS currencies CASCADE;
DROP TABLE IF EXISTS plans CASCADE;
DROP TABLE IF EXISTS admin_audit_logs CASCADE;
DROP TABLE IF EXISTS global_system_settings CASCADE;
