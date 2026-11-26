<p align="center">
  <img src="logo.png" alt="Tukan logo" width="280">
</p>

# Tukan

Fast OpenAPI 3.0 type generator and zero-dependency HTTP clients for **TypeScript** and **Dart**.

[![Release](https://img.shields.io/github/v/release/vladislav-yemelyanov/tukan)](https://github.com/vladislav-yemelyanov/tukan/releases/latest)
[![npm](https://img.shields.io/npm/v/tukan?label=npm)](https://www.npmjs.com/package/tukan)
[![pub.dev](https://img.shields.io/pub/v/tukan?label=pub.dev)](https://pub.dev/packages/tukan)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

Written in [Odin](https://odin-lang.org/) as a single native binary with parallel generation, preflight validation, and safe failure isolation—broken specs never overwrite existing generated files. While parsing, it checks schemas, `$ref` targets, and operation contracts, reporting structured errors and warnings with exact JSON Pointer paths instead of stopping at the first issue.

- **Tukan CLI** ([Releases](https://github.com/vladislav-yemelyanov/tukan/releases/latest)) — generates pure TypeScript types (`Schemas`) and standalone Dart models with compile-time `Paths` builders (`api.dart`) from one `tukan.json5` config. No runtime dependencies in generated code.
- **TypeScript Client** ([npm](https://www.npmjs.com/package/tukan) · [docs](clients/ts/README.md)) — zero-dependency `fetch` client with end-to-end path, parameter, body, and status-error typing, non-throwing results, `AbortSignal`, timeouts, and hooks.
- **Dart Client** ([pub.dev](https://pub.dev/packages/tukan) · [docs](clients/dart/README.md)) — zero-dependency `dart:io` client built for generated `Paths` trees, non-throwing sealed `ApiResult` / `ApiError`, `CancelToken`, hooks, and pluggable transports.

## Install

```sh
curl -fsSL https://github.com/vladislav-yemelyanov/tukan/releases/latest/download/install.sh | bash
```

Installs to `~/.local/bin` on **macOS (ARM64)** and **Linux (ARM64, x86-64)** with SHA-256 verification.

<details>
<summary>Install a specific version or custom directory</summary>

```sh
curl -fsSL https://github.com/vladislav-yemelyanov/tukan/releases/latest/download/install.sh \
  | bash -s -- --version 0.4.0 --install-dir /path/to/bin
```

> Executables use the system `libcurl` (preinstalled on macOS; install `libcurl` on Linux if missing).

</details>

## Quick start

1. Create `tukan.json5` in your project root:

```sh
tukan init
```

2. Add your OpenAPI specs and output targets to `tukan.json5`:

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

3. Generate types:

```sh
tukan
```

Run `tukan` whenever a spec changes — locally or in CI. See the [configuration guide](docs/configuration.md) or [CLI reference](docs/cli.md) for direct one-off runs.

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
