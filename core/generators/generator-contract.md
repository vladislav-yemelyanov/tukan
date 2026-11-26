# Generator implementation contract

This document defines the requirements for adding or changing a Tukan language generator. Read it before choosing how a new language will represent schemas and operations.

The goal is to preserve the same API contract in every supported language. The generated syntax and public types may differ when the languages require different representations. Every difference must be explained, and every weaker guarantee must be made visible.

**Status:** the requirements below apply to new work. The tables describe TypeScript and Dart. They do not claim that every requirement already has complete test coverage. Known limitations are identified separately.

## 1. Scope and ownership

A generator receives an already parsed `ir.Document` and produces source code for one target language.

The [architecture](../ARCHITECTURE.md#package-boundaries-and-dependencies) defines package responsibilities and dependencies. Language-specific representations belong to the generator.

A generator must use IR instead of reading or interpreting the original OpenAPI document again. It must preserve the input document, including its maps, fields, and referenced models. Synthetic declarations belong to generator-owned data.

Reuse existing shared behavior when it applies. For example, Dart uses `generate_operation_types` in `core/generators/operations.odin`. A new generator may use a different public operation shape, but must preserve the same information or document what it loses.

Tukan generates data types for TypeScript and Dart, plus `fromJson`/`toJson`, `copyWith`, `==`, and `hashCode` for Dart. Dart `fromJson` checks required properties, expected JSON shapes, and enum membership; HTTP clients, full OpenAPI runtime schema validation, and automatic text-format conversions remain outside this contract.

## 2. Required semantic behavior

### 2.1 Property presence and nullability

`Field.required` answers: **must the property be provided?** A model's `nullable` flag answers: **may its value be null?**

- TypeScript preserves all four combinations statically using `?` (when not required) and `| null` (when nullable), assuming `strict` and `exactOptionalPropertyTypes`.
- Dart prioritizes idiomatic DTO ergonomics over a separate presence wrapper: required properties use `required` constructor arguments (with `?` when nullable), while optional properties use nullable fields (`T?`) defaulting to `null`. Consequently, Dart models collapse absent and `null` optional fields into `null`, and `toJson()` omits `null` optional fields while retaining `false`, `0`, empty strings, and empty collections.

Requiredness remains enforced for required nullable properties: Dart `required` constructor arguments and `fromJson` `_requiredJson(...)` require the property even when its value can be `null`.

Compiler settings are part of the guarantee. Document settings needed to reject invalid values. These are static type guarantees for ordinary typed use; casts, dynamic access, reflection, and unchecked external JSON can bypass them.

### 2.2 Primitive values and formats

Preserve the distinction between strings, booleans, integers, and numbers wherever the target type system allows it. Do not substitute strings for numeric values or replace binary content with a file path.

The existing mappings are:

| IR meaning | TypeScript | Dart |
|---|---|---|
| String | `string` | `String` |
| Boolean | `boolean` | `bool` |
| Integer | `number` | `int` |
| Number | `number` | `num` |
| String with `format: binary` | `Blob` | `List<int>` |
| Other string formats | `string` | `String` |
| Unconstrained value | `unknown` | `dynamic` |

These mappings have limits. TypeScript's `number` does not enforce integrality. The byte element range is not enforced by Dart's `List<int>`.

A new mapping must document its range, precision, or validation limitations. It must not promise support for arbitrary JSON numeric precision unless the implementation and tests establish that support.

Text formats such as `date-time`, `uuid`, and base64 `byte` currently remain strings. A new generator must not silently introduce parsing, decoding, or a new runtime dependency for them.

### 2.3 Arrays and dictionaries

Arrays must preserve element types, nested array structure, and element nullability. Array nullability and element nullability are separate: a nullable list of strings differs from a list of nullable strings.

A dictionary must preserve string keys and its value model, including nested objects, references, enums, and nullable values.

For an object with named fields and typed additional properties, preserve both parts. Do not replace all named fields with a generic dictionary or silently discard additional properties.

The current IR stores an optional additional-property model. A missing model does not grant permission to introduce arbitrary extra fields into the generated static type. `ObjectModel.closed` distinguishes explicit `additionalProperties: false` from omission in IR; Dart `fromJson` ignores undeclared keys on objects without an additional-property model to preserve forward compatibility when servers add new fields.

### 2.4 Named schemas, references, and recursion

Every named schema must have an accessible representation. References must point to the corresponding generated representation, including when a schema refers to itself or participates in a recursive object graph.

Do not expand references indefinitely or replace recursive branches with an unconstrained type. Preserve the target schema's nullability, including through reference chains. The named schema does not become non-nullable merely because a particular reference has no additional nullable flag.

Aliases and wrapper classes are both possible representations, but their consequences must be documented.

If the target compiler cannot represent a particular reference cycle, record the unsupported case and its handling. Passing one recursive-object example does not establish support for every possible alias cycle.

### 2.5 Enumerations

An enum must represent a closed set of choices under ordinary typed use. Preserve each original value and its type, including string escaping, booleans, mixed numeric values, null, arrays, and objects when present in IR.

Generated member names may be synthetic, such as `value0`. The original values must remain accessible. Do not derive identity solely from a normalized display name: distinct values can normalize to the same identifier.

For an empty enum, generate a representation with no ordinary non-null value. Replacing an empty enum with an unconstrained type would reverse its meaning.

Literal unions and language enums may provide different guarantees. In particular, preserving an object enum's payload does not establish exact structural equality or JSON validation. Describe those limitations rather than implying all representations are equivalent.

### 2.6 Operations

Operation output must account for:

- Path and HTTP method, with a stable way to locate their generated types.
- Parameter groups kept separate for path, query, header, and cookie parameters.
- Each parameter's name, type, requiredness, and nullability.
- Request content separated by media type.
- Response content separated by status and media type.

Equal parameter names in different locations must not overwrite each other. Operations must not replace named schemas with the same generated name.

A response with no content must not acquire an invented payload. A generator that emits only payload types may emit no declaration for that response; document how consumers identify such operations and responses.

The current IR retains `operation_id`, parameter groups, an optional request body, and response content maps. It does not retain all original response metadata. A generator cannot reconstruct information that parsing has discarded.

## 3. Names, literals, and stable output

Generated source must compile for supported input names and values, including keywords, punctuation, empty names, Unicode, quotes, backslashes, interpolation markers, and line terminators.

Use deterministic, readable names with language-specific escaping. Avoid collisions between user names, normalized names, generated inline types, operation types, helper types, and members reserved by the target language. Include collisions with enclosing type names and inherited members where relevant.

Keep original schema and property names discoverable through the generated representation or safe comments. Dart JSON methods map renamed properties back to their original names.

The same document must produce the same source across repeated runs, regardless of map iteration order. Sort unordered declarations and fields. Resolve synthetic name collisions deterministically. Existing enum value order is significant because generated member names may use value indexes.

Determinism for an unchanged document does not promise that adding a schema can never change a collision suffix. Document public naming changes when they affect existing consumers.

Dart allocates public names before rendering. Existing legal schema names take priority over normalized names and inline declarations. Nested types combine their enclosing schema, property names, `Item` for array elements, and `AdditionalProperty` for dictionary values; for example, `GetInvoiceQueryParametersExpandItem`. Conflicts receive deterministic numeric suffixes starting at `2`. Field names have separate scopes, protecting constructor names and Dart object/helper members (`fromJson`, `toJson`, `copyWith`, `identical`, `hashCode`, `runtimeType`, `toString`, `noSuchMethod`).

Dart identifiers use ASCII; names containing separators become camelCase fields or PascalCase types. When there are no usable letters or digits, Dart uses `field` or `Schema`, with suffixes when needed. Source names remain in comments. Nullable Dart objects and enums use a `<Name>Value` backing declaration, also checked for collisions.

TypeScript preserves original JSON property and schema names inside its `Schemas` interface namespace.

## 4. Current representations and their tradeoffs

This section records the current baseline. It explains choices; it does not require new languages to copy another language's syntax or treat existing limitations as unavoidable.

| Area | TypeScript | Dart |
|---|---|---|
| Named object | Entry in the exported `Schemas` interface. | Class with named constructor parameters, `fromJson`, `toJson`, `copyWith`, `==`, and `hashCode`. |
| Required field | Required object property. | Required constructor argument. |
| Optional field | Optional property using `?`. | Nullable field (`T?`) defaulting to `null` (omitted from `toJson()` when `null`). |
| Nullable value | Union with `null`. | Nullable type using `?`; named nullable objects and enums use aliases. |
| Named primitive, array, or reference | A schema entry can directly hold the mapped type. | `typedef`. |
| Inline object with named fields | Inline object type. | Named record fields. |
| Scalar enum | Literal union. | Enum with original payload in `value`. Empty enums use an uninhabitable class. |
| Complex enum | Object or tuple literal types. | Enum payload containing constant maps or lists. |
| Object with fields and additional properties | Index signature widened to include named field types and optional `undefined`. | Separate `additionalProperties` map, with a suffix on collision. |
| Operations | Nested `Schemas["Operations"]` entry placed at the end of `Schemas`; underscores resolve schema-name collisions. | Named parameter groups, inline payload models, generated `sealed class <Op>Error` unions for multi-error operations, plus a structural `OperationRequest<T, E>` record and segment-based `Paths` tree (`Paths.foo.byId(id).patch.body(...).request`) whose immutable typestate operation builders enforce required slots at compile time, expose `method`, `path`, fluent `.query`/`.headers`/`.cookie`/`.body`/`.contentType`/`.with*` methods, a `.request` getter on ready states, and inline bound path-segment parameters (`by<Param>(value)`, with `.pathParams(...)` fallback on conflicts). |

### What consumers need to know

**Nullable optional fields in Dart favor ergonomics over absent-vs-null distinction.** Dart models use `T?` defaulting to `null` rather than a presence wrapper. `toJson()` omits `null` optional fields while keeping `false`, `0`, and empty values. `copyWith` uses an internal sentinel so callers can explicitly set nullable or optional fields to `null`.

**Additional-property storage changes the object layout.** Dart keeps extra values in a separate map. Generated JSON conversion flattens those maps and protects named properties from extra-map collisions. TypeScript keeps the flat shape, but widening its index signature permits extra values outside the declared additional-property type. For example, a named string field causes the extra-key signature to accept strings even if the additional-property schema is numeric.

**Operation representations expose different information.** TypeScript's `Schemas["Operations"]` shape represents request-body requiredness directly. Dart reuses existing component models and built-in types directly for request bodies and responses, generating named types only for parameter groups and inline object/enum payloads. No generator creates payload declarations for responses without media content.

**Unconstrained values provide different levels of checking.** TypeScript `unknown` requires narrowing before most operations; Dart `dynamic` permits unchecked operations. These types both represent unconstrained data, but provide different compiler guarantees.

**Static object types are not exact JSON validators.** TypeScript's `{}` representation for an empty object does not enforce an object-only or closed-object schema. Inline empty objects in Dart use maps, while named empty objects use classes. Additional-key rejection and runtime schema constraint checks are not enforced.

### Compiler assumptions

The [consumer checks](../../test-specs/README.md#consumer-contracts) document compiler settings and execution checks. These settings affect the guarantees of the generated types.

TypeScript consumer checks enable `strict` and `exactOptionalPropertyTypes`; consumers need both settings for the corresponding optional-property guarantees. TypeScript remains type-only and does not validate external JSON.

Dart consumers are analyzed with `dart analyze --fatal-infos` and executed with assertions enabled.

### Known gaps and future work

The common examples and language-specific fixtures cover useful scenarios, but do not establish complete conformance to every rule above. Before claiming a guarantee, add the corresponding consumer test.

In particular, reference-chain nullability, alias cycles, empty-object behavior, numeric boundaries, and complex enum equality need explicit attention when extending coverage. A limitation that follows from the existing implementation is not automatically an accepted design for a new generator.

### Generation diagnostics

Each generator accepts an optional diagnostics manager and validates its representation before writing output. Representation errors leave the existing file unchanged and fail the run; other selected languages can still generate their files. Warnings describe a loss of guarantees or a change of representation while allowing generation. Generated models retain source JSON Pointer paths, including paths to referenced component definitions.

| Rule code | Severity | Applies to | Meaning |
|---|---|---|---|
| `unsupported-alias-cycle` | Error | TypeScript, Dart | A cycle of named aliases cannot compile. Dart also rejects alias cycles through arrays. Recursive object declarations remain supported. |
| `widened-additional-properties` | Warning | TypeScript | The index signature is widened beyond the additional-property model to accommodate named fields or optional `undefined`. |
| `enum-integer-precision-loss` | Warning | TypeScript | A concrete enum integer cannot be represented exactly as a JavaScript number. |

Messages include the language, rule code, and source path. Repeated messages for the same component are emitted once per language, and formatted diagnostics have a stable order. General numeric range limits remain documented rather than producing a warning for every numeric property.

## 5. How to document a difference

Before implementing a new generator, add a proposed representation column or a short language-specific section covering every area in the tables above. Mark open choices as unresolved. Use common scenarios to compare alternatives.

For each difference, record:

| Item | Required explanation |
|---|---|
| Scenario | The schema or operation that requires a decision. Include a small example when useful. |
| Desired meaning | Which values and states the API contract allows or rejects. |
| Chosen representation | The public generated type and how a consumer uses it. |
| Reason | The language constraint or concrete usability tradeoff behind the choice. Separate language restrictions from project preferences. |
| Alternatives | Practical alternatives and why they were not chosen. |
| Consequence | Whether the choice changes syntax only, changes construction or access, or weakens a guarantee. Give a concrete example of any lost guarantee. |
| Verification | The positive, negative, or execution test that demonstrates the behavior. Identify missing coverage honestly. |
| Dependencies | Required compiler version, flags, runtime libraries, and serialization assumptions. |

Do not silently weaken the contract to make implementation easier. If a guarantee cannot be represented, describe the limit and decide its handling explicitly before treating that feature as supported. The support matrix must distinguish full and partial support.

Keep these decisions alongside the implementation so reviewers can assess the representation, its limits, and its tests together. Update the decision when the behavior changes.

## 6. Verification requirements

### Generator unit tests

Check representative declarations, error propagation for unwritable paths, input preservation, deterministic output, and synthetic name collisions. Assert meaningful public behavior rather than every formatting detail.

### Shared consumer scenarios

Use the same semantic scenarios across target languages. The source code can differ, but the API contract being tested must be recognizable in each consumer.

| Scenario | Required evidence |
|---|---|
| Presence and nullability | Required vs optional and nullable types; present `false`, `0`, and empty values. |
| Primitive and binary values | Correct mapped types and rejection of incompatible values within the documented limits. |
| Collections | Primitive and reference items, nested arrays, nullable items, and typed dictionary values. |
| Objects | Required and optional fields, nested objects, `copyWith`/`==`/`hashCode` in Dart, and named fields together with additional properties. |
| References | Named schemas, nullable targets, reference chains, and recursive objects. |
| Enums | Scalar, mixed, complex, nullable, inline, and empty cases; original payloads preserved. |
| Names and literals | Keywords, encoding collisions, generated-name collisions, Unicode, escapes, and enclosing-type member collisions. |
| Operations | Parameter locations, name collisions, media types, response statuses, and documented handling of empty responses. |

Keep large shared service contracts in `test-specs/`, focused regression specifications in `core/tests/fixtures/specs/`, and consumer checks in `core/tests/consumers/`. Language-specific fixtures may supplement the shared cases when they exercise a representation unique to that language. They must not replace the common cases.

### Compiler and execution checks

Compile or analyze generated source together with a consumer using the documented settings. A substring test in Odin cannot establish that target-language code compiles or enforces a type restriction.

Include negative consumers. A negative test must fail for the intended reason: for example, a missing required field, a disallowed null, or an invalid enum choice. Match diagnostic codes and source locations where available, or use the compiler's supported expected-error mechanism. An unrelated syntax error must not count as a successful rejection test.

Execute consumers where value behavior matters, especially `fromJson`/`toJson`, `copyWith`, `==`/`hashCode`, binary data, and enum payloads. Compilation alone cannot prove that a string literal kept its original contents.

### CLI integration and completion

Language selection comes from project configuration or the required `-l` / `--lang` option in direct mode. A new language must be selectable alone and alongside other languages in both modes. Unselected outputs remain unchanged. Parsing errors prevent generation for that specification and preserve its previous output; other specifications continue. Generators may run concurrently against the same document, so they must not mutate shared IR or use mutable global state. Return write errors to the CLI; do not claim rollback or atomic replacement, which the current output layer does not provide.

A generator is ready when its representation decisions are documented, the relevant shared and language-specific checks pass, and its CLI option, output extension, tool requirements, support matrix, and user examples are updated. Integrate its consumer checks into `scripts/check-generated.sh` and the full `scripts/test.sh` workflow.

## Related documents

- [Architecture and package boundaries](../ARCHITECTURE.md)
- [IR definitions](../ir/model.odin)
- [OpenAPI support and limitations](../../docs/openapi-support.md)
- [Example specifications and consumer checks](../../test-specs/README.md)

### Directional schema projection

All generators project property `readOnly` and `writeOnly` flags into generator-owned request and response variants before emitting operation types. Original components remain available unchanged. Only reachable schemas whose fields change in a given direction (and reachable schemas referencing an affected type in that direction) receive named variants. Variant names use `Request` and `Response` suffixes without repeating an existing suffix; a changed schema already carrying that suffix uses `View`, and remaining collisions receive deterministic numeric suffixes. Recursive links, inline objects, array items, typed additional properties, nullability, and requiredness are preserved in the applicable direction. Request parameters are projected in the request direction.

The `valid-directions` fixture covers directional operation links and recursive models in both languages, positive and negative TypeScript use, and Dart execution and analyzer rejection checks. Generator unit tests also cover reachability pruning, collisions, aliases, inline properties, additional-property values, and input preservation.

### Documentation

Each generator writes a single model file. Keep schema descriptions and supported constraints beside their declarations and properties. Defaults are documented, never inserted by constructors. Comments must distinguish static types and `fromJson` shape checks from constructors, defaults, and unvalidated rules.

Operation types document the method, path, summary, description, and effective security requirements. Request types also document body presence, media type, and encoding settings. TypeScript uses operation entries; Dart attaches operation information to generated parameter groups and inline payload types. Operations without such declarations have no generated documentation. Security scheme definitions remain in the input specification. Preserve anonymous alternatives, AND/OR grouping, scopes, inheritance, and explicit empty security overrides.

Comment generation must preserve the source IR and neutralize comment delimiters and line separators. No metadata companion, runtime registry, or constraint table is generated.

### Decimal and conversion behavior

TypeScript and Dart preserve the numeric wire shape for `format: decimal` using floating-point types; changing the API to decimal strings is not implied.

Dart `fromJson` checks required properties, expected JSON shapes, and enum membership; it does not enforce `minLength`, `maxLength`, `minimum`, `maximum`, `pattern`, or closed-object extra-key rejection at runtime. TypeScript exports types and unions only.

The `valid-wire` consumers exercise `fromJson`/`toJson`, `copyWith`/`==`/`hashCode`, recursive models, additional fields, and enum member collisions. Source property comments are emitted only when an identifier differs from its JSON key. Direction variants remain separate when their fields or dependencies differ.
