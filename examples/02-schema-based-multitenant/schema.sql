-- ==============================================================================
-- 02-schema-based-multitenant: Schema-Per-Tenant Architecture
-- Authoritative Docs: https://docs.citusdata.com/en/v14.2/use_cases/schema_sharding.html
-- ==============================================================================

-- 1. Enable schema-based sharding in Citus.
--    When enabled, any newly created schema is automatically distributed across
--    worker nodes as a single co-located shard group.
SET citus.enable_schema_based_sharding = 'on';

-- 2. Drop existing tenant schemas if recreating
DROP SCHEMA IF EXISTS tenant_acme CASCADE;
DROP SCHEMA IF EXISTS tenant_globex CASCADE;
DROP SCHEMA IF EXISTS tenant_soylent CASCADE;

-- 3. Create Tenant Schemas
--    Citus automatically intercepts CREATE SCHEMA and assigns each schema to an active worker.
CREATE SCHEMA tenant_acme;
CREATE SCHEMA tenant_globex;
CREATE SCHEMA tenant_soylent;

-- ==============================================================================
-- 4. Create Tables inside Tenant Schemas
-- KEY ADVANTAGE OVER ROW-BASED SHARDING:
-- Tables DO NOT require a `tenant_id` column.
-- Tables DO NOT require composite primary or foreign keys.
-- You can write standard, unmodified single-node PostgreSQL DDL!
-- ==============================================================================

-- Tenant 1: Acme
CREATE TABLE tenant_acme.users (
    id bigserial PRIMARY KEY,
    name text NOT NULL,
    email text UNIQUE NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE tenant_acme.orders (
    id bigserial PRIMARY KEY,
    user_id bigint NOT NULL REFERENCES tenant_acme.users(id) ON DELETE CASCADE,
    total_amount numeric(10, 2) NOT NULL,
    status text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'completed', 'canceled')),
    created_at timestamptz NOT NULL DEFAULT now()
);

-- Tenant 2: Globex
CREATE TABLE tenant_globex.users (
    id bigserial PRIMARY KEY,
    name text NOT NULL,
    email text UNIQUE NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE tenant_globex.orders (
    id bigserial PRIMARY KEY,
    user_id bigint NOT NULL REFERENCES tenant_globex.users(id) ON DELETE CASCADE,
    total_amount numeric(10, 2) NOT NULL,
    status text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'completed', 'canceled')),
    created_at timestamptz NOT NULL DEFAULT now()
);

-- Tenant 3: Soylent
CREATE TABLE tenant_soylent.users (
    id bigserial PRIMARY KEY,
    name text NOT NULL,
    email text UNIQUE NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE tenant_soylent.orders (
    id bigserial PRIMARY KEY,
    user_id bigint NOT NULL REFERENCES tenant_soylent.users(id) ON DELETE CASCADE,
    total_amount numeric(10, 2) NOT NULL,
    status text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'completed', 'canceled')),
    created_at timestamptz NOT NULL DEFAULT now()
);
