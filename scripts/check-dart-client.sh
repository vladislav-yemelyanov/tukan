#!/usr/bin/env bash
set -euo pipefail

root_dir="$(cd "$(dirname "$0")/.." && pwd -P)"
client_dir="$root_dir/clients/dart"

if ! command -v dart >/dev/null 2>&1; then
  echo "Missing required tool: dart" >&2
  exit 1
fi

dart analyze --fatal-infos "$client_dir/lib" "$client_dir/test"
dart --enable-asserts run "$client_dir/test/client_test.dart"
