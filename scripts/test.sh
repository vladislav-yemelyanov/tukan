#!/usr/bin/env bash
set -euo pipefail

root_dir="$(cd "$(dirname "$0")/.." && pwd)"
"$root_dir/scripts/test-release.sh"
for tool in odin tsc node dart; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "Missing required test tool: $tool" >&2
    exit 1
  fi
done

test_dir="$(mktemp -d "${TMPDIR:-/tmp}/tukan-tests.XXXXXX")"
trap 'rm -rf "$test_dir"' EXIT
export TUKAN_TEST_BINARY="$test_dir/tukan"
cd "$root_dir"
odin build core "-out:$TUKAN_TEST_BINARY"
odin test core/openapi
odin test core/parser/schemas
odin test core/parser
odin test core/generators
odin test core/diagnostics
odin test core/tests
./scripts/check-generated.sh
./scripts/check-ts-client.sh
./scripts/check-dart-client.sh
