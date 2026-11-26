#!/usr/bin/env bash
set -euo pipefail

script_dir=""
if [[ -n "${BASH_SOURCE[0]:-}" && -f "${BASH_SOURCE[0]}" ]]; then
  script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fi

dist_dir_set=false
dist_dir=""
requested_version="${TUKAN_VERSION:-}"
repo="${TUKAN_REPO:-vladislav-yemelyanov/tukan}"
release_url="${TUKAN_RELEASE_URL:-}"
install_dir="${TUKAN_INSTALL_DIR:-$HOME/.local/bin}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dist-dir|--install-dir)
      if [[ $# -lt 2 || -z "$2" ]]; then
        echo "Missing directory for $1" >&2
        exit 1
      fi
      case "$1" in
        --dist-dir)
          dist_dir="$2"
          dist_dir_set=true
          ;;
        --install-dir)
          install_dir="$2"
          ;;
      esac
      shift 2
      ;;
    --version)
      if [[ $# -lt 2 || -z "$2" ]]; then
        echo "Missing version for --version" >&2
        exit 1
      fi
      requested_version="$2"
      shift 2
      ;;
    -h|--help)
      echo "Usage: bash install.sh [--version VERSION] [--dist-dir DIRECTORY] [--install-dir DIRECTORY]"
      echo 'Defaults: download the latest GitHub release (or use ./dist when present next to this script);'
      echo 'install to $TUKAN_INSTALL_DIR or $HOME/.local/bin.'
      exit 0
      ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
done

if $dist_dir_set && [[ -n "$requested_version" ]]; then
  echo "Cannot combine --dist-dir with --version." >&2
  exit 1
fi

if [[ -n "$requested_version" ]]; then
  requested_version="${requested_version#v}"
  number='(0|[1-9][0-9]*)'
  prerelease='(0|[1-9][0-9]*|[0-9]*[A-Za-z-][0-9A-Za-z-]*)'
  if [[ ! "$requested_version" =~ ^$number\.$number\.$number(-$prerelease(\.$prerelease)*)?(\+[0-9A-Za-z-]+(\.[0-9A-Za-z-]+)*)?$ ]]; then
    echo "Invalid version: $requested_version. Use SemVer, for example 0.3.0 or v0.3.0." >&2
    exit 1
  fi
fi

download_dir=""
temporary=""
cleanup() {
  if [[ -n "$temporary" ]]; then rm -f "$temporary"; fi
  if [[ -n "$download_dir" ]]; then rm -rf "$download_dir"; fi
}
trap cleanup EXIT

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

download_file() {
  local url="$1"
  local destination="$2"
  if command -v curl >/dev/null 2>&1; then
    curl -fsSL "$url" -o "$destination"
  elif command -v wget >/dev/null 2>&1; then
    wget -qO "$destination" "$url"
  else
    echo "Install curl or wget to download Tukan." >&2
    return 1
  fi
}

if $dist_dir_set; then
  :
elif [[ -z "$requested_version" && -z "$release_url" && -n "$script_dir" && -d "$script_dir/dist" ]]; then
  dist_dir="$script_dir/dist"
else
  if [[ -z "$release_url" ]]; then
    if [[ -n "$requested_version" ]]; then
      release_url="https://github.com/$repo/releases/download/v$requested_version"
    else
      release_url="https://github.com/$repo/releases/latest/download"
    fi
  fi

  if ! command -v curl >/dev/null 2>&1 && ! command -v wget >/dev/null 2>&1; then
    echo "Install curl or wget to download Tukan." >&2
    exit 1
  fi

  download_dir="$(mktemp -d "${TMPDIR:-/tmp}/tukan-install.XXXXXX")"
  for asset in VERSION SHA256SUMS "$binary"; do
    if ! download_file "$release_url/$asset" "$download_dir/$asset"; then
      echo "Failed to download $asset from $release_url. The existing installation was kept." >&2
      exit 1
    fi
  done
  dist_dir="$download_dir"
fi

if [[ ! -f "$dist_dir/$binary" || ! -s "$dist_dir/VERSION" || ! -s "$dist_dir/SHA256SUMS" ]]; then
  echo "Missing $binary, VERSION or SHA256SUMS in $dist_dir. Prepare this target with scripts/release.sh." >&2
  exit 1
fi
version="$(cat "$dist_dir/VERSION")"
if [[ -n "$requested_version" && "$version" != "$requested_version" ]]; then
  echo "Downloaded version ($version) does not match requested version ($requested_version). The existing installation was kept." >&2
  exit 1
fi
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
temporary=""
echo "Installed $installed_version to $destination"
case ":${PATH:-}:" in
  *":$install_dir:"*) ;;
  *) printf 'Add this to your shell profile, then open a new terminal:\n  export PATH=%q:"$PATH"\n' "$install_dir" ;;
esac
