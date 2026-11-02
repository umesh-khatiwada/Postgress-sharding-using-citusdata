-- ==============================================================================
-- 02-schema-based-multitenant: Cleanup Script
-- ==============================================================================

DROP SCHEMA IF EXISTS tenant_acme CASCADE;
DROP SCHEMA IF EXISTS tenant_globex CASCADE;
DROP SCHEMA IF EXISTS tenant_soylent CASCADE;

SET citus.enable_schema_based_sharding = 'off';
