#!/usr/bin/env python3
"""
Multi-Tenant SaaS Demo Application (Python / Psycopg 3)
Demonstrates session-level tenant switching, router queries, and RLS enforcement on Citus.
"""

import os
import sys

try:
    import psycopg
    from psycopg import sql
    from psycopg.rows import dict_row
except ImportError:
    print("Error: psycopg 3 is required. Install with: pip install 'psycopg[binary]'")
    sys.exit(1)

# Database connection configuration
DB_HOST = os.getenv("CITUS_HOST", "localhost")
DB_PORT = int(os.getenv("COORDINATOR_PORT", "5432"))
DB_NAME = os.getenv("POSTGRES_DB", "postgres")
DB_USER = os.getenv("APP_USER", "tenant_app_user")
DB_PASSWORD = os.getenv("APP_PASSWORD", "tenant_app_password")

DSN = f"host={DB_HOST} port={DB_PORT} dbname={DB_NAME} user={DB_USER} password={DB_PASSWORD}"


def set_tenant_context(cur, tenant_id: int):
    """
    Sets the active tenant ID for the current transaction.
    
    IMPORTANT CITUS DETAIL:
    Citus intercepts and propagates `SET LOCAL ...` utility statements to worker nodes
    when `citus.propagate_set_commands = 'local'`.
    Because PostgreSQL does not allow parameterized prepared statements ($1) for `SET`,
    we use `psycopg.sql.Literal` to safely escape the tenant identifier without risk of SQL injection.
    """
    cur.execute("SET citus.propagate_set_commands = 'local';")
    cur.execute(sql.SQL("SET LOCAL app.tenant_id = {};").format(sql.Literal(str(tenant_id))))


def list_tenant_tasks(conn, tenant_id: int):
    """
    Executes a query under the scope of a specific tenant.
    Demonstrates setting session context per transaction.
    """
    with conn.transaction():
        with conn.cursor(row_factory=dict_row) as cur:
            # 1. Set tenant context for this transaction
            set_tenant_context(cur, tenant_id)

            # 2. Query tasks - RLS automatically isolates rows for this tenant
            cur.execute(
                """
                SELECT t.id, t.title, t.status, t.priority, p.name AS project_name
                FROM tasks t
                JOIN projects p ON t.tenant_id = p.tenant_id AND t.project_id = p.id
                ORDER BY t.id;
                """
            )
            tasks = cur.fetchall()
            print(f"\n[Tenant {tenant_id}] Found {len(tasks)} visible tasks:")
            for task in tasks:
                print(f"  - [{task['status'].upper()}] {task['title']} (Project: {task['project_name']}, Priority: {task['priority']})")
            return tasks


def create_tenant_task(conn, tenant_id: int, task_id: int, project_id: int, title: str):
    """
    Inserts a task within the tenant context.
    """
    with conn.transaction():
        with conn.cursor() as cur:
            set_tenant_context(cur, tenant_id)

            cur.execute(
                """
                INSERT INTO tasks (tenant_id, id, project_id, title, status, priority)
                VALUES (%s, %s, %s, %s, 'todo', 'medium')
                ON CONFLICT (tenant_id, id) DO UPDATE SET title = EXCLUDED.title;
                """,
                (tenant_id, task_id, project_id, title),
            )
            print(f"\n[Tenant {tenant_id}] Successfully created task {task_id}: '{title}'")


def attempt_cross_tenant_exploit(conn, authenticated_tenant_id: int, target_tenant_id: int):
    """
    Demonstrates how RLS prevents cross-tenant data leakage or tampering even if an attacker
    attempts to inject rows belonging to another tenant.
    """
    print(f"\n--- Testing Security: Tenant {authenticated_tenant_id} attempting to insert into Tenant {target_tenant_id} ---")
    try:
        with conn.transaction():
            with conn.cursor() as cur:
                set_tenant_context(cur, authenticated_tenant_id)

                # Malicious attempt: session has tenant_id=1, but tries to write row with tenant_id=2
                cur.execute(
                    """
                    INSERT INTO tasks (tenant_id, id, project_id, title)
                    VALUES (%s, 9999, 21, 'Malicious Injected Task');
                    """,
                    (target_tenant_id,),
                )
        print("CRITICAL SECURITY FAILURE: Cross-tenant insert was permitted!")
    except psycopg.Error as e:
        print(f"SECURITY SUCCESS: PostgreSQL RLS blocked cross-tenant write:\n  --> {e}")


def main():
    print("======================================================================")
    print(" Citus SaaS Multi-Tenant Demo Application")
    print(f" Connecting to: {DB_HOST}:{DB_PORT}/{DB_NAME} as '{DB_USER}'")
    print("======================================================================")

    try:
        with psycopg.connect(DSN) as conn:
            # 1. Query Tenant 1 (Acme Corp) tasks
            list_tenant_tasks(conn, tenant_id=1)

            # 2. Query Tenant 2 (Globex Logistics) tasks
            list_tenant_tasks(conn, tenant_id=2)

            # 3. Create a task for Tenant 1
            create_tenant_task(conn, tenant_id=1, task_id=1099, project_id=11, title="New Microservices Blueprint")

            # 4. Attempt cross-tenant breach
            attempt_cross_tenant_exploit(conn, authenticated_tenant_id=1, target_tenant_id=2)

            print("\n======================================================================")
            print(" Demo application executed successfully with full tenant isolation!")
            print("======================================================================")
    except psycopg.OperationalError as e:
        print(f"\nConnection error: {e}")
        print("Please ensure the Citus cluster is running (`make up`) and `01-row-based-multitenant` schema is applied.")
        sys.exit(1)


if __name__ == "__main__":
    main()
