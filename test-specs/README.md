# Realistic test specifications

Four large OpenAPI 3.0.3 JSON contracts model a multi-tenant commerce platform. Each service has its own schemas, shared components, nested models, pagination, error responses and resource lifecycles. Intentional contract defects are kept in the failing services; warnings represent real OpenAPI features Tukan currently ignores.

| File | Domain | Schemas parsed / failed | Operations parsed / failed | Expected result |
|---|---|---:|---:|---|
| [billing.json](billing.json) | Customers, invoices, subscriptions, payments, refunds, usage, ledger, receipts | 38 / 0 | 26 / 0 | Exit 0; generate all selected languages. |
| [catalog.json](catalog.json) | Products, variants, categories, warehouses, inventory, collections, search, imports, translations | 44 / 0 | 26 / 0 | Exit 0 with 12 parsing warnings plus language-specific representation warnings; generate all selected languages. |
| [identity.json](identity.json) | Accounts, profiles, organizations, roles, permissions, sessions, MFA, access reviews | 17 / 7 | 0 / 12 | Exit 1 with errors; preserve existing output. Every operation has a deliberately broken contract branch. |
| [fulfillment.json](fulfillment.json) | Orders, shipments, parcels, returns, reservations, packing, manifests, carrier integrations | 33 / 3 | 21 / 3 | Exit 1 with warnings and errors; preserve output for the entire service, including its valid parts. |

Run one service from the project root:

```sh
odin run core -- -l ts,dart -i test-specs/billing.json
odin run core -- -l ts,dart -i test-specs/catalog.json
odin run core -- -l ts,dart -i test-specs/identity.json
odin run core -- -l ts,dart -i test-specs/fulfillment.json
```

Run the combined project configuration:

```sh
odin run core -- --config test-specs/tukan.json5
```

The combined run intentionally exits with 1. Billing and catalog still generate `tukan-output/billing.{ts,dart}` and `tukan-output/catalog.{ts,dart}`. Identity and fulfillment produce no new files and keep any previous output. All paths in the configuration resolve relative to `test-specs/`.

## Coverage

| Area | Examples |
|---|---|
| Primitive types and formats | Money amounts and usage counters, fractional discounts, flags, UUIDs, email addresses, dates, timestamps, URI strings, binary receipts and base64 checksums. Formats remain strings except `binary`. |
| Presence and nullability | Required nullable customer names, optional nullable invoice notes, nullable address references, required flags, optional flags and omitted patch fields. |
| Objects and nesting | Invoice service periods, tax identifiers, search facets, product SEO, packing steps, inline array items and inline enums. |
| Arrays | Arrays of primitives, enums, references and inline objects; nested numeric usage buckets. |
| Dictionaries | String metadata, numeric totals, boolean feature flags, schema-valued warehouse stock, nested audit changes, named fields combined with open supplier dictionaries, explicitly closed money objects. |
| Enums | String states, integer retry attempts, numeric tax rates, boolean collection settings, inline currencies and directions; mixed scalar/object/array/null merchandising presets. Complex enum values exercise generator behavior beyond ordinary scalar enums. |
| Recursion and references | Recursive ledger entries and category trees, nullable schema targets, escaped and percent-encoded JSON Pointers, reusable parameters/responses/request bodies and multi-hop aliases. |
| Names and escaping | Supplier fields named `class`, Unicode keys and translation values, slash/tilde component names, quotes, dollar signs and line breaks in enum payloads. |
| Operations | All eight supported HTTP methods across billing routes, path-level parameters, operation overrides, identical `id` names in four locations, JSON-content query filters, cursor pagination and idempotency headers. |
| Bodies and responses | JSON, URL-encoded forms, multipart receipts/imports, PDF/CSV downloads, JSON/XML alternatives, problem JSON, 200/201/202/204/400/404/502/503 and default responses, bodyless responses. |
| Unsupported composition | Catalog `allOf`, `oneOf`, `anyOf`, `not` and `discriminator`: warnings with incomplete generated representations. |
| Direction and security documentation | Read/write-only properties produce directional variants. Security schemes and requirements are preserved internally; generated operation declarations document their effective requirements. Tags are ignored without warnings. |
| Schema and encoding documentation | Constraints, defaults, and request media encoding are preserved internally and described in generated comments. |
| Ignored metadata | Servers, serialization options, response headers and links; fulfillment callbacks. |
| Schema errors | Identity uses malformed `required`, `properties`, `items`, `nullable`, `format`, `$ref`, `enum`, unknown types and a 3.1-style union-valued `type`; fulfillment adds malformed `additionalProperties`. |
| Reference errors | Missing schemas and parameter/body/response components, invalid pointer escapes, absolute and relative external references. |
| Failure isolation | Valid and invalid parts of fulfillment are counted separately, but generation fails for the entire input. The combined configuration continues generating other services. |

This is a broad integration corpus, not exhaustive OpenAPI conformance: see [current support and limitations](../docs/openapi-support.md). Unsupported features are deliberately present to test diagnostics, not to imply complete generated types. Descriptions, examples and deprecated annotations do not become runtime validation or serialization.

Focused malformed JSON, reference, naming and consumer regression fixtures now live in [core/tests/fixtures/specs](../core/tests/fixtures/specs/). They remain small so a regression has an isolated cause, while this directory stays focused on large service contracts. CLI tests exercise both sets. Compiler checks include the complete generated billing and catalog types in TypeScript and Dart, then the existing focused consumer checks.

## Running checks

Run commands from the project root. The complete test suite requires Odin, TypeScript (`tsc`), Node.js, and Dart (plus `libcurl` development headers on Linux):

```sh
./scripts/test.sh
```

This runs Odin unit and CLI tests, local HTTP tests, and the consumer checks below. One temporary CLI build is shared across integration and consumer checks. The full suite also runs before every target in `scripts/build.sh`.

Individual checks can be run separately:

```sh
odin test core/openapi
odin test core/parser/schemas
odin test core/parser
odin test core/generators
odin test core/diagnostics
odin test core/tests
./scripts/check-generated.sh
```

The CLI integration tests (`odin test core/tests`) build and run the CLI for the service contracts above and the focused regression fixtures. Invalid examples are checked with existing output to verify that a failed run preserves it.


## Consumer contracts

`core/tests/consumers/<specification-name>.ts` and `.dart` use the types generated from each `valid-*.json` fixture in `core/tests/fixtures/specs/`. They check required and optional fields, nullability, enums, arrays, references, parameter locations, and request/response types.

TypeScript consumers are checked with `tsc --noEmit --strict --exactOptionalPropertyTypes --skipLibCheck` and include `@ts-expect-error` cases, so accepting an invalid value also fails the check. The security and annotations consumers are additionally compiled and executed with Node.js to verify ordinary model usage without metadata imports.

Dart consumers are analyzed with `dart analyze --fatal-infos`. The invalid Dart consumers in `core/tests/consumers/invalid/` declare the analyzer error code expected on each marked line. Valid Dart consumers are also executed with assertions enabled to check `fromJson`, `toJson`, `copyWith`, `==`, `hashCode`, and directional types. Additional Dart serialization checks cover `dart-json.json` with nested records, enum names, and JSON key collisions. The shared `valid-naming-collisions.json` fixture checks readable inline types, normalized field collisions, schema-name priority, nullable Dart backing types, and references to renamed schemas in both TypeScript and Dart.

Run all compiler and consumer checks:

```sh
./scripts/check-generated.sh
```

This uses the tools listed under [running checks](#running-checks). For new generators, follow the [verification requirements](../core/generators/generator-contract.md#6-verification-requirements).
