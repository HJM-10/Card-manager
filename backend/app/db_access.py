"""Provision the dedicated runtime login using the migration administrator.

Run python -m app.db_access --configure-local after applying migrations.
Credentials are saved only in the ignored backend/.env, never printed.
"""
import argparse
import os
from pathlib import Path
import secrets

import psycopg
from psycopg import sql
from psycopg.conninfo import conninfo_to_dict, make_conninfo
from psycopg.rows import dict_row
from dotenv import set_key

from .db import migration_connect


WRITE_TABLES = (
    'users', 'sessions', 'card_profiles', 'merchants', 'categories',
    'biometric_sessions', 'import_batches', 'budgets',
    'device_registrations', 'notification_events',
)
READ_TABLES = ('transaction_audit_events', 'transaction_spending', 'monthly_category_spending')


def grant_runtime_access(conn, role, schema='public'):
    """Grant only known application operations; never grant schema ownership."""
    role_id, schema_id = sql.Identifier(role), sql.Identifier(schema)
    info = conn.execute('SELECT rolsuper, rolcreaterole, rolcreatedb, rolreplication, rolbypassrls FROM pg_roles WHERE rolname = %s', (role,)).fetchone()
    if not info or any(info.values()):
        raise ValueError('Runtime role must exist and have no administrative privileges')
    if conn.execute('SELECT 1 FROM pg_auth_members WHERE member = (SELECT oid FROM pg_roles WHERE rolname = %s)', (role,)).fetchone():
        raise ValueError('Runtime role must not inherit or assume any other role')
    if conn.execute('''SELECT 1 FROM pg_namespace WHERE nspname = %s
        AND nspowner = (SELECT oid FROM pg_roles WHERE rolname = %s)
        UNION ALL SELECT 1 FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
        WHERE n.nspname = %s AND c.relowner = (SELECT oid FROM pg_roles WHERE rolname = %s)
        UNION ALL SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
        WHERE n.nspname = %s AND p.proowner = (SELECT oid FROM pg_roles WHERE rolname = %s)''',
        (schema, role, schema, role, schema, role)).fetchone():
        raise ValueError('Runtime role must not own application objects')
    if conn.execute('SELECT 1 FROM pg_database WHERE datname = current_database() AND datdba = (SELECT oid FROM pg_roles WHERE rolname = %s)', (role,)).fetchone():
        raise ValueError('Runtime role must not own the database')
    # PostgreSQL 15 protects public by default on fresh databases, but upgraded
    # databases may still allow PUBLIC to create objects there.
    conn.execute(sql.SQL('REVOKE CREATE ON SCHEMA {} FROM PUBLIC').format(schema_id))
    conn.execute(sql.SQL('REVOKE ALL ON SCHEMA {} FROM {}').format(schema_id, role_id))
    conn.execute(sql.SQL('GRANT USAGE ON SCHEMA {} TO {}').format(schema_id, role_id))
    conn.execute(sql.SQL('REVOKE ALL ON ALL TABLES IN SCHEMA {} FROM {}').format(schema_id, role_id))
    conn.execute(sql.SQL('REVOKE ALL ON ALL FUNCTIONS IN SCHEMA {} FROM {}').format(schema_id, role_id))
    for table in WRITE_TABLES:
        conn.execute(sql.SQL('GRANT SELECT, INSERT, UPDATE, DELETE ON {}.{} TO {}').format(schema_id, sql.Identifier(table), role_id))
    for table in READ_TABLES:
        conn.execute(sql.SQL('GRANT SELECT ON {}.{} TO {}').format(schema_id, sql.Identifier(table), role_id))
    conn.execute(sql.SQL('GRANT SELECT, INSERT, UPDATE ON {}.spending_transactions TO {}').format(schema_id, role_id))
    conn.execute(sql.SQL('GRANT SELECT, UPDATE ON {}.transaction_outbox TO {}').format(schema_id, role_id))
    # Fail closed if grants inherited from PUBLIC defeat the audit restrictions.
    audit = sql.Identifier(schema, 'transaction_audit_events').as_string(conn)
    for privilege in ('INSERT', 'UPDATE', 'DELETE', 'TRUNCATE', 'TRIGGER', 'REFERENCES'):
        if conn.execute('SELECT has_table_privilege(%s, %s, %s) AS allowed', (role, audit, privilege)).fetchone()['allowed']:
            raise ValueError('Unexpected inherited audit privileges; remove them before provisioning')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--configure-local', action='store_true', required=True)
    parser.add_argument('--role', default='spendtrail_runtime')
    parser.add_argument('--schema', default='public')
    args = parser.parse_args()
    owner_url = os.environ.get('MIGRATION_DATABASE_URL') or os.environ['DATABASE_URL']
    password = secrets.token_urlsafe(36)
    role = args.role
    # A schema owner need not have cluster-wide CREATEROLE. Supply a temporary
    # administrator connection for provisioning without storing it in .env.
    admin_url = os.environ.get('PROVISION_DATABASE_URL')
    connection = psycopg.connect(admin_url, row_factory=dict_row) if admin_url else migration_connect()
    with connection as conn:
        if not conn.execute('SELECT 1 FROM pg_roles WHERE rolname = %s', (role,)).fetchone():
            conn.execute(sql.SQL('CREATE ROLE {} LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION NOBYPASSRLS').format(sql.Identifier(role)))
        grant_runtime_access(conn, role, args.schema)
        conn.execute(sql.SQL('ALTER ROLE {} LOGIN PASSWORD {}').format(sql.Identifier(role), sql.Literal(password)))
    settings = conninfo_to_dict(owner_url)
    settings.update(user=role, password=password)
    env_file = Path(__file__).resolve().parents[1] / '.env'
    set_key(str(env_file), 'MIGRATION_DATABASE_URL', owner_url)
    set_key(str(env_file), 'DATABASE_URL', make_conninfo(**settings))
    print('Restricted application login configured in backend/.env. Restart the API and notification worker to use it.')


if __name__ == '__main__':
    main()
