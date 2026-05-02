#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SQL_DIR="$ROOT_DIR/sql"

fail() {
  echo "ERROR: $*" >&2
  exit 1
}

if grep -RIn --include='*.sql' '{{results_schema}}\|{{cdm_schema}}\|{{vocab_schema}}' "$SQL_DIR"; then
  fail "template placeholders remain in SQL files"
fi

if grep -RIn --include='*.sql' "sed -i" "$SQL_DIR"; then
  fail "runtime SQL file mutation is forbidden"
fi

if grep -RIn --include='*.sql' "results_site_a\\." "$SQL_DIR"; then
  fail "hardcoded results_site_a schema remains in SQL files"
fi

if grep -RIn --include='*.sql' ":results_schema\\.ase_parameters\\|:results_schema\\.ase_blood_cultures\\|sh\\.charttime\\|meets_sepsis3 = TRUE" "$SQL_DIR"; then
  fail "stale table/view/column references remain"
fi

if grep -RIn --include='*.sql' "ILIKE '%dialysis%' .*LIMIT 1" "$SQL_DIR"; then
  fail "dialysis/RRT concept lookup must use validated concept sets, not name search LIMIT 1"
fi

duplicate_prefixes="$(
  find "$SQL_DIR" -maxdepth 1 -type f -name '[0-9][0-9]_*.sql' -print \
    | sed -E 's#.*/([0-9][0-9])_.*#\1#' \
    | sort \
    | uniq -d
)"
if [ -n "$duplicate_prefixes" ]; then
  echo "$duplicate_prefixes" >&2
  fail "duplicate numbered SQL prefixes found"
fi

echo "Static SQL checks passed."
