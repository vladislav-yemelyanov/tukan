# CLI reference

The recommended project workflow is `tukan init`, edit `tukan.json5`, then run `tukan`. See the [configuration guide](configuration.md). Direct input flags are available for scripts and occasional runs.

## Project commands

```sh
tukan init
tukan
tukan --config ./config/tukan.json5
tukan --help
tukan --version
```

`init` creates `tukan.json5` in the current directory and refuses replacement. Plain `tukan` reads that file from the current directory. Missing configuration is an error with an instruction to run `tukan init`.

| Option | Meaning |
| --- | --- |
| `-c`, `--config FILE` | Read an explicit configuration file. |
| `-j`, `--concurrency N` | Override the shared task limit, from 1 to 64. |
| `-l`, `--lang LANGUAGES` | With an explicit `--config`, replace the language selection of every specification (when a spec uses `outputs`, filters targets to matching languages). |
| `-o`, `--output DIRECTORY` | With an explicit `--config`, replace the output directory of every specification. `--out` is also accepted. |
| `-h`, `--help` | Show help; used alone. |
| `-v`, `--version` | Show the embedded build version; used alone. |

CLI overrides take precedence over per-specification settings and defaults. A CLI output path is relative to the current working directory; paths inside the configuration remain relative to its directory. The configuration itself must still be valid before overrides are applied.

```sh
tukan --config tukan.json5 --lang ts,dart --output ./temporary-types --concurrency 2
```

## Direct input

Providing `--input`, `--input-list`, `--lang`, or `--output` without `--config` selects direct mode and ignores the project configuration. Language selection is required in direct mode, including when `spec.json` is used by default.

```sh
tukan -l ts -i path/to/openapi.json
tukan -l ts,dart -i https://example.com/openapi.json
tukan -l ts -i path/to/openapi.json -o src/api/types
```

| Option | Meaning | Default |
| --- | --- | --- |
| `-i`, `--input FILE_OR_URL` | One local OpenAPI JSON file or HTTP/HTTPS URL. | `spec.json` in the current directory |
| `--input-list FILE` | Load several sources from a text file, one path or URL per non-empty line. | None |
| `-l`, `--lang LANGUAGES` | Comma-separated languages: `ts`/`typescript`, `dart`. | Required |
| `-o`, `--output DIRECTORY`, `--out DIRECTORY` | Output directory, created if needed. | `tukan-output` in the current directory |
| `-j`, `--concurrency N` | Shared task limit, from 1 to 64. | `4` |

Options cannot be repeated. `--input` and `--input-list` are mutually exclusive and cannot be combined with `--config`. Invalid arguments are rejected before input loading or output writes. `-j` alone uses the project configuration.

## Input lists

For detailed per-source settings, prefer the project configuration. A text list is useful when all sources share the same languages and output directory:

```text
./specs/billing.json
https://example.com/catalog.json
```

```sh
tukan --input-list sources.txt --lang ts,dart
```

Paths in the list are relative to the list file's directory. Leading and trailing whitespace and empty lines are ignored; LF and CRLF are accepted. A UTF-8 BOM at the beginning of the list is accepted. Lines are literal paths or URLs: there is no comment syntax, so URL fragments remain part of their source URLs.

## Output naming

Direct mode takes the input filename without its final extension: `openapi.json` produces `openapi.ts` or `openapi.dart` for selected languages. URL query parameters and fragments are excluded, and a URL without a filename uses `spec`. Files for unselected languages are left unchanged.

Relative single-input and output paths use the current working directory. Multiple inputs with conflicting complete output paths are rejected before loading; use a configuration with explicit names or separate output directories to distinguish them.

The [configuration guide](configuration.md#parallel-execution-and-failures) describes parallel execution, preservation of existing output, diagnostics, and exit codes for both modes.

## Run report

Each input is reported under `Specification`, followed by `Statistics` and any `Diagnostics`. Once all inputs and generator diagnostics have been reported, a single `Generated files` section lists the successfully written files from this run, in configuration and language order. Existing files preserved after a failure are excluded. If no files were generated, the section reports `None.`.

One total-time line is printed on successful and failed processing runs:

```text
Generated files (2)
  ./generated/billing.ts
  ./generated/catalog.ts

Total time: 125.400 ms
```

`Total time` measures elapsed time from CLI startup through configuration, processing, reporting and task cleanup. It uses a monotonic clock and is shown in milliseconds. Help, version and `init` do not print it.

Reports, file lists and timings go to stdout; diagnostics go to stderr. To retain their terminal order in one log, redirect both streams together, for example `tukan > run.log 2>&1`.
