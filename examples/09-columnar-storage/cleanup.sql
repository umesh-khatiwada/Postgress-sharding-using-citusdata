-- ============================================================================
-- Example 09: Columnar Storage
-- Teardown and Cleanup Script
-- ============================================================================

DROP TABLE IF EXISTS partitioned_order_ledger CASCADE;
DROP TABLE IF EXISTS historical_sales_columnar CASCADE;
DROP TABLE IF EXISTS historical_sales_heap CASCADE;
