-- ==============================================================================
-- 01-row-based-multitenant: Cleanup Script
-- ==============================================================================

DROP TABLE IF EXISTS events CASCADE;
DROP TABLE IF EXISTS tasks CASCADE;
DROP TABLE IF EXISTS projects CASCADE;
DROP TABLE IF EXISTS users CASCADE;
DROP TABLE IF EXISTS tenants CASCADE;

DROP ROLE IF EXISTS tenant_app_user;
