-- ==============================================================================
-- 03-reference-and-local-tables: Schema Definition
-- Authoritative Docs: https://docs.citusdata.com/en/v14.2/develop/reference_tables.html
-- ==============================================================================

-- 1. Drop existing demo tables if present
DROP TABLE IF EXISTS subscriptions CASCADE;
DROP TABLE IF EXISTS countries CASCADE;
DROP TABLE IF EXISTS currencies CASCADE;
DROP TABLE IF EXISTS plans CASCADE;
DROP TABLE IF EXISTS admin_audit_logs CASCADE;
DROP TABLE IF EXISTS global_system_settings CASCADE;

-- ==============================================================================
-- 2. Reference Tables (Replicated to All Nodes)
-- Reference tables store small, slowly-changing lookup data (such as currencies,
-- countries, tax codes, and subscription plans).
-- Citus replicates reference tables to EVERY node in the cluster (coordinator + all workers),
-- enabling distributed tables to join with them locally without network hops!
-- ==============================================================================

CREATE TABLE currencies (
    code char(3) PRIMARY KEY,
    name text NOT NULL,
    symbol text NOT NULL,
    exchange_rate_usd numeric(12, 4) NOT NULL
);
SELECT create_reference_table('currencies');

CREATE TABLE countries (
    code char(2) PRIMARY KEY,
    name text NOT NULL,
    currency_code char(3) NOT NULL REFERENCES currencies(code),
    vat_rate numeric(5, 2) NOT NULL DEFAULT 0.00
);
SELECT create_reference_table('countries');

CREATE TABLE plans (
    id text PRIMARY KEY,
    name text NOT NULL,
    price_monthly numeric(10, 2) NOT NULL,
    max_users integer NOT NULL,
    features jsonb NOT NULL DEFAULT '{}'::jsonb
);
SELECT create_reference_table('plans');

-- ==============================================================================
-- 3. Distributed Table Referencing Reference Tables
-- Notice: Distributed tables can define foreign keys referencing reference tables!
-- Citus enforces foreign key validation across all cluster nodes.
-- ==============================================================================

CREATE TABLE subscriptions (
    tenant_id bigint NOT NULL,
    id bigint NOT NULL,
    plan_id text NOT NULL REFERENCES plans(id),
    currency_code char(3) NOT NULL REFERENCES currencies(code),
    billing_country char(2) NOT NULL REFERENCES countries(code),
    status text NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'past_due', 'canceled')),
    started_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (tenant_id, id)
);
SELECT create_distributed_table('subscriptions', 'tenant_id');

-- ==============================================================================
-- 4. Coordinator-Local Tables
-- Coordinator-local tables reside only on the coordinator.
-- Calling `citus_add_local_table_to_metadata` allows the Citus distributed planner
-- to safely query and join them with reference tables and distributed tables.
-- ==============================================================================

CREATE TABLE admin_audit_logs (
    id bigserial PRIMARY KEY,
    admin_email text NOT NULL,
    action text NOT NULL,
    target_tenant_id bigint,
    metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at timestamptz NOT NULL DEFAULT now()
);
SELECT citus_add_local_table_to_metadata('admin_audit_logs');

CREATE TABLE global_system_settings (
    setting_key text PRIMARY KEY,
    setting_value text NOT NULL,
    updated_at timestamptz NOT NULL DEFAULT now()
);
SELECT citus_add_local_table_to_metadata('global_system_settings');
