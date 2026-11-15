#!/usr/bin/env bash
set -euo pipefail
umask 077
exec python3.12 "$(dirname -- "$0")/staging.py" "$@"
