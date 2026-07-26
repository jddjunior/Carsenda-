#!/usr/bin/env bash
# run_tests.sh - apply migrations to a scratch database and run the full suite.
# Any failed assertion aborts with a non-zero exit code.
set -euo pipefail

DB="${CARSENDA_TEST_DB:-carsenda_test}"
PSQL="psql -v ON_ERROR_STOP=1 -q"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

echo "==> recreating database ${DB}"
dropdb --if-exists "$DB"
createdb "$DB"

echo "==> auth shim (local only; Supabase provides this natively)"
$PSQL -d "$DB" -f "$ROOT/db/test/shim_auth.sql"

echo "==> migrations"
for f in "$ROOT"/db/migrations/*.sql; do
  echo "    $(basename "$f")"
  $PSQL -d "$DB" -f "$f"
done

echo "==> seed"
$PSQL -d "$DB" -f "$ROOT/db/seed/0001_test_fixtures.sql"

echo "==> tests"
for f in "$ROOT"/db/test/test_*.sql; do
  echo "--- $(basename "$f")"
  $PSQL -d "$DB" -f "$f"
done

echo
echo "ALL TESTS PASSED"
