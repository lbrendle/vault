#!/bin/bash
set -euo pipefail
LAB_ENV="${1:-$HOME/Library/Application Support/Vault/Lab/Python}"
PYTHON_BIN="${2:-python3}"
LAB_REPO="$(cd "$(dirname "$0")/.." && pwd)"
"$PYTHON_BIN" -c 'import sys; sys.exit(0 if sys.version_info[:2] == (3, 12) else "Use Python 3.12 for this locked Lab environment.")'
"$PYTHON_BIN" -m venv "$LAB_ENV"
"$LAB_ENV/bin/python" -m pip install -r "$LAB_REPO/native/lab-mac-requirements.lock.txt"
printf '\nSet the Python executable in Vault → Lab → Mac host settings to:\n%s/bin/python\n' "$LAB_ENV"
