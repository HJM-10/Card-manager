import os
from pathlib import Path

import psycopg
from dotenv import load_dotenv
from psycopg.rows import dict_row

load_dotenv(Path(__file__).resolve().parents[1] / '.env')


def connect():
    return psycopg.connect(os.environ['DATABASE_URL'], row_factory=dict_row, connect_timeout=5)


def migrate():
    # Serialize migration runners and commit the schema and version together.
    with connect() as db:
        db.execute('SELECT pg_advisory_xact_lock(741003)')
        db.execute('CREATE TABLE IF NOT EXISTS schema_migrations (version TEXT PRIMARY KEY)')
        for path in sorted((Path(__file__).resolve().parents[1] / 'migrations').glob('*.sql')):
            if not db.execute('SELECT 1 FROM schema_migrations WHERE version = %s', (path.name,)).fetchone():
                db.execute(path.read_text(encoding='utf-8'))
                db.execute('INSERT INTO schema_migrations VALUES (%s)', (path.name,))


if __name__ == '__main__':
    migrate()
