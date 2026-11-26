#+feature dynamic-literals

package schemas

import "core:encoding/json"
import "core:testing"
import virtual "core:mem/virtual"
import ir "../../ir"
import "../../diagnostics"
import "../../openapi"

@(test)
parse_schema_preserves_nested_fields :: proc(t: ^testing.T) {
	arena: virtual.Arena
	arena_err := virtual.arena_init_growing(&arena)
	if !testing.expect(t, arena_err == nil, "test arena should initialize") { return }
	defer virtual.arena_destroy(&arena)
	context.allocator = virtual.arena_allocator(&arena)

	source := `{
		"type": "object",
		"required": ["items"],
		"properties": {
			"items": {
				"type": "array",
				"items": {
					"type": "object",
					"required": ["count"],
					"properties": {
						"count": {"type": "integer", "nullable": true},
						"owner": {"$ref": "#/components/schemas/User"}
					}
				}
			},
			"name": {"type": "string"}
		},
		"additionalProperties": {"type": "boolean"}
	}`
	schema: openapi.Schema
	err := json.unmarshal(transmute([]byte)source, &schema, .JSON)
	if !testing.expect(t, err == nil, "schema JSON should parse") { return }

	schemas := make(map[string]openapi.Schema)
	schemas["User"] = openapi.Schema{"type" = json.String("string")}

	model, valid := parse(schema, schemas)
	if !testing.expect(t, valid, "schema should convert") { return }

	object, ok := model.(ir.ObjectModel)
	if !testing.expect(t, ok, "schema should be an object") { return }

	testing.expect(t, object.fields["items"].required, "items should be required")
	testing.expect(t, !object.fields["name"].required, "name should be optional")

	additional, has_additional := object.additional_properties.?
	if testing.expect(t, has_additional, "additional properties should be preserved") {
		primitive, is_primitive := additional^.(ir.Primitive)
		if testing.expect(t, is_primitive, "additional values should be primitive") {
			testing.expect_value(t, primitive.type, ir.PrimitiveType.boolean)
		}
	}

	array, is_array := object.fields["items"].model.(ir.ArrayModel)
	if !testing.expect(t, is_array, "items should be an array") { return }
	item, is_object := array.items^.(ir.ObjectModel)
	if !testing.expect(t, is_object, "array items should preserve their object schema") { return }

	count, is_primitive := item.fields["count"].model.(ir.Primitive)
	if testing.expect(t, is_primitive, "count should be primitive") {
		testing.expect_value(t, count.type, ir.PrimitiveType.integer)
		testing.expect(t, count.nullable && item.fields["count"].required, "count should be nullable and required")
	}

	owner, is_ref := item.fields["owner"].model.(ir.Reference)
	if testing.expect(t, is_ref, "owner should be a reference") {
		testing.expect_value(t, owner.name, "User")
	}
}

@(test)
validate_schema_references :: proc(t: ^testing.T) {
	arena: virtual.Arena
	arena_err := virtual.arena_init_growing(&arena)
	if !testing.expect(t, arena_err == nil, "test arena should initialize") { return }
	defer virtual.arena_destroy(&arena)
	context.allocator = virtual.arena_allocator(&arena)

	schemas := make(map[string]openapi.Schema)
	schemas["A/B~C"] = openapi.Schema{"type" = json.String("string")}
	valid_schema := openapi.Schema{"$ref" = json.String("#/components/schemas/A~1B~0C")}
	missing := openapi.Schema{"$ref" = json.String("#/components/schemas/Missing")}
	invalid_schema := openapi.Schema{"$ref" = json.String("#/components/schemas/A~2B")}

	_, valid := parse(valid_schema, schemas)
	testing.expect(t, valid, "escaped local reference should resolve")

	_, missing_valid := parse(missing, schemas)
	testing.expect(t, !missing_valid, "missing reference should fail")

	_, invalid_valid := parse(invalid_schema, schemas)
	testing.expect(t, !invalid_valid, "invalid JSON Pointer escape should fail")

	model, _ := parse(valid_schema, schemas)
	ref, ok := model.(ir.Reference)
	if testing.expect(t, ok, "valid schema should become a reference") {
		testing.expect_value(t, ref.name, "A/B~C")
	}
}

