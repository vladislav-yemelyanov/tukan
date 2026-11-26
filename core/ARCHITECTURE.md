# Tukan architecture

Tukan reads OpenAPI JSON from a file or HTTP response, converts the API description into a shared model, and generates TypeScript and Dart types. That shared model is called IR: the intermediate representation used by the generators.

For requirements when adding or changing a generator, see the [generator implementation contract](generators/generator-contract.md). It defines shared guarantees, language-specific representations, and verification requirements.

## Processing flow

Arrows in this diagram show the flow of data:

```text
                  Config file / CLI options
                  validate configuration
                             |
                             v
                    main.odin: run()
                    pipeline.odin: pool
                             |
                    +--------+--------+
                    |                 |
                    v                 v
                Local file       HTTP / HTTPS
                    |                 |
                    +--------+--------+
                             |
                             v
                         JSON bytes
                             |
                             v
                     openapi.decode()
                             |
                             v
                    openapi.OpenApiSpec
                             |
                             v
                      parser.parse()
                             |
                 +-----------+------------+
                 |                        |
                 v                        v
        components.schemas         paths and operations
                 |                        |
                 v                        v
          schemas.parse()        parse_operations()
                 |                 |           |
                 |                 v           v
                 |          Resolve $ref  schemas.parse()
                 |                 |           |
                 +-----------------+-----------+
                                   |
                                   v
                        parser.ParseResult
                      document / stats / valid
                                   |
                                   v
                            valid == true?
                             /          \
                            no          yes
                             |            |
                             v            v
                       Keep existing  output.odin:
                       output files  write_output()
                       unchanged          |
                                   +------+------+
                                   |             |
                                   v             v
                              TypeScript       Dart
                               generator     generator
                                   |             |
                                   v             v
                               <name>.ts    <name>.dart
```

Configuration and argument errors, including conflicting output paths, prevent the batch from starting. The diagram shows one source task: input read or JSON errors prevent its parser from running, and an invalid parsing result prevents all generation for that document. Other source tasks continue independently.

Configuration validation has its own diagnostics manager. Each source task owns a manager for input and parser diagnostics; each language task owns a separate manager for output errors. After workers finish, the CLI prints complete groups in source order and returns exit code `1` if any errors occurred, or `0` otherwise.

## Code layout

Source paths in the descriptions below are relative to `core/`.

```text
core/
|-- main.odin                 Entry point, input loading, exit status
|-- cli.odin                  CLI arguments and help
|-- config.odin               JSON5 settings, paths, collision checks, init
|-- pipeline.odin             Bounded source and language task scheduling
|-- output.odin               Generator selection and output writes
|-- openapi/                  OpenAPI input representation
|   |-- spec.odin             Document, operation, and component types
|   |-- decode.odin           JSON -> OpenApiSpec
|   `-- references.odin       Extract a component name from $ref
|-- parser/                   OpenAPI -> IR conversion
|   |-- parser.odin           Document assembly, statistics, validity
|   |-- operations.odin       Parameters, request bodies, responses
|   |-- references.odin       Resolve operation component references
|   `-- schemas/              Separate schema conversion package
|       |-- schema_input.odin Read and validate schema fields
|       |-- schemas.odin      Schema -> ir.Model
|       `-- unsupported.odin  Warnings about schema keywords
|-- ir/model.odin             Shared model for parser and generators
|-- generators/               Generate and write TypeScript / Dart
|-- diagnostics/              Collect and format messages
`-- tests/                    Integration tests and consumer examples
```

The top-level `.odin` files belong to the same `main` package. The `parser/schemas/` directory is a separate `schemas` package, so its procedures are called through `schemas.parse(...)`. Unit tests in `*_test.odin` files live alongside the code they test.

## Package boundaries and dependencies

An arrow here means “imports.” The diagram shows dependencies between project packages; standard library imports and the HTTP dependency are omitted.

```text
main
 |---> openapi ----------------------> diagnostics
 |---> parser
 |       |---> openapi
 |       |---> schemas
 |       |       |---> openapi
 |       |       |---> ir
 |       |       `---> diagnostics
 |       |---> ir
 |       `---> diagnostics
 |---> generators -------------------> ir
 |---> ir
 `---> diagnostics
