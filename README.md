<p align="center">
  <img src="logo.png" alt="Tukan logo" width="280">
</p>

# Tukan

Generate TypeScript and Dart types from OpenAPI.

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![CI](https://github.com/vladislav-yemelyanov/tukan/actions/workflows/ci.yml/badge.svg)](https://github.com/vladislav-yemelyanov/tukan/actions/workflows/ci.yml)

An API may be used by several applications—for example, a web app and a mobile app. Each application needs to understand the same request and response data, often in a different programming language. Keeping those definitions in sync by hand takes time and can lead to mismatches.

Tukan reads an OpenAPI specification—sometimes called a Swagger file—and generates TypeScript and Dart types from the same API description. This helps clients stay consistent without writing the types by hand.

## Quick start

### Installation

Install the latest release on **macOS or Linux** with one command:

```sh
curl -fsSL https://github.com/vladislav-yemelyanov/tukan/releases/latest/download/install.sh | bash
```

The installer selects your operating system and CPU, downloads the binary together with `VERSION` and `SHA256SUMS` from GitHub Releases, verifies the SHA-256 checksum and embedded version, and installs `tukan` into `~/.local/bin` without `sudo`. It checks that the binary runs before replacing an existing installation. If necessary, follow the printed instruction to add the directory to your shell's `PATH`, then check:

```sh
tukan --version
```

To pin a specific release version or choose a custom install directory:

```sh
curl -fsSL https://github.com/vladislav-yemelyanov/tukan/releases/latest/download/install.sh | bash -s -- --version 0.3.0 --install-dir /path/to/bin
```

To install from a locally built `dist/` bundle instead of downloading from GitHub:

```sh
bash install.sh --dist-dir /path/to/dist --install-dir /path/to/bin
```

The project targets **macOS and Linux**. Builds target macOS ARM64 and Linux ARM64 and x86-64. Executables use the system libcurl library (preinstalled on macOS; install libcurl on Linux if missing).

### Set up your project

Use a project configuration as the main way to work with Tukan. Once the executable is available in your `PATH`, open your project's root directory and create it:

```sh
tukan init
```

This creates a commented `tukan.json5` file and never overwrites an existing configuration. Add your specification paths or URLs and choose the output languages.

### Generate types

**Run `tukan` from your project root to generate types for every configured API:**

```sh
tukan
```

Tukan reads `tukan.json5`, loads each OpenAPI specification, and writes the selected TypeScript and Dart files to their configured directories. It prints a list of generated files and diagnostics tied to individual specifications, so you can see what was created and which API needs attention. Run the same command whenever a specification changes, locally or in CI.

Keep `tukan.json5` in version control so teammates and CI use the same API sources and output paths. You can edit the file yourself or ask your AI assistant, for example: “Add the catalog API from this URL to the Tukan config and generate its types in `src/generated/catalog`.”

One configuration can route each API to multiple apps and languages at once, with shared defaults and per-spec overrides:

```json5
{
    concurrency: 4,
    defaults: {
        outputs: [
            { language: "ts", path: "./apps/web/src/generated" },
            { language: "dart", path: "./apps/mobile/lib/generated" },
        ],
    },
    specs: [
        { name: "billing", input: "https://billing.example.com/openapi.json" },
        {
            name: "catalog",
            input: "./specs/catalog.json",
            outputs: [
                { language: "ts", path: "./apps/web/src/generated" },
                { language: "ts", path: "./apps/admin/src/generated" },
                { language: "dart", path: "./apps/mobile/lib/generated" },
            ],
        },
    ],
}
```

Paths are relative to the configuration file. Each specification is fetched and parsed once, then written in parallel to every configured target using `name` as the basename—generating `apps/web/src/generated/billing.ts` and `apps/mobile/lib/generated/billing.dart`, plus `catalog.ts` (for both `web` and `admin`) and `catalog.dart` (for `mobile`). Tukan creates output folders and replaces existing generated files for the selected languages.

Specifications and language generators run in parallel within the configured limit. Configuration errors and conflicting output paths stop the run before processing begins. A specification that fails to load or parse keeps its previous output while other specifications continue.

See the [configuration guide](docs/configuration.md) for all settings. For occasional runs without a project configuration, see the separate [CLI reference](docs/cli.md).

## Documentation

- [Project configuration](docs/configuration.md)
- [CLI reference and direct input](docs/cli.md)
- [Test specifications and their expected results](test-specs/README.md)
- [Architecture and package boundaries](core/ARCHITECTURE.md)
- [Generated model usage and serialization](docs/generated-models.md)
- [OpenAPI features and current limitations](docs/openapi-support.md)
- [Generator requirements and language tradeoffs](core/generators/generator-contract.md)
- [HTTP client requirements matrix](docs/client-requirements.md)
- [TypeScript HTTP client](clients/ts/README.md)
- [Dart HTTP client](clients/dart/README.md)
- [Development and release builds](docs/development.md)

## Parsing errors and warnings

**A parsing error prevents all generation for that specification.** Other specifications continue. Tukan collects diagnostics and exits with code `1` if any specification fails, preserving existing generated files for inputs that fail reading or parsing.

Warnings about ignored or unsupported features are reported but allow generation to continue.

## Supporting Tukan

If Tukan saves your team time, consider sponsoring its development. Sponsorship helps fund maintenance, broader OpenAPI support, and improvements to generated TypeScript and Dart types. Sponsorship is voluntary; using Tukan does not require payment.

| Network                     | Address                                       |
| --------------------------- | --------------------------------------------- |
| **Ethereum (ETH / ERC-20)** | `0xBcbbf3Fd0Ee6456f61FF30F0978d884d88DE9b5B`  |
| **Bitcoin (BTC)**           | `bc1q6ysqf7w9xh9vfjj24d7j8y8dmmp6puv9ngfg7e`  |
| **Solana (SOL)**            | `d9QxLajm7avBzPZ4X43k3fjiNQWeJMgLZ42DRnxy5Y7` |
| **Tron (TRX / TRC-20)**     | `TC2PrctWUCQ7ePEFfo6zkhWoxJrgxw35xi`          |

<p>
  <img src="docs/assets/qr/eth.svg" alt="Ethereum (ETH / ERC-20) QR code" width="150">&nbsp;&nbsp;
  <img src="docs/assets/qr/btc.svg" alt="Bitcoin (BTC) QR code" width="150">&nbsp;&nbsp;
  <img src="docs/assets/qr/sol.svg" alt="Solana (SOL) QR code" width="150">&nbsp;&nbsp;
  <img src="docs/assets/qr/trx.svg" alt="Tron (TRX / TRC-20) QR code" width="150">
</p>

## License

Tukan is licensed under the [MIT License](LICENSE). You can use, modify, and distribute it, including in commercial and proprietary projects, provided you retain the license and copyright notice. Third-party dependencies retain their own licenses.