@(test)
parse_enums_and_dictionary :: proc(t: ^testing.T) {
	arena: virtual.Arena
	arena_err := virtual.arena_init_growing(&arena)
	if !testing.expect(t, arena_err == nil, "test arena should initialize") { return }
	defer virtual.arena_destroy(&arena)
	context.allocator = virtual.arena_allocator(&arena)

	source := `{"type":"object","additionalProperties":{"type":"integer","enum":[1,2]}}`
	schema: openapi.Schema
	err := json.unmarshal(transmute([]byte)source, &schema, .JSON)
	if !testing.expect(t, err == nil, "dictionary schema should parse") { return }

	model, valid := parse(schema, make(map[string]openapi.Schema))
	if !testing.expect(t, valid, "schema should convert") { return }

	dictionary, ok := model.(ir.ObjectModel)
	if !testing.expect(t, ok, "dictionary should be an object") { return }
	additional, has_additional := dictionary.additional_properties.?
	if !testing.expect(t, has_additional, "dictionary value schema should be preserved") { return }
	enum_model, is_enum := additional^.(ir.Enumeration)
	if !testing.expect(t, is_enum, "dictionary values should preserve their enum") { return }
	if !testing.expect_value(t, len(enum_model.values), 2) { return }

	first, is_integer := enum_model.values[0].(json.Integer)
	if testing.expect(t, is_integer, "enum should preserve numeric values") {
		testing.expect_value(t, first, json.Integer(1))
	}
}

@(test)
parse_primitives_and_formats :: proc(t: ^testing.T) {
	arena: virtual.Arena
	arena_err := virtual.arena_init_growing(&arena)
	if !testing.expect(t, arena_err == nil, "test arena should initialize") { return }
	defer virtual.arena_destroy(&arena)
	context.allocator = virtual.arena_allocator(&arena)

	cases := [4]struct { source: string, expected: ir.PrimitiveType }{
		{`{"type":"string","format":"binary"}`, .string},
		{`{"type":"number"}`, .number},
		{`{"type":"integer"}`, .integer},
		{`{"type":"boolean"}`, .boolean},
	}

	for test in cases {
		schema: openapi.Schema
		err := json.unmarshal(transmute([]byte)test.source, &schema, .JSON)
		if !testing.expectf(t, err == nil, "schema should parse: %s", test.source) { continue }

		model, valid := parse(schema, make(map[string]openapi.Schema))
		if !testing.expect(t, valid, "schema should convert") { continue }
		primitive, ok := model.(ir.Primitive)
		if !testing.expectf(t, ok, "expected primitive: %s", test.source) { continue }

		testing.expect_value(t, primitive.type, test.expected)
		if test.expected == .string {
			format, has_format := primitive.format.?
			if testing.expect(t, has_format, "string format should be preserved") {
				testing.expect_value(t, format, "binary")
			}
		}
	}
}

@(test)
parse_optional_and_unconstrained_schemas :: proc(t: ^testing.T) {
	arena: virtual.Arena
	arena_err := virtual.arena_init_growing(&arena)
	if !testing.expect(t, arena_err == nil, "test arena should initialize") { return }
	defer virtual.arena_destroy(&arena)
	context.allocator = virtual.arena_allocator(&arena)

	for source in ([2]string{`{"type":"object","additionalProperties":false}`, `{"type":"object"}`}) {
		schema: openapi.Schema
		if !testing.expect(t, json.unmarshal(transmute([]byte)source, &schema, .JSON) == nil, "object schema should parse") { continue }

		model, valid := parse(schema, make(map[string]openapi.Schema))
		if !testing.expect(t, valid, "schema should convert") { continue }
		object, ok := model.(ir.ObjectModel)
		if testing.expect(t, ok, "object should remain an object") {
			_, has_additional := object.additional_properties.?

			testing.expect(t, !has_additional, "closed or unspecified additional properties have no value schema")
		}
	}

	open_schema: openapi.Schema
	open_source: string = `{"type":"object","additionalProperties":true}`
	if !testing.expect(t, json.unmarshal(transmute([]byte)open_source, &open_schema, .JSON) == nil, "open object should parse") { return }

	open_model, valid := parse(open_schema, make(map[string]openapi.Schema))
	if !testing.expect(t, valid, "open schema should convert") { return }
	open_object, is_object := open_model.(ir.ObjectModel)
	if !testing.expect(t, is_object, "open object should be an object") { return }
	additional, has_additional := open_object.additional_properties.?
	if testing.expect(t, has_additional, "open object should preserve additional values") {
		_, is_unknown := additional^.(ir.UnknownModel)

		testing.expect(t, is_unknown, "unrestricted additional values should be unknown")
	}

	unknown, unknown_valid := parse(openapi.Schema{"nullable" = json.Boolean(true)}, make(map[string]openapi.Schema))
	if !testing.expect(t, unknown_valid, "unconstrained schema should convert") { return }
	value, is_unknown := unknown.(ir.UnknownModel)
	if testing.expect(t, is_unknown, "untyped schema should become unknown") {
		testing.expect(t, value.nullable, "unknown nullable flag should be preserved")
	}
}

