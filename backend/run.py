"""Optional launcher for Windows installations using pgAdmin's embedded Python.

Standard Python users can use a virtual environment and normal -m commands.
"""
import runpy
import sys
from pathlib import Path

root = Path(__file__).resolve().parent
sys.path[:0] = [str(root / '.local' / 'packages'), str(root)]
if len(sys.argv) < 2:
    raise SystemExit('Usage: python backend/run.py app.db | uvicorn app.main:app | pytest')
module = sys.argv.pop(1)
runpy.run_module(module, run_name='__main__')
