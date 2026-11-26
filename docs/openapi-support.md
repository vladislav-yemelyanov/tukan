# OpenAPI support

The table describes the current implementation against [OpenAPI 3.0.3](https://spec.openapis.org/oas/v3.0.3). Statuses include both parsing and the resulting generated types.

- ✅ Supported
- ◐ Partially supported
- ❌ Not supported

| # | Feature | Status | Current behavior |
|---:|---|:---:|---|
| 1 | `components.schemas` | ✅ | Named schemas are converted into an intermediate model and emitted as TypeScript and Dart types. |
| 2 | `string` and `boolean` | ✅ | Mapped to the corresponding language primitive types (`string` / `boolean` in TypeScript, `String` / `bool` in Dart). |
| 3 | `number` and `integer` | ✅ | Dart uses `num` and `int` respectively. TypeScript uses `number` for both because it has no separate integer type. `number` (including `format: decimal`) uses floating-point types without exact decimal arithmetic. |
| 4 | Objects with `properties` | ✅ | Properties are parsed recursively. TypeScript emits object type properties; Dart generates classes with named constructor parameters, `copyWith`, `==`, and `hashCode`. |
| 5 | Inline objects in `properties` | ✅ | TypeScript preserves the object shape; Dart uses named records with typed fields. Optional fields are nullable (`T?`). |
| 6 | `required` | ✅ | Required properties are mandatory. Optional properties use `?` in TypeScript and nullable parameters defaulting to `null` in Dart. |
| 7 | OpenAPI 3.0 `nullable` | ✅ | Supported for the schema types handled by the parser. TypeScript adds `\| null`; Dart uses nullable types with `?` and nullable type aliases for named nullable objects and enums. |
| 8 | Arrays of primitives or references | ✅ | Supports primitive `items`, schema references, and nested arrays. |
| 9 | Arrays of inline objects or enums | ✅ | Inline item schemas are parsed recursively. Both generators preserve scalar enum values, as described in row 12. |
| 10 | Local schema `$ref` | ✅ | References to named schemas are checked before generation. URI percent encoding and JSON Pointer escapes are decoded, and missing targets are reported. |
| 11 | External references and arbitrary JSON Pointers | ❌ | References outside the supported local component sections are reported; external documents are not loaded. |
| 12 | String, number, and boolean `enum` | ✅ | TypeScript emits literal unions. Dart emits enum types with the original values, including for inline schemas (and an uninhabitable class when empty). |
| 13 | Object and array `enum` values | ◐ | TypeScript emits object and tuple literal types, which use structural typing and cannot enforce exact object equality. Dart emits enum values containing constant maps and lists. |
| 14 | `additionalProperties` | ◐ | Explicit values are parsed, including schema-typed dictionaries. Dart stores extra fields in `additionalProperties` (with a suffix on collision) and flattens them during JSON conversion; TypeScript widens the index signature to accommodate named fields, so it cannot strictly constrain only extra keys. An omitted or `false` `additionalProperties` does not store extra keys; unknown JSON properties are ignored during Dart `fromJson` for forward compatibility. |
| 15 | `allOf`, `oneOf`, `anyOf`, and `not` | ❌ | Composition is ignored with warnings, potentially producing incomplete or unknown types. |
| 16 | `discriminator` | ❌ | Discriminator-based polymorphism is ignored with a warning. |
| 17 | `format`, including `date-time`, `uuid`, `binary`, and `byte` | ◐ | `binary` becomes `Blob` in TypeScript and `List<int>` in Dart. Text formats, including base64 `byte`, remain strings; format validation and automatic conversions are not generated. |
| 18 | Validation constraints | ◐ | The parser checks the value types of `minimum`, `maximum`, and `pattern`, and rejects `minimum` greater than `maximum`. It checks that `minLength` and `maxLength` are nonnegative integers with `minLength` no greater than `maxLength`. Valid constraints are retained internally and in generated documentation; neither Dart models nor TypeScript types enforce them at runtime. |
| 19 | `readOnly` and `writeOnly` | ✅ | The parser validates property flags. Both generators add request or response variants only for reachable schemas whose fields differ in that direction, exclude `readOnly` fields from requests and `writeOnly` fields from responses, and preserve requiredness in the applicable direction. Operations use these variants, including nested references, arrays, and dictionaries. Original component types remain available. |
| 20 | `default`, `example`, `description`, and `deprecated` | ◐ | When a schema declares a type, the parser checks that its `default` matches that type. Defaults are retained internally and in documentation, including null, false, zero, and empty strings. Constructors do not apply them. Schema descriptions are emitted as documentation; examples and deprecated annotations remain ignored. |
| 21 | Unknown or unsupported schemas | ◐ | Unconstrained schemas become TypeScript `unknown` or Dart `dynamic`. Unsupported schema keywords produce warnings; malformed supported fields produce errors. |
| 22 | Paths, operations, parameters, request bodies, and responses | ◐ | `Schemas["Operations"]` represents paths, methods, grouped parameters, request media types, and response status/media types. Local component references and path-level parameters are supported. Path-item references are ignored with a warning; response headers, callbacks, links, and parameter serialization metadata are ignored without warnings. Dart emits named parameter groups and models for inline object or enum payloads; existing component references and simple payloads are reused directly, and identical inline response schemas within an operation share one type across media and status codes. |
| 23 | Multipart uploads and file downloads | ◐ | A named binary file schema produces a file-content type, while request-body media encoding metadata is preserved internally and documented beside request types; serializers are not generated. |
| 24 | Security metadata, servers, tags, and callbacks | ◐ | `securitySchemes` and document/operation `security` are retained internally and documented in generated comments. Operation inheritance and explicit empty overrides are preserved. Tags, servers, and callbacks are ignored without warnings. |
| 25 | JSON input | ✅ | Supported as the specification input format. |
| 26 | YAML input | ❌ | Not supported. |
| 27 | OpenAPI 3.1 and its JSON Schema features | ❌ | Unsupported versions produce a warning; a missing version is an error. Features such as union-valued `type` and `$defs` are not supported; malformed supported fields are errors and ignored schema keywords produce warnings. |
| 28 | OpenAPI document and reference validation | ❌ | There is no full validation. Checked references, malformed supported schema fields, arrays without `items`, enum/type conflicts, and invalid parameter or response contracts produce errors with source paths. Warnings cover ignored schema keywords, unsupported OpenAPI versions, and ignored path-item references; annotations, extensions, HTTP transport metadata, and unvisited components can remain unchecked. |
| 29 | JSON serialization | ◐ | Dart object models and enums provide `fromJson` and `toJson`, preserving original JSON keys and omitting `null` optional fields. TypeScript exports compile-time types only. |

These statuses describe the implementation rather than a complete conformance test suite. The [generator implementation contract](../core/generators/generator-contract.md) defines requirements for new work and explains differences between the current language representations.

See [architecture](../core/ARCHITECTURE.md) for the conversion contract, allocator lifetime, and diagnostic coverage.

## Contract diagnostics

Parsing errors stop generation for the affected specification. Parameter validation rejects duplicate `name`/`in` pairs within one list, missing or simultaneous `schema`/`content`, and content maps without exactly one media type. Operation parameters may still override path-level definitions. Path parameters must match template variables and explicitly declare `required: true`. Operations require a non-empty `responses` map with status keys from `100` through `599`, `1XX` through `5XX`, or `default`.

Arrays require `items`. Enum values must match an explicitly declared type. An explicit primitive type takes precedence over object keywords; ignored object keywords produce warnings. Required properties without declared property schemas also produce warnings because their presence is not represented, even when the specification legally permits them as additional properties.

The parser also checks the shape of supported constraints and annotations: string lengths, numeric bounds, patterns, defaults, and property direction flags. A malformed value is an error at its source path. Well-formed constraints and defaults are preserved internally and as documentation rather than runtime validation. Property direction flags are retained for request/response projection.

A missing OpenAPI version is an error; unsupported versions retain the existing warning and OpenAPI 3.0 interpretation. This remains a focused conversion check rather than full OpenAPI validation. Language-specific representation diagnostics are listed in the [generator contract](../core/generators/generator-contract.md#generation-diagnostics).

## Directional types

For a component named `User` that is reachable in a given direction and has fields removed by `readOnly` or `writeOnly`, generators retain `User` and add `UserRequest` or `UserResponse` when its properties differ in that direction. Existing names take precedence; generated variants receive numeric suffixes on collisions. Schemas referencing affected types in reachable operations also receive variants, so recursive and nested references keep their request/response direction. Unreachable directional variants (for example, a response-only schema with `readOnly` properties never used in any request) are not generated. Inline operation schemas are projected directly. Request parameters and request bodies use request variants; response content uses response variants. The original component type includes all declared fields and is independent of operation direction. See [generated model usage](generated-models.md).

## Generated documentation

Each selected language produces one model file. Schema descriptions, `minLength`, `maxLength`, `minimum`, `maximum`, `pattern`, `default`, and property direction annotations are documented beside declarations and fields. Nested item and additional-property constraints are documented at the containing field. Defaults retain their written values, including null, false, zero, and empty strings. Constructors do not apply defaults, and comments themselves do not enforce runtime validation.

Operation documentation includes the HTTP method and path, summary, description, and effective authentication requirements. Standalone parameter, request, and response types carry the operation documentation; TypeScript documents entries in its `Operations` shape. In Dart, operation information is documented beside generated parameter groups and inline payload types; an operation that produces no such declaration has no generated operation documentation, so consult the specification for its details. Request payload documentation also describes body presence, media type, and declared encoding settings. Encoding settings are informational; serializers are not generated.

Security scheme details are retained internally; generated operation documentation identifies required schemes but does not reproduce their definitions. An absent operation security declaration inherits document security; an explicit `security: []` disables it. Alternatives are shown with OR, schemes required together with AND, and scopes beside the scheme name. An empty requirement object represents anonymous access. The parser checks requirement structure and scheme names; scheme details and references are preserved internally without fully validating or resolving them. No authentication or HTTP calls are generated.

Tukan does not generate metadata companion files, constraint tables, or a runtime metadata API. Existing companions produced by older versions can be removed; generation writes only the selected model files.
