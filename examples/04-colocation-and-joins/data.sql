-- ==============================================================================
-- 04-colocation-and-joins: Seed Data
-- ==============================================================================

-- 1. Orders across 3 Stores
INSERT INTO store_orders (store_id, order_id, customer_id, order_status, total_amount) VALUES
    (1, 101, 501, 'completed', 150.00),
    (1, 102, 502, 'completed',  85.50),
    (1, 103, 503, 'completed', 320.00),
    (1, 104, 504, 'completed',  45.00),
    (2, 201, 601, 'completed', 210.00),
    (2, 202, 602, 'completed', 115.00),
    (2, 203, 603, 'completed', 540.00),
    (2, 204, 604, 'completed',  95.00),
    (3, 301, 701, 'completed',  65.00),
    (3, 302, 702, 'completed', 410.00),
    (3, 303, 703, 'completed', 180.00),
    (3, 304, 704, 'completed', 290.00);

-- 2. Line Items for Orders (Co-located with orders on store_id)
INSERT INTO order_items (store_id, item_id, order_id, sku, quantity, unit_price) VALUES
    (1, 1001, 101, 'SKU-LAPTOP-01',  1, 150.00),
    (1, 1002, 102, 'SKU-MOUSE-02',   2,  42.75),
    (1, 1003, 103, 'SKU-MONITOR-03', 1, 320.00),
    (1, 1004, 104, 'SKU-KEYBRD-04',  1,  45.00),
    (2, 2001, 201, 'SKU-LAPTOP-01',  1, 150.00),
    (2, 2002, 201, 'SKU-MOUSE-02',   1,  60.00),
    (2, 2003, 202, 'SKU-HEADSET-05', 1, 115.00),
    (2, 2004, 203, 'SKU-CHAIR-06',   2, 270.00),
    (2, 2005, 204, 'SKU-KEYBRD-04',  2,  47.50),
    (3, 3001, 301, 'SKU-MOUSE-02',   1,  65.00),
    (3, 3002, 302, 'SKU-MONITOR-03', 1, 320.00),
    (3, 3003, 302, 'SKU-KEYBRD-04',  2,  45.00),
    (3, 3004, 303, 'SKU-HEADSET-05', 1, 180.00),
    (3, 3005, 304, 'SKU-CHAIR-06',   1, 290.00);

-- 3. Non-Colocated Data: Warehouse Inventory (Distributed by warehouse_id)
INSERT INTO warehouse_inventory (warehouse_id, sku, quantity_available, aisle_bay) VALUES
    (10, 'SKU-LAPTOP-01',  45, 'A-12-3'),
    (10, 'SKU-MOUSE-02',  120, 'B-04-1'),
    (10, 'SKU-MONITOR-03', 30, 'C-08-2'),
    (10, 'SKU-KEYBRD-04',  85, 'B-05-4'),
    (20, 'SKU-HEADSET-05', 60, 'D-02-1'),
    (20, 'SKU-CHAIR-06',   15, 'E-01-1'),
    (20, 'SKU-LAPTOP-01',  20, 'A-01-2'),
    (20, 'SKU-MOUSE-02',   50, 'B-02-3');
