#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
dist_dir="$script_dir/dist"
install_dir="${TUKAN_INSTALL_DIR:-$HOME/.local/bin}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dist-dir|--install-dir)
      if [[ $# -lt 2 || -z "$2" ]]; then
        echo "Missing directory for $1" >&2
        exit 1
      fi
      case "$1" in
        --dist-dir) dist_dir="$2" ;;
        --install-dir) install_dir="$2" ;;
      esac
      shift 2
      ;;
    -h|--help)
      echo "Usage: bash install.sh [--dist-dir DIRECTORY] [--install-dir DIRECTORY]"
      echo 'Defaults: dist next to this script; install to $HOME/.local/bin.'
      exit 0
      ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
done

case "$(uname -s)" in
  Darwin) platform=macos ;;
  Linux) platform=linux ;;
  *) echo "Tukan supports macOS and Linux." >&2; exit 1 ;;
esac
case "$(uname -m)" in
  arm64|aarch64) arch=arm64 ;;
  x86_64|amd64) arch=amd64 ;;
  *) echo "Unsupported CPU architecture: $(uname -m)" >&2; exit 1 ;;
esac

binary="tukan-$platform-$arch"
if [[ ! -f "$dist_dir/$binary" || ! -s "$dist_dir/VERSION" || ! -s "$dist_dir/SHA256SUMS" ]]; then
  echo "Missing $binary, VERSION or SHA256SUMS in $dist_dir. Prepare this target with scripts/release.sh." >&2
  exit 1
fi
version="$(cat "$dist_dir/VERSION")"
expected="$(awk -v name="$binary" '$2 == name {print $1}' "$dist_dir/SHA256SUMS")"
if command -v shasum >/dev/null 2>&1; then
  actual="$(shasum -a 256 "$dist_dir/$binary" | awk '{print $1}')"
elif command -v sha256sum >/dev/null 2>&1; then
  actual="$(sha256sum "$dist_dir/$binary" | awk '{print $1}')"
else
  echo "Install shasum or sha256sum to verify the binary." >&2
  exit 1
fi
if [[ -z "$expected" || "$actual" != "$expected" ]]; then
  echo "Checksum verification failed for $binary. The existing installation was kept." >&2
  exit 1
fi

mkdir -p "$install_dir"
install_dir="$(cd "$install_dir" && pwd)"
destination="$install_dir/tukan"
if [[ -d "$destination" ]]; then
  echo "Cannot replace a directory: $destination" >&2
  exit 1
fi
temporary="$(mktemp "$install_dir/.tukan.XXXXXX")"
trap 'rm -f "$temporary"' EXIT
cp "$dist_dir/$binary" "$temporary"
chmod 755 "$temporary"
if ! installed_version="$("$temporary" --version)"; then
  echo "Cannot run $binary. Check system compatibility and libcurl. The existing installation was kept." >&2
  exit 1
fi
if [[ "$installed_version" != "Tukan $version" ]]; then
  echo "Binary version does not match dist/VERSION. The existing installation was kept." >&2
  exit 1
fi
mv -f "$temporary" "$destination"
echo "Installed $installed_version to $destination"
case ":${PATH:-}:" in
  *":$install_dir:"*) ;;
  *) printf 'Add this to your shell profile, then open a new terminal:\n  export PATH=%q:"$PATH"\n' "$install_dir" ;;
esac
