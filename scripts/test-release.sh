#!/usr/bin/env bash
set -euo pipefail

root_dir="$(cd "$(dirname "$0")/.." && pwd)"
work="$(mktemp -d "${TMPDIR:-/tmp}/tukan-release-tests.XXXXXX")"
trap 'rm -rf "$work"' EXIT
if command -v shasum >/dev/null 2>&1; then
  checksum_command=(shasum -a 256)
else
  checksum_command=(sha256sum)
fi
mkdir -p "$work/repo/scripts" "$work/tools" "$work/install dir"
cp "$root_dir/scripts/release.sh" "$work/repo/scripts/"
cp "$root_dir/install.sh" "$work/repo/"
printf '0.1.0\n' > "$work/repo/VERSION"

# Simulate platforms and build failures without Docker or cross-platform compilers.
cat > "$work/tools/uname" <<'STUB'
#!/usr/bin/env bash
case "$1" in
  -s) echo "${TEST_OS:-Darwin}" ;;
  -m) echo "${TEST_ARCH:-arm64}" ;;
esac
STUB
cat > "$work/tools/odin" <<'STUB'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${TEST_BUILD_FAIL:-false}" == true ]]; then exit 1; fi
for argument in "$@"; do
  case "$argument" in
    -out:*) output="${argument#-out:}" ;;
    -define:TUKAN_VERSION=*) version="${argument#-define:TUKAN_VERSION=}" ;;
  esac
done
printf '#!/usr/bin/env bash\nprintf "Tukan %s\\n"\n' "$version" > "$output"
STUB
cat > "$work/tools/docker" <<'STUB'
#!/usr/bin/env bash
# Reach the Linux step, then fail after the macOS binary was staged.
case "$1" in
  info) exit 0 ;;
  build) exit 1 ;;
  *) exit 1 ;;
esac
STUB
chmod +x "$work/tools/"*
export PATH="$work/tools:$PATH"

expect_failure() {
  if "$@" > "$work/failure.log" 2>&1; then
    echo "Expected failure: $*" >&2
    exit 1
  fi
}

bash "$work/repo/scripts/release.sh" 0.2.0-rc.1+build.7 macos --skip-tests
[[ "$(cat "$work/repo/VERSION")" == 0.2.0-rc.1+build.7 ]]
[[ "$("$work/repo/dist/tukan-macos-arm64" --version)" == 'Tukan 0.2.0-rc.1+build.7' ]]
(cd "$work/repo/dist" && "${checksum_command[@]}" -c SHA256SUMS)
bash "$work/repo/install.sh" --install-dir "$work/install dir"
[[ "$("$work/install dir/tukan" --version)" == 'Tukan 0.2.0-rc.1+build.7' ]]
HOME="$work/home" bash "$work/repo/install.sh" > /dev/null
[[ "$("$work/home/.local/bin/tukan" --version)" == 'Tukan 0.2.0-rc.1+build.7' ]]
cp "$work/install dir/tukan" "$work/installed-before"
cp "$work/repo/dist/tukan-macos-arm64" "$work/binary-before"

# A partial rebuild retains same-version targets, but a new version removes them.
cp "$work/repo/dist/tukan-macos-arm64" "$work/repo/dist/tukan-linux-arm64"
bash "$work/repo/scripts/release.sh" macos --skip-tests
[[ -f "$work/repo/dist/tukan-linux-arm64" ]]
bash "$work/repo/scripts/release.sh" 0.2.0 macos --skip-tests
[[ ! -e "$work/repo/dist/tukan-linux-arm64" ]]
cp "$work/repo/dist/tukan-macos-arm64" "$work/current-before"

# A later platform failure must not publish a partial release or bump VERSION.
expect_failure bash "$work/repo/scripts/release.sh" 0.3.0 all --skip-tests
[[ "$(cat "$work/repo/VERSION")" == 0.2.0 ]]
cmp "$work/current-before" "$work/repo/dist/tukan-macos-arm64"
expect_failure env TEST_BUILD_FAIL=true bash "$work/repo/scripts/release.sh" 0.3.0 macos --skip-tests
[[ "$(cat "$work/repo/VERSION")" == 0.2.0 ]]
cmp "$work/current-before" "$work/repo/dist/tukan-macos-arm64"

for version in 01.2.3 1.2 1.2.3-01 '1.2.3;bad'; do
  expect_failure bash "$work/repo/scripts/release.sh" "$version" macos --skip-tests
  [[ "$(cat "$work/repo/VERSION")" == 0.2.0 ]]
done

# Every supported OS/CPU spelling must select its own artifact.
for system in Darwin Linux; do
  case "$system" in Darwin) platform=macos ;; Linux) platform=linux ;; esac
  for architecture in arm64 aarch64 x86_64 amd64; do
    case "$architecture" in arm64|aarch64) arch=arm64 ;; *) arch=amd64 ;; esac
    cp "$work/current-before" "$work/repo/dist/tukan-$platform-$arch"
    (cd "$work/repo/dist" && "${checksum_command[@]}" tukan-* > SHA256SUMS)
    TEST_OS="$system" TEST_ARCH="$architecture" bash "$work/repo/install.sh" --install-dir "$work/install dir" > /dev/null
    cmp "$work/current-before" "$work/install dir/tukan"
  done
done
cp "$work/install dir/tukan" "$work/installed-before"
expect_failure env TEST_OS=FreeBSD bash "$work/repo/install.sh" --install-dir "$work/install dir"
expect_failure env TEST_ARCH=riscv64 bash "$work/repo/install.sh" --install-dir "$work/install dir"
cmp "$work/installed-before" "$work/install dir/tukan"

# Corruption, missing artifacts and version mismatch must preserve the installed file.
printf '\ncorrupted\n' >> "$work/repo/dist/tukan-macos-arm64"
expect_failure bash "$work/repo/install.sh" --install-dir "$work/install dir"
cmp "$work/installed-before" "$work/install dir/tukan"
rm "$work/repo/dist/tukan-macos-arm64"
expect_failure bash "$work/repo/install.sh" --install-dir "$work/install dir"
cmp "$work/installed-before" "$work/install dir/tukan"
cp "$work/binary-before" "$work/repo/dist/tukan-macos-arm64"
(cd "$work/repo/dist" && "${checksum_command[@]}" tukan-* > SHA256SUMS)
expect_failure bash "$work/repo/install.sh" --install-dir "$work/install dir"
cmp "$work/installed-before" "$work/install dir/tukan"

# Runtime dependency failures must also leave the existing installation intact.
printf '#!/usr/bin/env bash\nexit 1\n' > "$work/repo/dist/tukan-macos-arm64"
(cd "$work/repo/dist" && "${checksum_command[@]}" tukan-* > SHA256SUMS)
expect_failure bash "$work/repo/install.sh" --install-dir "$work/install dir"
cmp "$work/installed-before" "$work/install dir/tukan"

echo "Release and installation checks passed."
