# Project configuration

Keep one `tukan.json5` in your project root. Run `tukan init` to create a commented starting configuration, edit its sources and settings, then run `tukan`. The init command refuses to overwrite an existing file. Commit the configuration so developers, AI assistants, and CI use the same inputs and output locations.

The file uses JSON5: ordinary JSON is accepted, and comments, unquoted keys, and trailing commas are allowed. OpenAPI input specifications still require JSON.

## Example

```json5
{
  concurrency: 4,
  defaults: {
    outputs: [
      { language: "ts", path: "./web/src/generated" },
      { language: "dart", path: "./mobile/lib/generated" },
    ],
  },
  specs: [
    {
      name: "billing",
      input: "https://billing.example.com/openapi.json",
    },
    {
      name: "catalog",
      input: "./specs/catalog.json",
      languages: ["dart"],
      output: "./mobile/generated",
    },
  ],
}
```

Each specification is fetched and parsed once, then written to all configured output targets in parallel. Here `billing` generates `web/src/generated/billing.ts` and `mobile/lib/generated/billing.dart`, while `catalog` replaces inherited targets with `mobile/generated/catalog.dart`.

## Settings

| Field | Meaning | Default |
| --- | --- | --- |
| `concurrency` | Maximum number of active download/parse or language-generation tasks across the entire run. Integer from 1 to 64; use 1 for sequential execution. | `4` |
| `defaults.languages` | Languages inherited by specifications that omit `languages` and `outputs`. Non-empty array. | `["ts"]` |
| `defaults.output` | Output directory inherited by specifications that omit `output` and `outputs`. Non-empty string. | `"./src/generated"` |
| `defaults.outputs` | Array of `{ language, path }` targets inherited by specs that do not override `outputs`, `output`, or `languages`. Cannot be combined with `defaults.output` or `defaults.languages`. | None |
| `defaults.optional` | Boolean inherited by specifications that omit `optional`. When `true`, unavailable inputs warn instead of failing the run. | `false` |
| `specs` | Non-empty array of specification objects. | Required |
| `specs[].input` | Non-empty local file path or HTTP/HTTPS URL. | Required |
| `specs[].name` | Output basename without path separators; cannot be `.` or `..`. An extension is added for each selected language. | Derived from the input filename |
| `specs[].languages` | Non-empty array replacing `defaults.languages` for this specification (or resetting `defaults.outputs` to classic mode). | Inherited |
| `specs[].output` | Non-empty directory path replacing `defaults.output` for this specification (or resetting `defaults.outputs` to classic mode). | Inherited |
| `specs[].outputs` | Non-empty array of `{ language, path }` objects targeting separate directories per language (including multiple destinations for the same language). Cannot be combined with `output` or `languages` in the same block. | Inherited |
| `specs[].optional` | Boolean overriding `defaults.optional`. When `true`, input read or HTTP fetch errors emit warnings and preserve existing outputs without failing the run. | Inherited (`false`) |

Language values are `ts` (or `typescript`) and `dart`. In classic `languages` mode, repeated values select a language once; in `outputs` mode, each entry targets its own `path`, and duplicate complete output paths are rejected before inputs are loaded. See the [generator contract](../core/generators/generator-contract.md#4-current-representations-and-their-tradeoffs) for generated type conventions and limitations.

Unknown fields and incorrect value types are errors. Empty language lists do not disable a specification; remove its entry to exclude it from a run. The configuration contains data only and does not execute scripts or expand environment variables.

## Paths and output names

All relative input and output paths are resolved from the configuration file's directory, even when you select it from elsewhere with `tukan --config path/to/tukan.json5`. Tukan looks for the default file in the current directory; it does not search parent directories.

An explicit `name` keeps output names stable when a source URL changes and distinguishes APIs whose URLs all end in `openapi.json`. Without a name, Tukan takes the input filename without its last extension. For URLs it ignores the query and fragment; a URL without a filename uses `spec`.

Output directories are created when generation starts. Existing files for selected languages are replaced, and files for unselected languages are left unchanged. Two specifications may share a directory or a basename when their complete output paths differ. Conflicting output paths, including aliases through existing directory symlinks, are rejected before inputs are loaded.

## Parallel execution and failures

Each source is loaded and parsed once. Valid specifications enqueue a separate generation task per selected language. All tasks share the same concurrency limit; generators read the parsed document without modifying it. A ready specification can generate output while another source is still downloading.

Configuration validation completes before any specification is read or downloaded. Once execution begins, read, HTTP, JSON, parsing, or output errors in one specification do not cancel other specifications. Reading or parsing failures preserve every existing output for that specification. Write failures can leave some output files updated; there is no transaction or rollback across files.

When a specification has `optional: true` (directly or inherited from `defaults.optional`), file read and HTTP fetch failures (such as connection errors or non-2xx HTTP statuses) are downgraded to warnings: existing generated outputs are preserved, the specification is omitted from `Generated files`, and the run still succeeds unless another error occurs. Invalid JSON, OpenAPI parsing errors, generator errors, and file write errors still fail the run even when `optional: true`. Pass `--strict` on the CLI to ignore `optional: true` (for example in CI).

Messages and counts are printed in specification order after execution, with diagnostics identifying their input. Exit code `0` means all specifications completed without errors; warnings do not fail the run. Exit code `1` means configuration validation or at least one specification failed.

For selecting another config or making temporary overrides, see the [CLI reference](cli.md).

## Consuming several APIs

Dart and TypeScript use module imports; import each API with an alias or prefix when names overlap:

```dart
import 'accounts/api.dart' as accounts;
import 'cards/api.dart' as cards;
```

See [generated model usage](generated-models.md) for serialization and enum examples.
