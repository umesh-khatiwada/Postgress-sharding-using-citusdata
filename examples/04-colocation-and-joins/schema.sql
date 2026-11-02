-- ==============================================================================
-- 04-colocation-and-joins: Schema Definition
-- Authoritative Docs: https://docs.citusdata.com/en/v14.2/sharding/data_modeling.html#table-colocation
-- ==============================================================================

-- 1. Drop existing demo objects
DROP TABLE IF EXISTS store_orders_archive CASCADE;
DROP TABLE IF EXISTS order_items CASCADE;
DROP TABLE IF EXISTS store_orders CASCADE;
DROP TABLE IF EXISTS warehouse_inventory CASCADE;
DROP FUNCTION IF EXISTS calculate_store_revenue(bigint);

-- ==============================================================================
-- 2. Co-located Distributed Tables
-- `store_orders` and `order_items` are both distributed by `store_id`.
-- When tables share the same distribution key type and colocation group,
-- Citus guarantees that shard N of `store_orders` and shard N of `order_items`
-- live on the exact same physical PostgreSQL worker!
-- ==============================================================================

CREATE TABLE store_orders (
    store_id bigint NOT NULL,
    order_id bigint NOT NULL,
    customer_id bigint NOT NULL,
    order_status text NOT NULL DEFAULT 'completed',
    order_date date NOT NULL DEFAULT CURRENT_DATE,
    total_amount numeric(10, 2) NOT NULL,
    PRIMARY KEY (store_id, order_id)
);
SELECT create_distributed_table('store_orders', 'store_id');

CREATE TABLE order_items (
    store_id bigint NOT NULL,
    item_id bigint NOT NULL,
    order_id bigint NOT NULL,
    sku text NOT NULL,
    quantity integer NOT NULL,
    unit_price numeric(10, 2) NOT NULL,
    PRIMARY KEY (store_id, item_id),
    CONSTRAINT fk_items_order FOREIGN KEY (store_id, order_id) REFERENCES store_orders(store_id, order_id) ON DELETE CASCADE
);
-- Explicitly co-locate with store_orders
SELECT create_distributed_table('order_items', 'store_id', colocate_with => 'store_orders');

-- Target archive table for co-located INSERT..SELECT demonstrations
CREATE TABLE store_orders_archive (
    store_id bigint NOT NULL,
    order_id bigint NOT NULL,
    archived_at timestamptz NOT NULL DEFAULT now(),
    total_amount numeric(10, 2) NOT NULL,
    PRIMARY KEY (store_id, order_id)
);
SELECT create_distributed_table('store_orders_archive', 'store_id', colocate_with => 'store_orders');


-- ==============================================================================
-- 3. Non-Colocated Distributed Table
-- `warehouse_inventory` is distributed by `warehouse_id` (a completely different entity).
-- Joining `store_orders` with `warehouse_inventory` is a NON-colocated join,
-- requiring data to be dynamically repartitioned across the cluster network.
-- ==============================================================================

CREATE TABLE warehouse_inventory (
    warehouse_id bigint NOT NULL,
    sku text NOT NULL,
    quantity_available integer NOT NULL,
    aisle_bay text NOT NULL,
    PRIMARY KEY (warehouse_id, sku)
);
-- Explicitly set colocate_with => 'none' to demonstrate non-colocated behavior
SELECT create_distributed_table('warehouse_inventory', 'warehouse_id', colocate_with => 'none');


-- ==============================================================================
-- 4. Distributed Function (create_distributed_function)
-- Functions can be distributed to execute directly on the worker node holding
-- a specific tenant or partition's data.
-- ==============================================================================

CREATE OR REPLACE FUNCTION calculate_store_revenue(p_store_id bigint)
RETURNS numeric AS $$
    SELECT coalesce(sum(total_amount), 0.00)::numeric
    FROM store_orders
    WHERE store_id = p_store_id;
$$ LANGUAGE sql;

-- Tell Citus to distribute the function definition to all workers and route
-- calls by p_store_id to the worker holding that store's shard
SELECT create_distributed_function('calculate_store_revenue(bigint)', 'p_store_id', colocate_with => 'store_orders');
