#!/usr/bin/env bash
set -euo pipefail

root_dir="$(cd "$(dirname "$0")/.." && pwd)"
version="$(cat "$root_dir/VERSION")"
target=all
run_tests=true
version_set=false
target_set=false

for argument in "$@"; do
  case "$argument" in
    all|macos|linux-arm64|linux-amd64)
      if $target_set; then echo "Only one build target is allowed." >&2; exit 1; fi
      target="$argument"
      target_set=true
      ;;
    --skip-tests) run_tests=false ;;
    -h|--help)
      echo "Usage: ./scripts/release.sh [VERSION] [all|macos|linux-arm64|linux-amd64] [--skip-tests]"
      echo "Defaults: version from VERSION, all targets, complete host tests."
      exit 0
      ;;
    *)
      if $version_set; then echo "Unexpected argument: $argument" >&2; exit 1; fi
      version="$argument"
      version_set=true
      ;;
  esac
done

number='(0|[1-9][0-9]*)'
prerelease='(0|[1-9][0-9]*|[0-9]*[A-Za-z-][0-9A-Za-z-]*)'
if [[ ! "$version" =~ ^$number\.$number\.$number(-$prerelease(\.$prerelease)*)?(\+[0-9A-Za-z-]+(\.[0-9A-Za-z-]+)*)?$ ]]; then
  echo "Invalid version: $version. Use SemVer, for example 0.1.0 or 0.2.0-rc.1." >&2
  exit 1
fi

if [[ "$target" == all || "$target" == macos ]]; then
  if [[ "$(uname -s)" != Darwin ]]; then echo "macOS builds must run on macOS; choose a Linux target." >&2; exit 1; fi
  case "$(uname -m)" in
    arm64) macos_arch=arm64 ;;
    x86_64) macos_arch=amd64 ;;
    *) echo "Unsupported macOS architecture: $(uname -m)" >&2; exit 1 ;;
  esac
  command -v odin >/dev/null || { echo "Odin is required for macOS builds." >&2; exit 1; }
fi
if [[ "$target" != macos ]]; then
  command -v docker >/dev/null || { echo "Docker is required for Linux builds." >&2; exit 1; }
  docker info >/dev/null
fi
if command -v shasum >/dev/null 2>&1; then
  checksum_command=(shasum -a 256)
elif command -v sha256sum >/dev/null 2>&1; then
  checksum_command=(sha256sum)
else
  echo "Install shasum or sha256sum to prepare checksums." >&2
  exit 1
fi

stage="$(mktemp -d "$root_dir/.tukan-release.XXXXXX")"
container=""
backup=""
cleanup() {
  if [[ -n "$container" ]]; then docker rm -f "$container" >/dev/null 2>&1 || true; fi
  if [[ -n "$backup" && ! -e "$root_dir/dist" ]]; then mv "$backup" "$root_dir/dist"; fi
  rm -rf "$stage"
}
trap cleanup EXIT
mkdir "$stage/dist"

# Keep other targets only when they belong to the same version.
if [[ -f "$root_dir/dist/VERSION" && "$(cat "$root_dir/dist/VERSION")" == "$version" ]]; then
  for binary in "$root_dir"/dist/tukan-*; do
    if [[ -f "$binary" ]]; then cp "$binary" "$stage/dist/"; fi
  done
fi
if $run_tests; then "$root_dir/scripts/test.sh"; fi

build_macos() {
  echo "==> Building Tukan $version for macOS $macos_arch"
  (cd "$root_dir" && odin build core -o:speed "-define:TUKAN_VERSION=$version" "-out:$stage/dist/tukan-macos-$macos_arch")
}

build_linux() {
  local arch="$1"
  local image="tukan-build:$arch"
  echo "==> Building Tukan $version for Linux $arch"
  docker build --load --platform "linux/$arch" --build-arg "TUKAN_VERSION=$version" --tag "$image" --file "$root_dir/docker/Dockerfile.linux" "$root_dir"
  container="$(docker create --platform "linux/$arch" "$image")"
  docker cp "$container:/output/tukan" "$stage/dist/tukan-linux-$arch"
  docker rm "$container" >/dev/null
  container=""
}

case "$target" in
  macos) build_macos ;;
  linux-arm64) build_linux arm64 ;;
  linux-amd64) build_linux amd64 ;;
  all) build_macos; build_linux arm64; build_linux amd64 ;;
esac

printf '%s\n' "$version" > "$stage/dist/VERSION"
chmod 755 "$stage"/dist/tukan-*
(cd "$stage/dist" && "${checksum_command[@]}" tukan-* > SHA256SUMS)
printf '%s\n' "$version" > "$stage/VERSION"

# Publish only after every requested build has succeeded.
if [[ -e "$root_dir/dist" ]]; then
  backup="$stage/previous-dist"
  mv "$root_dir/dist" "$backup"
fi
mv "$stage/dist" "$root_dir/dist"
mv "$stage/VERSION" "$root_dir/VERSION"
echo "Tukan $version is ready in $root_dir/dist"
