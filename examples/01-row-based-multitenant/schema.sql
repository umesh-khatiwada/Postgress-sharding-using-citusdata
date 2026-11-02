-- ==============================================================================
-- 01-row-based-multitenant: Schema Definition
-- SaaS Multi-Tenant Architecture with Composite Keys & Co-located Distribution
-- Authoritative Docs: https://docs.citusdata.com/en/v14.2/use_cases/multi_tenant.html
-- ==============================================================================

-- 1. Create an unprivileged application role for Row-Level Security (RLS) enforcement.
--    In PostgreSQL, superusers bypass RLS. Production SaaS apps connect as an unprivileged
--    role so the database engine strictly enforces RLS policies.
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'tenant_app_user') THEN
        CREATE ROLE tenant_app_user NOSUPERUSER NOCREATEDB NOCREATEROLE LOGIN PASSWORD 'tenant_app_password';
        RAISE NOTICE 'Created application role: tenant_app_user';
    END IF;
END $$;

-- 2. Clean teardown of existing demo tables if present
DROP TABLE IF EXISTS events CASCADE;
DROP TABLE IF EXISTS tasks CASCADE;
DROP TABLE IF EXISTS projects CASCADE;
DROP TABLE IF EXISTS users CASCADE;
DROP TABLE IF EXISTS tenants CASCADE;

-- 3. Base Tenants Table
--    In a row-based multi-tenant model, `tenants` is distributed by its primary key `id`.
--    NOTE ON CONSTRAINTS: In Citus, distributed relations cannot have UNIQUE or PRIMARY KEY
--    constraints that do not include the distribution column. Therefore, `slug` cannot have
--    a standalone UNIQUE constraint unless `id` is part of the constraint (e.g. UNIQUE (id, slug))
--    or uniqueness is enforced via an application-level check / reference table.
CREATE TABLE tenants (
    id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    name text NOT NULL,
    slug text NOT NULL,
    plan text NOT NULL DEFAULT 'standard' CHECK (plan IN ('free', 'standard', 'growth', 'enterprise')),
    created_at timestamptz NOT NULL DEFAULT now()
);

-- 4. Users Table
--    RULE: Every distributed child table MUST include `tenant_id` in its PRIMARY KEY
--    and in any FOREIGN KEY relationships.
CREATE TABLE users (
    tenant_id bigint NOT NULL,
    id bigint NOT NULL,
    email text NOT NULL,
    name text NOT NULL,
    role text NOT NULL DEFAULT 'member' CHECK (role IN ('owner', 'admin', 'member', 'guest')),
    created_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (tenant_id, id),
    CONSTRAINT fk_users_tenant FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE
);

-- 5. Projects Table
CREATE TABLE projects (
    tenant_id bigint NOT NULL,
    id bigint NOT NULL,
    name text NOT NULL,
    description text,
    status text NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'archived', 'completed')),
    created_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (tenant_id, id),
    CONSTRAINT fk_projects_tenant FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE
);

-- 6. Tasks Table
--    Notice composite foreign keys: (tenant_id, project_id) references projects(tenant_id, id)
--    and (tenant_id, assigned_to_user_id) references users(tenant_id, id).
--    This guarantees referential integrity strictly within the SAME tenant shard!
CREATE TABLE tasks (
    tenant_id bigint NOT NULL,
    id bigint NOT NULL,
    project_id bigint NOT NULL,
    assigned_to_user_id bigint,
    title text NOT NULL,
    status text NOT NULL DEFAULT 'todo' CHECK (status IN ('todo', 'in_progress', 'review', 'done')),
    priority text NOT NULL DEFAULT 'medium' CHECK (priority IN ('low', 'medium', 'high', 'urgent')),
    due_date date,
    created_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (tenant_id, id),
    CONSTRAINT fk_tasks_project FOREIGN KEY (tenant_id, project_id) REFERENCES projects(tenant_id, id) ON DELETE CASCADE,
    -- Note on ON DELETE SET NULL: Citus does not allow ON DELETE SET NULL or SET DEFAULT
    -- when the distribution column (tenant_id) is part of the foreign key constraint.
    -- Supported actions are ON DELETE CASCADE, RESTRICT, or NO ACTION.
    CONSTRAINT fk_tasks_user FOREIGN KEY (tenant_id, assigned_to_user_id) REFERENCES users(tenant_id, id) ON DELETE RESTRICT
);

