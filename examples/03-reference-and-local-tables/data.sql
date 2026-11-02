-- ==============================================================================
-- 03-reference-and-local-tables: Seed Data
-- ==============================================================================

-- 1. Reference Data: Currencies
-- Writes to reference tables use Two-Phase Commit (2PC) across all nodes.
INSERT INTO currencies (code, name, symbol, exchange_rate_usd) VALUES
    ('USD', 'US Dollar',       '$', 1.0000),
    ('EUR', 'Euro',            '€', 1.0850),
    ('GBP', 'British Pound',   '£', 1.2650),
    ('JPY', 'Japanese Yen',    '¥', 0.0067),
    ('CAD', 'Canadian Dollar', '$', 0.7400);

-- 2. Reference Data: Countries
INSERT INTO countries (code, name, currency_code, vat_rate) VALUES
    ('US', 'United States', 'USD',  0.00),
    ('DE', 'Germany',       'EUR', 19.00),
    ('FR', 'France',        'EUR', 20.00),
    ('GB', 'United Kingdom','GBP', 20.00),
    ('JP', 'Japan',         'JPY', 10.00);

-- 3. Reference Data: Subscription Plans
INSERT INTO plans (id, name, price_monthly, max_users, features) VALUES
    ('free',       'Free Tier',          0.00,    2, '{"api_access": false, "sla": "community"}'),
    ('starter',    'Starter Team',      49.00,   10, '{"api_access": true,  "sla": "99.0%"}'),
    ('growth',     'Growth Business',  199.00,   50, '{"api_access": true,  "sla": "99.9%"}'),
    ('enterprise', 'Enterprise Custom', 899.00, 1000, '{"api_access": true,  "sla": "99.99%"}');

-- 4. Distributed Data: Tenant Subscriptions
INSERT INTO subscriptions (tenant_id, id, plan_id, currency_code, billing_country, status) VALUES
    (1, 101, 'enterprise', 'USD', 'US', 'active'),
    (2, 201, 'growth',     'EUR', 'DE', 'active'),
    (3, 301, 'starter',    'GBP', 'GB', 'active'),
    (4, 401, 'free',       'USD', 'US', 'active');

-- 5. Coordinator-Local Data: Platform Settings
INSERT INTO global_system_settings (setting_key, setting_value) VALUES
    ('maintenance_window', 'Sunday 02:00-04:00 UTC'),
    ('default_currency',   'USD'),
    ('max_failed_logins',  '5');

-- 6. Coordinator-Local Data: Admin Audit Logs
INSERT INTO admin_audit_logs (admin_email, action, target_tenant_id, metadata) VALUES
    ('admin@platform.io', 'plan.upgraded',     1, '{"old_plan": "growth", "new_plan": "enterprise"}'),
    ('admin@platform.io', 'currency.updated',   2, '{"billing_currency": "EUR"}'),
    ('support@platform.io', 'compliance.check', 3, '{"gdpr_verified": true}');
