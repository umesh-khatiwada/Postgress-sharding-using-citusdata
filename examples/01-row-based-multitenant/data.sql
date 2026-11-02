-- ==============================================================================
-- 01-row-based-multitenant: Seed Data
-- ==============================================================================

-- 1. Insert Tenants (IDs: 1, 2, 3, 4)
INSERT INTO tenants (name, slug, plan) VALUES
    ('Acme Corporation',   'acme',    'enterprise'),
    ('Globex Logistics',   'globex',  'growth'),
    ('Soylent Health',     'soylent', 'standard'),
    ('Initech Software',   'initech', 'free');

-- 2. Insert Users for each tenant
-- Tenant 1 (Acme)
INSERT INTO users (tenant_id, id, email, name, role) VALUES
    (1, 101, 'alice@acme.com',   'Alice Smith',   'owner'),
    (1, 102, 'bob@acme.com',     'Bob Jones',     'admin'),
    (1, 103, 'charlie@acme.com', 'Charlie Brown', 'member');

-- Tenant 2 (Globex)
INSERT INTO users (tenant_id, id, email, name, role) VALUES
    (2, 201, 'diana@globex.com', 'Diana Prince', 'owner'),
    (2, 202, 'evan@globex.com',  'Evan Wright',  'member');

-- Tenant 3 (Soylent)
INSERT INTO users (tenant_id, id, email, name, role) VALUES
    (3, 301, 'frank@soylent.com', 'Frank Castle', 'owner'),
    (3, 302, 'grace@soylent.com', 'Grace Hopper', 'admin');

-- Tenant 4 (Initech)
INSERT INTO users (tenant_id, id, email, name, role) VALUES
    (4, 401, 'peter@initech.com', 'Peter Gibbons', 'owner');

-- 3. Insert Projects
-- Tenant 1
INSERT INTO projects (tenant_id, id, name, description, status) VALUES
    (1, 11, 'NextGen SaaS Platform', 'Migrating monolithic stack to distributed PostgreSQL', 'active'),
    (1, 12, 'Mobile Client v2',      'Native iOS and Android client refresh',                'active');

-- Tenant 2
INSERT INTO projects (tenant_id, id, name, description, status) VALUES
    (2, 21, 'Fleet GPS Tracking', 'Real-time telemetry ingestion pipeline', 'active'),
    (2, 22, 'Driver Mobile App',   'Turn-by-turn routing companion',         'active');

-- Tenant 3
INSERT INTO projects (tenant_id, id, name, description, status) VALUES
    (3, 31, 'Clinical Trials Portal', 'Patient registry and trial telemetry', 'active');

-- Tenant 4
INSERT INTO projects (tenant_id, id, name, description, status) VALUES
    (4, 41, 'TPS Reporting System', 'Automated cover sheet compliance tool', 'completed');

-- 4. Insert Tasks
-- Tenant 1 (Acme)
INSERT INTO tasks (tenant_id, id, project_id, assigned_to_user_id, title, status, priority, due_date) VALUES
    (1, 1001, 11, 101, 'Design distributed schema with composite keys', 'done',        'high',   CURRENT_DATE - 7),
    (1, 1002, 11, 102, 'Implement Row-Level Security policies',         'done',        'high',   CURRENT_DATE - 3),
    (1, 1003, 11, 103, 'Benchmark single-shard vs cross-shard queries', 'in_progress', 'urgent', CURRENT_DATE + 2),
    (1, 1004, 11, 101, 'Configure PgBouncer session pooling',          'todo',        'medium', CURRENT_DATE + 5),
    (1, 1005, 12, 103, 'Refactor offline sync engine',                 'in_progress', 'high',   CURRENT_DATE + 4),
    (1, 1006, 12, 102, 'Setup push notification dispatchers',          'todo',        'low',    CURRENT_DATE + 10);

-- Tenant 2 (Globex)
INSERT INTO tasks (tenant_id, id, project_id, assigned_to_user_id, title, status, priority, due_date) VALUES
    (2, 2001, 21, 201, 'Calibrate GPS geofence alerts',       'done',        'high',   CURRENT_DATE - 2),
    (2, 2002, 21, 202, 'Kafka telemetry consumer pipeline',   'in_progress', 'urgent', CURRENT_DATE + 1),
    (2, 2003, 22, 202, 'Bluetooth OBD-II reader integration', 'todo',        'medium', CURRENT_DATE + 8),
    (2, 2004, 22, 201, 'Driver dispatch UI styling',          'in_progress', 'low',    CURRENT_DATE + 3);

-- Tenant 3 (Soylent)
INSERT INTO tasks (tenant_id, id, project_id, assigned_to_user_id, title, status, priority, due_date) VALUES
    (3, 3001, 31, 301, 'HIPAA compliance audit checklist', 'done',        'urgent', CURRENT_DATE - 10),
    (3, 3002, 31, 302, 'Patient anonymization filter',     'in_progress', 'high',   CURRENT_DATE + 3),
    (3, 3003, 31, 301, 'Export data in FHIR standard',      'todo',        'medium', CURRENT_DATE + 14);

-- Tenant 4 (Initech)
INSERT INTO tasks (tenant_id, id, project_id, assigned_to_user_id, title, status, priority, due_date) VALUES
    (4, 4001, 41, 401, 'Attach new TPS cover sheet format', 'done', 'urgent', CURRENT_DATE - 30),
    (4, 4002, 41, 401, 'Submit status memorandum to Lumbergh', 'done', 'low', CURRENT_DATE - 28);

-- 5. Insert Events (Audit Log)
INSERT INTO events (tenant_id, id, user_id, event_type, payload) VALUES
    (1, 5001, 101, 'user.login',        '{"ip": "192.168.1.10", "client": "web"}'),
    (1, 5002, 101, 'project.created',   '{"project_id": 11, "name": "NextGen SaaS Platform"}'),
    (1, 5003, 102, 'task.assigned',     '{"task_id": 1003, "assignee": "charlie"}'),
    (1, 5004, 103, 'task.status_update', '{"task_id": 1003, "from": "todo", "to": "in_progress"}'),
    (2, 5005, 201, 'user.login',        '{"ip": "10.0.0.5", "client": "mobile"}'),
    (2, 5006, 202, 'telemetry.alert',   '{"vehicle_id": "TRK-402", "speed_kmh": 115}'),
    (3, 5007, 301, 'patient.registered', '{"patient_uuid": "f81d4fae-7dec-11d0-a765-00a0c91e6bf6"}'),
    (4, 5008, 401, 'tps_report.sent',   '{"copies": 8, "cover_sheet": true}');
