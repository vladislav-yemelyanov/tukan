# Generated model usage

TypeScript exports object types and literal unions inside `Schemas`, with API operations grouped at the end under `Schemas["Operations"]`. Dart generates classes with `fromJson`, `toJson`, `copyWith`, `==`, `hashCode`, and native enums with readable members. Unsafe or colliding Dart member names receive readable normalization and suffixes, while serialization always uses original wire values.

```ts
import type { Schemas as Cards } from './cards/api';
const state: Cards['CardOrderRequestState'] = 'approved';
```

Use `strict` and `exactOptionalPropertyTypes` in TypeScript. These are compile-time types; validate untrusted JSON separately. Fields omitted from OpenAPI `required` remain optional, including request IDs. Tukan does not infer server business rules.

## Several APIs

TypeScript and Dart use module imports; import each API with an alias or prefix when names overlap:

```ts
import type { Schemas as Accounts } from './accounts/api';
import type { Schemas as Cards } from './cards/api';
```

```dart
import 'accounts/api.dart' as accounts;
import 'cards/api.dart' as cards;
```

## Dart models and JSON conversion

Dart object models are immutable classes with named constructor parameters, `fromJson`, `toJson`, `copyWith`, value-based `==`, and `hashCode`. `jsonEncode(model)` calls `toJson` automatically.

Optional fields use nullable Dart types (`T?`) defaulting to `null`. When `toJson()` runs, optional fields whose value is `null` are omitted, while `false`, `0`, empty strings, and empty collections are serialized normally. Use `copyWith(field: null)` to clear an optional or nullable field explicitly back to `null`.

```dart
const patch = AccountUpdateRequest(id: 'account-id', name: 'new name');
final updated = patch.copyWith(name: null); // AccountUpdateRequest(id: 'account-id', name: null)
final payload = patch.toJson(); // {"id":"account-id","name":"new name"}
```

Additional-property maps (`additionalProperties`) are stored in `additionalProperties` and flattened during JSON conversion; entries cannot overwrite declared properties. Undeclared JSON keys on objects without an additional-property schema are ignored during `fromJson` for forward compatibility.

TypeScript (`number`) and Dart (`num`) keep numeric payloads for `format: decimal` using floating-point values without exact decimal arithmetic.

JSON binary values follow each runtime representation: TypeScript `Blob` and Dart `List<int>`. Multipart/binary HTTP transport still belongs to the caller.

## Operations and directional variants

When a schema has `readOnly` or `writeOnly` fields and is reachable from an operation in the corresponding direction, Tukan generates `<Name>Request` or `<Name>Response` variants containing only the fields valid for that direction. Existing schema components remain unchanged, and unreachable directional variants are omitted.

In TypeScript, `Schemas["Operations"]` groups paths, HTTP methods, parameters, request bodies, and responses. In Dart, operation parameter groups (`*Parameters`) and inline object/enum payloads (`*Request`, `*Response`) are emitted as top-level classes and enums, while `$ref` request bodies and responses use the referenced schema types directly.

Dart also generates a compile-time `Paths` tree of immutable typestate builders and an `OperationRequest<T, E>` record inside `api.dart` (with zero external imports):

```dart
final tasksRoot = Paths.api.v1.tasks;
final req = tasksRoot.byTaskId('tsk_01').patch.body(title: 'Updated').request;
```

- Path-parameter segments bind inline via `by<Param>(value)` when descendant operations agree on the parameter type (falling back to `.pathParams(...)` / `.withPathParams(...)` on conflicts).
- Required slots must be populated before `.request` becomes available on the builder type.
- Error typing `E` is inferred from OpenAPI error responses (`Never` for none, the model type directly for one shared model, or a generated `sealed class <Op>Error` union for two or more distinct error models).

See the [Dart HTTP client](../clients/dart/README.md) guide for full typestate, error-matrix, and serialization details.

Operation names stay short when unique. When short names collide, the method and resource path, including API version, distinguish the declarations. Numeric suffixes remain a fallback for schema-name collisions and different payloads within one operation.

## Validation boundaries

Dart `fromJson` verifies required properties (`Missing required property`), expected primitive/list/map shapes, and enum membership. Neither constructors nor `fromJson`/`toJson` enforce `minLength`, `maxLength`, `minimum`, `maximum`, `pattern`, or closed-object extra-key rejection at runtime; those rules are documented in comments beside declarations and fields.

This is not a full OpenAPI validator. Defaults are documented without being applied; UUIDs, dates, business dependencies, and unsupported schema keywords are not automatically validated. Static types and `fromJson` checks do not replace validation by the API server.
