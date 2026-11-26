#!/usr/bin/env bash
set -euo pipefail

root_dir="$(cd "$(dirname "$0")/.." && pwd -P)"
for tool in odin tsc node dart; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "Missing required tool: $tool" >&2
    exit 1
  fi
done

output_dir="$root_dir/tukan-output"
check_dir="$root_dir/test-artifacts"
mkdir -p "$check_dir"
# Dart reports canonical file paths in its machine-readable diagnostics.
check_dir="$(cd "$check_dir" && pwd -P)"
binary="${TUKAN_TEST_BINARY:-$check_dir/tukan}"
if [[ -z "${TUKAN_TEST_BINARY:-}" ]]; then
  odin build "$root_dir/core" "-out:$binary"
fi

check_dart_errors() {
  local source="$1"
  local output_dir="$2"
  local target="$output_dir/$(basename "$source")"
  local expected="$target.expected-errors"
  local observed="$target.observed-errors"
  local analyzer_log="$target.analyzer.log"
  local schema_name="${3:-valid-schemas}"
  sed "s|'spec.dart'|'../../tukan-output/$schema_name.dart'|" "$source" > "$target"

  if ! awk '
    match($0, /expected-error: [A-Z_]+/) {
      code = substr($0, RSTART + 16, RLENGTH - 16)
      print code "|" NR
      count++
    }
    END { if (count == 0) exit 1 }
  ' "$source" | LC_ALL=C sort > "$expected"; then
    echo "Unable to read expected analyzer errors from $source" >&2
    return 1
  fi

  if dart analyze --format machine "$target" > "$analyzer_log" 2>&1; then
    echo "Expected Dart to reject $(basename "$source"), but analysis succeeded." >&2
    cat "$analyzer_log" >&2
    return 1
  fi
  awk -F '|' -v target="$target" '
    $1 == "ERROR" {
      if (NF < 8 || $4 != target) {
        print "Unexpected analyzer diagnostic: " $0 > "/dev/stderr"
        exit 1
      }
      print $3 "|" $5
    }
  ' "$analyzer_log" | LC_ALL=C sort > "$observed"

  if ! diff -u "$expected" "$observed"; then
    echo "Unexpected Dart errors for $(basename "$source"):" >&2
    cat "$analyzer_log" >&2
    return 1
  fi
  echo "Verified rejected Dart usage: $(basename "$source")"
}

# Large service contracts must compile even when unsupported fields produce warnings.
for name in billing catalog; do
  "$binary" -l ts,dart -i "$root_dir/test-specs/$name.json" -o "$output_dir"
  tsc --noEmit --strict --exactOptionalPropertyTypes --skipLibCheck "$output_dir/$name.ts"
  dart analyze --fatal-infos "$output_dir/$name.dart"
done

for specification in "$root_dir"/core/tests/fixtures/specs/valid-*.json; do
  name="$(basename "$specification" .json)"
  consumer_dir="$check_dir/$name"
  mkdir -p "$consumer_dir"
  "$binary" -l ts,dart -i "$specification" -o "$output_dir"
  # Consumer templates import spec; point them at the CLI's actual named output.
  sed -e "s|'./spec'|'../../tukan-output/$name'|" "$root_dir/core/tests/consumers/$name.ts" > "$consumer_dir/usage.ts"
  sed -e "s|'spec.dart'|'../../tukan-output/$name.dart'|" "$root_dir/core/tests/consumers/$name.dart" > "$consumer_dir/usage.dart"

  tsc --noEmit --strict --exactOptionalPropertyTypes --skipLibCheck "$output_dir/$name.ts" "$consumer_dir/usage.ts"
  dart analyze --fatal-infos "$output_dir/$name.dart" "$consumer_dir/usage.dart"
  dart --enable-asserts run "$consumer_dir/usage.dart"
  if [[ "$name" == valid-schemas ]]; then
    for source in "$root_dir"/core/tests/consumers/invalid/*.dart; do
      check_dart_errors "$source" "$consumer_dir"
    done
  fi
  if [[ "$name" == valid-security || "$name" == valid-annotations ]]; then
    tsc --strict --exactOptionalPropertyTypes --skipLibCheck --module commonjs --rootDir "$root_dir" --outDir "$consumer_dir/js" "$consumer_dir/usage.ts"
    node "$consumer_dir/js/test-artifacts/$name/usage.js"
  fi
  if [[ "$name" == valid-directions ]]; then
    check_dart_errors "$root_dir/core/tests/consumers/invalid/directions/directions.dart" "$consumer_dir" "$name"
  fi
done

# Dart serialization covers presence, nested records, enum names, and JSON key collisions.
dart_json_dir="$check_dir/dart-json"
mkdir -p "$dart_json_dir"
"$binary" -l dart -i "$root_dir/core/tests/fixtures/dart-json.json" -o "$dart_json_dir"
sed -e "s|'spec.dart'|'dart-json.dart'|" "$root_dir/core/tests/consumers/valid-dart-json.dart" > "$dart_json_dir/usage.dart"
dart analyze --fatal-infos "$dart_json_dir/dart-json.dart" "$dart_json_dir/usage.dart"
dart --enable-asserts run "$dart_json_dir/usage.dart"