```

Repeated names refer to the same package. `ir` and `diagnostics` do not import other project packages.

| Package | Responsibility and main calls |
| --- | --- |
| `openapi` | Defines input data. `decode()` decodes JSON; `component_name()` parses a local component reference. It does not create IR. |
| `schemas` | `parse()` validates a schema and converts it into `ir.Model`. Field reading, recursive traversal, and keyword warnings remain private. |
| `parser` | `parse()` assembles `ir.Document`, statistics, and overall validity. Handles operations and references to their components. |
| `ir` | Defines intermediate model types. Language-specific output rules belong to the generators. |
| `generators` | `generate_typescript()` and `generate_dart()` receive IR, build source code, and write it to the supplied path. They accept an optional diagnostics manager and validate language representations before writing; they return validation or write errors to the caller. |
| `diagnostics` | `add()` collects messages, `child_path()` builds source field paths, `format()` produces diagnostic text, and `has_errors()` checks for errors. |
| `main` | Controls input, options, memory lifetime, conversion, output selection, and exit status. |

The parser is independent of generators, file access, and console output. Generators receive `ir.Document` and do not read the original `OpenApiSpec`. This allows the output for one language to change independently of OpenAPI parsing rules.

## Two data representations

### Input: `openapi.OpenApiSpec`

The input model preserves the OpenAPI structure: `components`, `paths`, operations, parameters, request bodies, and responses. Optional fields use `Maybe(...)`.

`openapi.Schema` stores the original JSON object. This allows conversion to distinguish missing fields from invalid values and report unsupported keywords. `openapi.decode()` decodes the input; the `schemas` package performs semantic validation of supported schema fields.

### Result: `ir.Document`

```text
ir.Document
 |-- schemas[name] -------------------> ir.Model
 |                                      |-- Primitive
 |                                      |-- Enumeration
 |                                      |-- Reference
 |                                      |-- ArrayModel
 |                                      |-- ObjectModel
 |                                      `-- UnknownModel
 |
 `-- paths[path][HTTP method] ---------> ir.Operation
                                        |-- operation_id
                                        |-- parameters[location]
                                        |     `-- ObjectModel.fields[name]
                                        |-- request_body?
                                        |     |-- required
                                        |     `-- content[media type] -> Model
                                        `-- responses[status]
                                              `-- [media type] -> Model
