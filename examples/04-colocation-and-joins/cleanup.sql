-- ==============================================================================
-- 04-colocation-and-joins: Cleanup Script
-- ==============================================================================

DROP TABLE IF EXISTS store_orders_archive CASCADE;
DROP TABLE IF EXISTS order_items CASCADE;
DROP TABLE IF EXISTS store_orders CASCADE;
DROP TABLE IF EXISTS warehouse_inventory CASCADE;
DROP FUNCTION IF EXISTS calculate_store_revenue(bigint);

SET citus.enable_repartition_joins = 'off';
