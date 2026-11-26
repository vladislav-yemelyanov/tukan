#!/usr/bin/env bash
set -euo pipefail

root_dir="$(cd "$(dirname "$0")/.." && pwd -P)"
client_dir="$root_dir/clients/ts"

for tool in tsc node; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "Missing required tool: $tool" >&2
    exit 1
  fi
done

tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/tukan-ts-client.XXXXXX")"
trap 'rm -rf "$tmp_dir"' EXIT

tsc -p "$client_dir/tsconfig.test.json" --noEmit
tsc -p "$client_dir/tsconfig.test.json" --noEmit false --outDir "$tmp_dir/test-build"
cp "$client_dir/package.json" "$tmp_dir/test-build/package.json"
node "$tmp_dir/test-build/test/client.test.js"

tsc -p "$client_dir/tsconfig.json" --outDir "$tmp_dir/dist"
