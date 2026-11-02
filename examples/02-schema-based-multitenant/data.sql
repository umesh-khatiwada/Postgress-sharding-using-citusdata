-- ==============================================================================
-- 02-schema-based-multitenant: Seed Data
-- ==============================================================================

-- 1. Seed Tenant Acme
INSERT INTO tenant_acme.users (name, email) VALUES
    ('Alice Smith',   'alice@acme.com'),
    ('Bob Jones',     'bob@acme.com');

INSERT INTO tenant_acme.orders (user_id, total_amount, status) VALUES
    (1, 1250.00, 'completed'),
    (1,  450.50, 'pending'),
    (2, 3100.00, 'completed');

-- 2. Seed Tenant Globex
INSERT INTO tenant_globex.users (name, email) VALUES
    ('Diana Prince',  'diana@globex.com'),
    ('Evan Wright',   'evan@globex.com');

INSERT INTO tenant_globex.orders (user_id, total_amount, status) VALUES
    (1, 890.00, 'completed'),
    (2, 120.00, 'canceled');

-- 3. Seed Tenant Soylent
INSERT INTO tenant_soylent.users (name, email) VALUES
    ('Frank Castle',  'frank@soylent.com'),
    ('Grace Hopper',  'grace@soylent.com');

INSERT INTO tenant_soylent.orders (user_id, total_amount, status) VALUES
    (1, 5400.00, 'completed'),
    (2,  750.25, 'completed');
