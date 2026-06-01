#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEST="$ROOT/Sources/MacWamp/Resources/WinampClassic"
CACHE="${XDG_CACHE_HOME:-$HOME/.cache}/macwamp/winamp-source"
REPO_URL="${MACWAMP_WINAMP_REPO_URL:-https://github.com/alexfreud/winamp.git}"
SOURCE_DIR=""
ACCEPT=0
NONINTERACTIVE=0
SKIP_BUILD=0

usage() {
  cat <<'USAGE'
MacWamp setup-assets wizard

Downloads or uses a local Winamp source checkout, shows/records the upstream
license acknowledgement, imports the classic bitmap sheets into your local
working tree, and optionally verifies the Swift build.

This script is for local user setup. The imported Winamp bitmap sheets are
ignored by git and must not be redistributed unless you independently have
redistribution rights.

Usage:
  scripts/setup-assets.sh [options]

Options:
  --source PATH                  Use an existing Winamp resource dir or checkout
  --repo-url URL                 Git URL to clone for user-local asset import
  --accept-winamp-license        Required for non-interactive import
  --yes                          Non-interactive; fail instead of prompting
  --skip-build                   Import assets but do not run swift build
  -h, --help                     Show this help

Examples:
  scripts/setup-assets.sh
  scripts/setup-assets.sh --accept-winamp-license --yes
  scripts/setup-assets.sh --source ../winamp --accept-winamp-license
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --source) SOURCE_DIR="${2:-}"; shift 2 ;;
    --repo-url) REPO_URL="${2:-}"; shift 2 ;;
    --accept-winamp-license) ACCEPT=1; shift ;;
    --yes) NONINTERACTIVE=1; shift ;;
    --skip-build) SKIP_BUILD=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "unknown option: $1" >&2; usage; exit 2 ;;
  esac
done

license_text() {
  cat <<'LICENSE'
Winamp asset/source notice

MacWamp does not redistribute Winamp source code, Winamp bitmap resources, or
Winamp trademarks. This wizard can fetch or use a Winamp source checkout on
your machine solely so you can import compatible bitmap sheets into your local
working copy.

The Winamp Collaborative License in the public source release includes
restrictions such as no distribution of modified versions and no forking. Do not
commit, upload, package, or redistribute imported Winamp assets unless you have
independent permission to do so.

By continuing, you acknowledge that:
  1. the download/import is for your local machine;
  2. imported assets will be git-ignored by this project;
  3. you are responsible for complying with the upstream license and trademark
     rules.
LICENSE
}

license_text
if [[ "$ACCEPT" -ne 1 ]]; then
  if [[ "$NONINTERACTIVE" -eq 1 ]]; then
    echo "error: pass --accept-winamp-license to continue non-interactively" >&2
    exit 3
  fi
  printf '\nType AGREE to continue importing assets for local use only: '
  read -r reply
  if [[ "$reply" != "AGREE" ]]; then
    echo "aborted"
    exit 4
  fi
fi

find_resource_dir() {
  local base="$1"
  for candidate in \
    "$base" \
    "$base/Src/Winamp/resource" \
    "$base/winamp/Src/Winamp/resource"; do
    if [[ -d "$candidate" && -f "$candidate/MAIN.BMP" || -f "$candidate/main.bmp" ]]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done
  return 1
}

if [[ -n "$SOURCE_DIR" ]]; then
  RESOURCE_DIR="$(find_resource_dir "$SOURCE_DIR" || true)"
  if [[ -z "${RESOURCE_DIR:-}" ]]; then
    echo "error: could not find Winamp resource directory under $SOURCE_DIR" >&2
    exit 5
  fi
else
  if [[ ! -d "$CACHE/.git" ]]; then
    mkdir -p "$(dirname "$CACHE")"
    echo "Cloning Winamp source for local asset import: $REPO_URL"
    git clone --depth 1 "$REPO_URL" "$CACHE"
  else
    echo "Updating cached Winamp source: $CACHE"
    git -C "$CACHE" pull --ff-only
  fi
  RESOURCE_DIR="$(find_resource_dir "$CACHE" || true)"
  if [[ -z "${RESOURCE_DIR:-}" ]]; then
    echo "error: cloned repository did not contain Src/Winamp/resource" >&2
    exit 6
  fi
fi

mkdir -p "$DEST"
import_one() {
  local src_name="$1" out_name="$2"
  if [[ -f "$RESOURCE_DIR/$src_name" ]]; then
    cp "$RESOURCE_DIR/$src_name" "$DEST/$out_name"
    echo "imported $out_name"
  elif [[ -f "$RESOURCE_DIR/${src_name,,}" ]]; then
    cp "$RESOURCE_DIR/${src_name,,}" "$DEST/$out_name"
    echo "imported $out_name"
  else
    echo "missing $src_name" >&2
    return 1
  fi
}

missing=0
import_one MAIN.BMP main.bmp || missing=1
import_one CBUTTONS.BMP cbuttons.bmp || missing=1
import_one titlebar.bmp titlebar.bmp || missing=1
import_one numbers.bmp numbers.bmp || missing=1
import_one text.bmp text.bmp || missing=1
import_one volume.bmp volume.bmp || missing=1
import_one BALANCE.BMP balance.bmp || missing=1
import_one POSBAR.BMP posbar.bmp || missing=1
import_one PLAYPAUS.BMP playpaus.bmp || missing=1
import_one MONOSTER.BMP monoster.bmp || missing=1
import_one SHUFREP.BMP shufrep.bmp || missing=1
import_one Pledit.bmp pledit.bmp || missing=1
import_one Eqmain.bmp eqmain.bmp || missing=1

if [[ "$missing" -ne 0 ]]; then
  echo "warning: some optional sheets were missing; MacWamp will use generated fallbacks for missing files" >&2
fi

if [[ "$SKIP_BUILD" -ne 1 ]]; then
  echo "Verifying Swift build..."
  (cd "$ROOT" && swift build)
fi

echo "Asset setup complete. Imported files are local-only and git-ignored."
