-- ==============================================================================
-- Example 10: Normal PostgreSQL vs Citus Distributed PostgreSQL (1M Benchmark)
-- Cleanup Script
-- ==============================================================================

DROP TABLE IF EXISTS citus_transactions CASCADE;
DROP TABLE IF EXISTS normal_transactions CASCADE;
DROP TABLE IF EXISTS merchants CASCADE;

RESET citus.shard_count;
RESET citus.shard_replication_factor;
