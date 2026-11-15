#!/usr/bin/env sh
set -eu
SCRIPT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
REPO=$(CDPATH='' cd -- "$SCRIPT_DIR/../.." && pwd)
PYTHON="$REPO/.venv/bin/python"
if [ ! -x "$PYTHON" ]; then
  PYTHON=''
  for candidate in python3.12 python3 python; do
    if command -v "$candidate" >/dev/null 2>&1 && "$candidate" -c 'import sys; sys.exit(0 if sys.version_info >= (3,12) else 1)' 2>/dev/null; then
      PYTHON=$(command -v "$candidate")
      break
    fi
  done
fi
if [ -z "$PYTHON" ]; then
  echo 'Python 3.12+ missing. Install Python 3.12 or newer and reopen your shell.' >&2
  exit 1
fi
exec "$PYTHON" "$SCRIPT_DIR/earthsync.py" "$@"
