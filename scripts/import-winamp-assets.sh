#!/usr/bin/env bash
set -euo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
if [[ $# -eq 0 ]]; then
  exec "$DIR/setup-assets.sh"
fi
exec "$DIR/setup-assets.sh" --source "$1" "${@:2}"
