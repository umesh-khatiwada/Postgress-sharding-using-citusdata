-- ==============================================================================
-- Example 10: Normal PostgreSQL vs Citus Distributed PostgreSQL (1M Benchmark)
-- Schema Definition
-- ==============================================================================

-- 1. Ensure Citus extension is enabled and coordinator host is set
CREATE EXTENSION IF NOT EXISTS citus;
SELECT citus_set_coordinator_host('citus_coordinator', 5432);

-- 2. Drop existing benchmark tables if they exist
DROP TABLE IF EXISTS citus_transactions CASCADE;
DROP TABLE IF EXISTS normal_transactions CASCADE;
DROP TABLE IF EXISTS merchants CASCADE;

-- 3. Configure shard count for Citus distributed tables
--    In production, shard count defaults to 32 or 64. For this multi-worker benchmark,
--    8 shards provides an even, parallel distribution across all active workers.
SET citus.shard_count = 8;
SET citus.shard_replication_factor = 1;

-- 4. Create Dimension / Reference Table: merchants
--    This table models merchants across different countries and industry categories.
--    In Citus, reference tables are replicated to every worker node, allowing
--    distributed queries to perform fast local joins without network data reshuffling.
CREATE TABLE merchants (
    merchant_id INT PRIMARY KEY,
    name VARCHAR(100) NOT NULL,
    category VARCHAR(50) NOT NULL,
    country VARCHAR(3) NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Distribute merchants as a Citus Reference Table
SELECT create_reference_table('merchants');

-- 5. Create Baseline: Standard Unsharded PostgreSQL Table (normal_transactions)
--    Stored entirely on the local coordinator node as a standard PostgreSQL heap table.
CREATE TABLE normal_transactions (
    transaction_id BIGINT NOT NULL,
    account_id INT NOT NULL,
    merchant_id INT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL,
    amount NUMERIC(10,2) NOT NULL,
    transaction_type VARCHAR(20) NOT NULL,
    status VARCHAR(20) NOT NULL,
    PRIMARY KEY (account_id, transaction_id)
);

-- 6. Create Sharded: Citus Distributed Table (citus_transactions)
--    Identical schema to normal_transactions, but partitioned by hash on account_id.
CREATE TABLE citus_transactions (
    transaction_id BIGINT NOT NULL,
    account_id INT NOT NULL,
    merchant_id INT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL,
    amount NUMERIC(10,2) NOT NULL,
    transaction_type VARCHAR(20) NOT NULL,
    status VARCHAR(20) NOT NULL,
    PRIMARY KEY (account_id, transaction_id)
);

-- Distribute citus_transactions across worker nodes by account_id
SELECT create_distributed_table('citus_transactions', 'account_id');

-- 7. Secondary Indexes
--    Create identical indexes on both tables to ensure fair comparisons on indexed queries.
--    Citus automatically propagates DDL index creation to all distributed worker shards!
CREATE INDEX idx_normal_created_at ON normal_transactions (created_at);
CREATE INDEX idx_normal_merchant_id ON normal_transactions (merchant_id);
CREATE INDEX idx_normal_status ON normal_transactions (status);

CREATE INDEX idx_citus_created_at ON citus_transactions (created_at);
CREATE INDEX idx_citus_merchant_id ON citus_transactions (merchant_id);
CREATE INDEX idx_citus_status ON citus_transactions (status);