@(test)
parse_string_and_boolean_enums :: proc(t: ^testing.T) {
	arena: virtual.Arena
	arena_err := virtual.arena_init_growing(&arena)
	if !testing.expect(t, arena_err == nil, "test arena should initialize") { return }
	defer virtual.arena_destroy(&arena)
	context.allocator = virtual.arena_allocator(&arena)

	for source in ([2]string{`{"type":"string","enum":["open","closed"],"nullable":true}`, `{"type":"boolean","enum":[true,false]}`}) {
		schema: openapi.Schema
		if !testing.expect(t, json.unmarshal(transmute([]byte)source, &schema, .JSON) == nil, "enum schema should parse") { continue }

		model, valid := parse(schema, make(map[string]openapi.Schema))
		if !testing.expect(t, valid, "schema should convert") { continue }
		enum_model, ok := model.(ir.Enumeration)
		if !testing.expect(t, ok, "enum should remain an enumeration") { continue }
		if !testing.expect_value(t, len(enum_model.values), 2) { continue }

		if source == `{"type":"string","enum":["open","closed"],"nullable":true}` {
			first, is_string := enum_model.values[0].(json.String)
			if testing.expect(t, is_string, "first enum value should be a string") {
				testing.expect_value(t, string(first), "open")
			}

			testing.expect(t, enum_model.nullable, "nullable enum should remain nullable")
		} else {
			first, is_bool := enum_model.values[0].(json.Boolean)
			if testing.expect(t, is_bool, "first enum value should be boolean") {
				testing.expect(t, bool(first), "first boolean value should be true")
			}
		}
	}
}

@(test)
validate_nested_references :: proc(t: ^testing.T) {
	arena: virtual.Arena
	arena_err := virtual.arena_init_growing(&arena)
	if !testing.expect(t, arena_err == nil, "test arena should initialize") { return }
	defer virtual.arena_destroy(&arena)
	context.allocator = virtual.arena_allocator(&arena)

	schemas := make(map[string]openapi.Schema)
	schemas["A B"] = openapi.Schema{"type" = json.String("string")}
	cases := [3]struct { source: string, valid: bool }{
		{`{"type":"array","items":{"$ref":"#/components/schemas/A%20B"}}`, true},
		{`{"type":"object","properties":{"owner":{"$ref":"#/components/schemas/Missing"}}}`, false},
		{`{"type":"object","additionalProperties":{"$ref":"#/components/schemas/Missing"}}`, false},
	}

	for test in cases {
		schema: openapi.Schema
		if !testing.expect(t, json.unmarshal(transmute([]byte)test.source, &schema, .JSON) == nil, "nested reference schema should parse") { continue }

		_, valid := parse(schema, schemas)
		testing.expectf(t, valid == test.valid, "unexpected reference validation result for %s", test.source)
	}
}

@(test)
collect_multiple_schema_errors :: proc(t: ^testing.T) {
	arena: virtual.Arena
	arena_err := virtual.arena_init_growing(&arena)
	if !testing.expect(t, arena_err == nil, "test arena should initialize") { return }
	defer virtual.arena_destroy(&arena)
	context.allocator = virtual.arena_allocator(&arena)

	source: string = `{"type":"object","properties":{"first":{"$ref":"#/components/schemas/MissingA"},"second":{"$ref":"#/components/schemas/MissingB"}}}`
	schema: openapi.Schema
	if !testing.expect(t, json.unmarshal(transmute([]byte)source, &schema, .JSON) == nil, "schema should parse") { return }

	issues: diagnostics.Manager
	_, valid := parse(schema, make(map[string]openapi.Schema), &issues)

	testing.expect(t, !valid, "missing references should invalidate schema")
	testing.expect_value(t, len(issues.issues), 2)

	actual := make(map[string]diagnostics.Issue)
	for issue in issues.issues { actual[issue.path] = issue }

	for name in ([2]string{"first", "second"}) {
		path := diagnostics.child_path(diagnostics.child_path("#/properties", name), "$ref")
		issue, found := actual[path]
		if !testing.expectf(t, found, "missing reference error at %s", path) { continue }

		testing.expect_value(t, issue.severity, diagnostics.Severity.error)

		expected_ref := "#/components/schemas/MissingA"
		if name == "second" { expected_ref = "#/components/schemas/MissingB" }

		testing.expect_value(t, issue.subject, expected_ref)
	}
}

@(test)
parse_preserves_explicit_closed_objects :: proc(t: ^testing.T) {
	arena: virtual.Arena
	if !testing.expect(t, virtual.arena_init_growing(&arena) == nil, "arena should initialize") { return }
	defer virtual.arena_destroy(&arena)
	context.allocator = virtual.arena_allocator(&arena)

	closed := openapi.Schema{"type" = json.String("object"), "additionalProperties" = json.Boolean(false)}
	model, valid := parse(closed, nil)
	if !testing.expect(t, valid, "closed object should parse") { return }
	object := model.(ir.ObjectModel)
	testing.expect(t, object.closed && object.additional_properties == nil, "explicit false must survive without an extra-value schema")

	unspecified := openapi.Schema{"type" = json.String("object")}
	model, valid = parse(unspecified, nil)
	testing.expect(t, valid && !model.(ir.ObjectModel).closed, "omission must remain distinct from explicit false")
}
