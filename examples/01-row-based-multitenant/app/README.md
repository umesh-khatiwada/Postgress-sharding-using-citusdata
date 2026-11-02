# Multi-Tenant Python Demo App (Psycopg 3)

This application demonstrates how a backend service (e.g. FastAPI, Django, Flask, Express, or Spring) connects to a Citus cluster using a shared connection pool and enforces tenant isolation via Row-Level Security.

## Prerequisites
- Citus cluster running: `make up`
- Schema and seed data loaded: `make verify-01`
- Python 3.10+

## Installation
```bash
# Optional: create virtual environment
python3 -m venv .venv
source .venv/bin/activate

# Install psycopg 3
pip install -r requirements.txt
```

## Running the App
```bash
python3 app.py
```

## What it Demonstrates
1. **Transaction-Scoped Tenant Context**: Using `SET LOCAL app.tenant_id = %s;` within a transaction.
2. **Local Propagation**: `SET citus.propagate_set_commands = 'local';` propagates the session setting to the worker node executing the shard query.
3. **Automatic RLS Filtering**: Running `SELECT * FROM tasks` automatically filters tasks for that tenant.
4. **Write Isolation Breach Prevention**: Attempting to insert a task belonging to `tenant_id = 2` while authenticated as `tenant_id = 1` triggers a PostgreSQL RLS check violation.
