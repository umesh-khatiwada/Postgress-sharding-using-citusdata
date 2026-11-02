-- ============================================================================
-- Example 09: Columnar Storage
-- Schema Definition: Pure Columnar, Heap, and Mixed Hot/Cold Partitions
-- ============================================================================

-- 1. Ensure Citus and Columnar extensions are loaded
CREATE EXTENSION IF NOT EXISTS citus;

DO $$
BEGIN
    SET citus.enable_ddl_propagation = off;
    CREATE EXTENSION IF NOT EXISTS citus_columnar;
    RESET citus.enable_ddl_propagation;
END $$;

SET citus.shard_count = 4;

-- ----------------------------------------------------------------------------
-- 2. Pure Columnar Distributed Table (USING columnar)
-- ----------------------------------------------------------------------------
-- Stores rows column-wise in compressed stripes (zstd/lz4/pglz).
-- Optimizes analytical queries selecting a subset of columns over millions of rows.
CREATE TABLE IF NOT EXISTS historical_sales_columnar (
    store_id int NOT NULL,
    order_id bigint NOT NULL,
    customer_id bigint NOT NULL,
    category text NOT NULL,
    quantity int NOT NULL,
    unit_price numeric(10,2) NOT NULL,
    total_amount numeric(10,2) NOT NULL,
    order_date date NOT NULL,
    status text NOT NULL,
    notes text
) USING columnar;

-- Configure Columnar Storage Options (zstd level 3 compression, 50,000 rows per stripe)
SELECT alter_columnar_table_set(
    'historical_sales_columnar',
    compression => 'zstd',
    compression_level => 3,
    stripe_row_limit => 50000
);

-- Distribute table on store_id
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM citus_tables WHERE table_name = 'historical_sales_columnar'::regclass) THEN
        PERFORM create_distributed_table('historical_sales_columnar', 'store_id', colocate_with => 'none');
    END IF;
END $$;

-- ----------------------------------------------------------------------------
-- 3. Row-Oriented (Heap) Distributed Table (For Benchmark Comparison)
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS historical_sales_heap (
    store_id int NOT NULL,
    order_id bigint NOT NULL,
    customer_id bigint NOT NULL,
    category text NOT NULL,
    quantity int NOT NULL,
    unit_price numeric(10,2) NOT NULL,
    total_amount numeric(10,2) NOT NULL,
    order_date date NOT NULL,
    status text NOT NULL,
    notes text
) USING heap;

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM citus_tables WHERE table_name = 'historical_sales_heap'::regclass) THEN
        PERFORM create_distributed_table('historical_sales_heap', 'store_id', colocate_with => 'none');
    END IF;
END $$;

-- ----------------------------------------------------------------------------
-- 4. Mixed Hot (Row) and Cold (Columnar) Partitioned Table
-- ----------------------------------------------------------------------------
-- Architecture pattern:
-- - Active current partition uses standard heap (supports singleton UPDATE/DELETE)
-- - Historical partitions use columnar (compressed 3x-6x, fast aggregation scans)
CREATE TABLE IF NOT EXISTS partitioned_order_ledger (
    store_id int NOT NULL,
    order_id bigint NOT NULL,
    order_date date NOT NULL,
    amount numeric(10,2) NOT NULL,
    status text NOT NULL,
    notes text,
    PRIMARY KEY (store_id, order_date, order_id)
) PARTITION BY RANGE (order_date);

-- Hot Partition: Active current month (heap)
CREATE TABLE IF NOT EXISTS ledger_hot_2026_11 PARTITION OF partitioned_order_ledger
    FOR VALUES FROM ('2026-11-01') TO ('2026-12-01')
    USING heap;

-- Cold Partition: Prior closed month (columnar with zstd)
CREATE TABLE IF NOT EXISTS ledger_cold_2026_10 PARTITION OF partitioned_order_ledger
    FOR VALUES FROM ('2026-10-01') TO ('2026-11-01')
    USING columnar;

-- Distribute partitioned table on store_id
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM citus_tables WHERE table_name = 'partitioned_order_ledger'::regclass) THEN
        PERFORM create_distributed_table('partitioned_order_ledger', 'store_id', colocate_with => 'none');
    END IF;
END $$;
