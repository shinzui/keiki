#!/usr/bin/env bash
# Generate the SCXML fixture documents from the compiled keiki test
# component and validate them with the independent Python checker.
#
#   scripts/check-scxml.sh             # generate + check in a temporary directory
#   scripts/check-scxml.sh OUTPUT_DIR  # also copy the checked documents there
#
# Documents are always generated into a fresh directory owned by this script
# and removed on exit, so a failed export can never leave stale or partial
# artifacts that pass the check. OUTPUT_DIR is created if needed and is never
# deleted; only the checked *.scxml files are copied into it (overwriting
# same-named files).
#
# Run inside the Nix dev shell (`nix develop -c bash scripts/check-scxml.sh`)
# so cabal, GHC, and python3 come from the pinned toolchain.
set -euo pipefail

if (($# > 1)); then
  echo "usage: $0 [OUTPUT_DIR]" >&2
  exit 2
fi

repo=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$repo"

work=$(mktemp -d "${TMPDIR:-/tmp}/keiki-scxml.XXXXXX")
trap 'rm -rf "$work"' EXIT
generated="$work/scxml"
mkdir "$generated"

cabal build -v1 keiki:test:keiki-test
bin=$(cabal -v0 list-bin keiki:test:keiki-test)
[[ -x $bin ]] || {
  echo "test executable not found: $bin" >&2
  exit 1
}

# The test executable writes the fixtures instead of running Hspec when this
# variable is set; it exits non-zero (writing nothing) if any export fails.
KEIKI_SCXML_EXPORT_DIR="$generated" "$bin"

python3 scripts/check-scxml.py "$generated"

if (($# == 1)); then
  mkdir -p "$1"
  cp "$generated"/*.scxml "$1"/
  echo "copied checked SCXML documents to $1"
fi
