#!/usr/bin/env bash
# Do not trace credentials inherited through the environment.
set +x
set -euo pipefail
cd -- "$(dirname -- "$0")"
exec python3 scripts/releaseTooling.py "$@"
