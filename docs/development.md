# Development

The Odin source and tests are in `core/`. Install [Odin](https://odin-lang.org/docs/install/) (and `libcurl` development headers on Linux; macOS includes `libcurl`), then build the executable from the project root:

```sh
odin build core -out:tukan
```

Run the complete test suite from the project root:

```sh
./scripts/test.sh
```

See [running checks](../test-specs/README.md#running-checks) for required tools, individual checks, and generated test artifacts.

The current build version is stored in [VERSION](../VERSION) and embedded in the executable, including when building directly with Odin. On macOS, prepare builds for the current Mac, Linux ARM64, and Linux x86-64:

```sh
./scripts/release.sh
```

To set the version while preparing a release:

```sh
./scripts/release.sh 0.3.0
```

Use a SemVer version such as `0.3.0` or `0.3.0-rc.1`. The script embeds that version, prepares `dist/VERSION` and `dist/SHA256SUMS`, and updates the root `VERSION` only after all requested builds succeed. A failed build keeps the previous version and `dist/`. Building a different version removes older targets from `dist/` so a distribution contains one version.

Pass `macos`, `linux-arm64`, or `linux-amd64` to build one target, for example `./scripts/release.sh 0.3.0 macos`. A partial rebuild keeps other targets only if their version matches. `./scripts/build.sh` remains an alias for the same workflow.

Every target invokes the complete host test suite first. After running the required checks separately, `--skip-tests` skips the host suite. Linux builds require a running Docker daemon and always run Odin and HTTP tests inside the image; building for a different CPU architecture requires emulation. Under CPU emulation, CLI integration tests run sequentially, including the scenarios that exercise concurrent downloads and generation.

## Publishing a GitHub Release

GitHub Actions automates CI checks ([`.github/workflows/ci.yml`](../.github/workflows/ci.yml)) and release builds ([`.github/workflows/release.yml`](../.github/workflows/release.yml)).

To publish a new version:

1. Update [VERSION](../VERSION) (for example, `0.4.0`) and commit the changes on `main`.
2. Create an annotated tag matching `VERSION` with a `v` prefix and push both `main` and the tag:

```sh
git tag -a v0.4.0 -m "Tukan v0.4.0"
git push origin main v0.4.0
```

Pushing a `v*` tag triggers the release workflow, which verifies that the tag matches `VERSION`, runs the full test suite, builds native binaries for macOS ARM64, Linux x86-64, and Linux ARM64, generates `SHA256SUMS`, smoke-tests `install.sh`, and publishes the GitHub Release with generated release notes.