-- 7. Events Table (Audit / Activity Stream)
CREATE TABLE events (
    tenant_id bigint NOT NULL,
    id bigint NOT NULL,
    user_id bigint,
    event_type text NOT NULL,
    payload jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (tenant_id, id),
    CONSTRAINT fk_events_user FOREIGN KEY (tenant_id, user_id) REFERENCES users(tenant_id, id) ON DELETE CASCADE
);

-- Indexes on foreign keys and frequent query filters
CREATE INDEX idx_users_email ON users(tenant_id, email);
CREATE INDEX idx_tasks_project ON tasks(tenant_id, project_id);
CREATE INDEX idx_tasks_assigned ON tasks(tenant_id, assigned_to_user_id);
CREATE INDEX idx_tasks_status ON tasks(tenant_id, status);
CREATE INDEX idx_events_type ON events(tenant_id, event_type);

-- ==============================================================================
-- 8. Citus Distribution & Co-location
-- ==============================================================================

-- Distribute root table `tenants` by `id`
SELECT create_distributed_table('tenants', 'id');

-- Distribute child tables by `tenant_id` and explicitly co-locate with `tenants`.
-- Co-location guarantees that all rows with the same `tenant_id` across tenants,
-- users, projects, tasks, and events live on the EXACT same worker and shard!
SELECT create_distributed_table('users', 'tenant_id', colocate_with => 'tenants');
SELECT create_distributed_table('projects', 'tenant_id', colocate_with => 'tenants');
SELECT create_distributed_table('tasks', 'tenant_id', colocate_with => 'tenants');
SELECT create_distributed_table('events', 'tenant_id', colocate_with => 'tenants');

-- ==============================================================================
-- 9. Row-Level Security (RLS) Policies
-- ==============================================================================

-- Grant permissions to application role
GRANT USAGE ON SCHEMA public TO tenant_app_user;
GRANT ALL ON ALL TABLES IN SCHEMA public TO tenant_app_user;
GRANT ALL ON ALL SEQUENCES IN SCHEMA public TO tenant_app_user;

-- Enable Row-Level Security on all multi-tenant tables
ALTER TABLE users ENABLE ROW LEVEL SECURITY;
ALTER TABLE projects ENABLE ROW LEVEL SECURITY;
ALTER TABLE tasks ENABLE ROW LEVEL SECURITY;
ALTER TABLE events ENABLE ROW LEVEL SECURITY;

-- Define tenant isolation policies using current_setting('app.tenant_id', true).
-- The USING clause filters SELECT, UPDATE, DELETE queries.
-- The WITH CHECK clause prevents INSERT or UPDATE with a mismatched tenant_id.
CREATE POLICY tenant_isolation_users ON users
    FOR ALL
    USING (tenant_id = NULLIF(current_setting('app.tenant_id', true), '')::bigint)
    WITH CHECK (tenant_id = NULLIF(current_setting('app.tenant_id', true), '')::bigint);

CREATE POLICY tenant_isolation_projects ON projects
    FOR ALL
    USING (tenant_id = NULLIF(current_setting('app.tenant_id', true), '')::bigint)
    WITH CHECK (tenant_id = NULLIF(current_setting('app.tenant_id', true), '')::bigint);

CREATE POLICY tenant_isolation_tasks ON tasks
    FOR ALL
    USING (tenant_id = NULLIF(current_setting('app.tenant_id', true), '')::bigint)
    WITH CHECK (tenant_id = NULLIF(current_setting('app.tenant_id', true), '')::bigint);

CREATE POLICY tenant_isolation_events ON events
    FOR ALL
    USING (tenant_id = NULLIF(current_setting('app.tenant_id', true), '')::bigint)
    WITH CHECK (tenant_id = NULLIF(current_setting('app.tenant_id', true), '')::bigint);