```

Parameter locations are `path`, `query`, `header`, and `cookie`. Property direction (`Field.read_only` / `Field.write_only`) is retained for generator-owned request/response projections. Field presence (`Field.required`) and nullability (the `nullable` field on each model variant) are independent. `UnknownModel` represents a valid schema without a concrete type; a separate `bool` indicates conversion failure.

For example, the `User` schema in `components.schemas` becomes `document.schemas["User"]`. The `GET /users/{id}` operation becomes `document.paths["/users/{id}"]["get"]`. If its response references `User`, the response model contains `ir.Reference{name = "User"}`. All generators receive this same document and choose their own type representation.

## Schemas, references, and operations

`schemas.parse()` reads supported fields directly from the JSON tree, reports incompatible types, and recursively converts `properties`, `items`, and schema-valued `additionalProperties`. For `$ref`, it checks the reference format and the existence of the target schema. IR retains the target name, allowing recursive schemas to remain finite. Nested schemas are not serialized back to JSON during conversion.

References to parameters, request bodies, and responses follow a different process: private `resolve_parameter()`, `resolve_body()`, and `resolve_response()` procedures in `parser` follow the chain until they reach a definition without a reference. Visiting a decoded component name again is a cycle. The resolver returns the resolved definition's source path. If an error occurs within a component definition, diagnostics point to that definition.

Both processes use `openapi.component_name()`: it performs URI percent decoding first, then interprets JSON Pointer escapes `~0` and `~1`. Local component references are supported; external references are not resolved.

When processing an operation, path-level parameters are read first. Operation-level parameters can override them by name and location. Parameters in `path` must explicitly declare `required: true` and match the path template. Missing template parameters, duplicate parameters within a list, and invalid parameter schema/content combinations are errors. Each operation must declare at least one response, using a valid status code, range, or `default`. Parameter, body, and response schemas use the same `schemas.parse()` procedure as the document's named schemas. Conversion collects independent parameter, body, and response errors instead of stopping at the first error in an operation.

## Errors, warnings, and output

`parser.parse()` returns a `ParseResult` with three related fields:

- `document`: successfully converted parts of the document;
- `stats`: counts of successful and failed schemas and operations, independent of output file errors;
- `valid`: whether the document can be passed to generators.

When `valid == false`, the document may be partial. The CLI checks this flag before calling `write_output()`, preserving previous output when parsing fails. Omitting the diagnostics manager suppresses messages while keeping validity checks active.

Diagnostics carry severity, message, subject, source path, and optional rule code and output language. Identical messages are deduplicated, and formatting sorts an owned copy for stable output. IR models retain their source paths so generators can identify original schema and component definitions. Paths use JSON Pointer token escaping. Errors prevent generation; warnings are printed without changing the successful exit status.

`parser/schemas/unsupported.odin` reports ignored schema keywords such as composition (`oneOf`, `anyOf`, `allOf`, `not`, `discriminator`) and constraints. A missing OpenAPI version is an error; unsupported OpenAPI versions and ignored path-item `$ref` entries produce warnings, while supported fields are interpreted using OpenAPI 3.0 semantics. An unsupported shape of a supported field, such as an array-valued `type`, is an error.

HTTP transport and client metadata (`servers`, `callbacks`, `headers`, `links`, parameter serialization settings, `jsonSchemaDialect`, and response `encoding`), schema annotations (`title`, examples, `deprecated`, `externalDocs`, `xml`, and `$comment`), tags, and `x-` extensions are intentionally ignored without warnings. Schema descriptions and operation summaries/descriptions are retained for generated documentation. Security schemes and requirements are retained as metadata, with raw JSON fields preserving absence versus explicit null during validation. Warnings cover visited schemas, unsupported versions, and path-item references; this is not a complete unknown-field detector or OpenAPI validator. Unused parameter, request-body, and response components are not traversed. Features contained inside an ignored construct are not recursively validated.

The current feature coverage and limitations are listed in the [support matrix](../docs/openapi-support.md).

`config.odin` turns project settings or direct CLI options into a list of source jobs. Configuration-relative paths are resolved before scheduling. The preflight check rejects overlapping destinations, including existing directory symlink aliases, before any input is read. Settings and CLI semantics are documented in the [configuration guide](../docs/configuration.md) and [CLI reference](../docs/cli.md).

`pipeline.odin` uses one `thread.Pool` for source and language tasks. Each source is loaded and parsed once; a valid result enqueues one task per selected language. A wait group tracks both initial and dynamically added tasks, and the CLI joins the workers before reporting results or releasing their arenas. Output writes are independent, with no shared transaction or rollback. Language-specific representations belong to the [generators](generators/generator-contract.md#4-current-representations-and-their-tradeoffs).

## Memory and data ownership

The CLI owns an invocation arena for settings and job records. Each source task owns a separate arena for decoded input, IR, and parsing diagnostics; each language task owns another arena for generator allocations and output diagnostics. The pool uses the thread-safe default heap allocator. Source arenas remain alive until every generator has finished reading their documents, and all task arenas are released after workers join.

The decoded document does not borrow the original JSON buffer, so file or HTTP response buffers can be released after `openapi.decode()`. Callers must keep the allocator alive while using the input model and parsing result. The parser and generators preserve their inputs; parallel generators only read the shared IR and allocate their own projections.

## Verifying architectural boundaries

Unit tests for `openapi`, `parser/schemas`, `parser`, `generators`, and `diagnostics` live alongside the code responsible for each stage. Parser tests assert diagnostic paths, severity, and subjects directly; formatter text belongs to the diagnostics package tests.

`tests/` covers the CLI, HTTP input, errors, and file handling. CLI tests cover configuration initialization, inheritance and overrides, config-relative paths, validation before execution, deterministic results across worker counts, independent failures, input lists, and the direct input workflow. `tests/http_test.odin` exercises file/HTTP equivalence, invalid JSON, non-success HTTP status, and refused connections against a loopback server, including preservation of previous output on failure. Its fixture uses Odin's standard networking and threading packages. The concurrent-download scenario uses a barrier: both requests must arrive before either server responds, establishing overlap without timing-based assertions.

Consumer contracts in `tests/consumers/` check generated types with positive and negative examples. See [running checks](../test-specs/README.md#running-checks) for commands, tool requirements, compiler settings, and artifacts, and the [generator implementation contract](generators/generator-contract.md#6-verification-requirements) for required coverage.

## Documentation flow

`openapi` retains raw security fields so semantic validation can distinguish absence, explicit empty arrays, and malformed values. `parser/security.odin` validates requirement structure and scheme names, then stores optional typed requirement lists and original scheme objects in IR. Operation requirements remain optional, preserving inheritance versus explicit empty overrides. Scheme details and reference objects remain opaque descriptive data.

`generators/security.odin` formats effective authentication requirements; request encoding details are added to relevant type comments. `generators/annotations.odin` formats schema descriptions and constraints, and safely escapes comment text. Operation documentation is attached to owned copies of generated types without changing the input IR. Operation documentation appears beside generated declarations (parameter groups and inline payload models in Dart; `Operations` entries in TypeScript). Dart does not emit a file-level operation catalog; consult the specification for operations without generated declarations. Every selected language writes one model file; there are no metadata companions or runtime constraint tables.
