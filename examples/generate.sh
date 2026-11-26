#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd)"
root_dir="$(cd "$script_dir/.." && pwd)"
port="${PORT:-4000}"
backend_url="http://localhost:${port}"

tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/tukan-examples-gen.XXXXXX")"
server_pid=""

cleanup() {
  if [[ -n "$server_pid" ]]; then
    kill "$server_pid" >/dev/null 2>&1 || true
    wait "$server_pid" >/dev/null 2>&1 || true
  fi
  rm -rf "$tmp_dir"
}
trap cleanup EXIT

tukan_bin="$tmp_dir/tukan"
odin build "$root_dir/core" "-out:$tukan_bin"

if ! curl -fsS "${backend_url}/openapi/todos.json" >/dev/null 2>&1; then
  PORT="$port" bun "$script_dir/backend/src/server.ts" >/dev/null 2>&1 &
  server_pid="$!"

  for _ in $(seq 1 40); do
    if curl -fsS "${backend_url}/openapi/todos.json" >/dev/null 2>&1; then
      break
    fi
    sleep 0.1
  done

  if ! curl -fsS "${backend_url}/openapi/todos.json" >/dev/null 2>&1; then
    echo "Timed out waiting for demo backend at ${backend_url}" >&2
    exit 1
  fi
fi

"$tukan_bin" --config "$script_dir/tukan.json5"
