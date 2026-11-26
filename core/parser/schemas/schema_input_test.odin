package schemas

import "core:encoding/json"
import virtual "core:mem/virtual"
import "core:testing"
import "../../diagnostics"
import "../../openapi"
import ir "../../ir"

@(test)
reject_malformed_supported_schema_fields :: proc(t: ^testing.T) {
	arena: virtual.Arena
	err := virtual.arena_init_growing(&arena)
	if !testing.expect(t, err == nil, "test arena should initialize") { return }
	defer virtual.arena_destroy(&arena)
	context.allocator = virtual.arena_allocator(&arena)

	cases := []struct { name: string, source: string, path: string, subject: string }{
		{"numeric reference", `{"$ref":1}`, "#/$ref", "$ref"},
		{"boolean format", `{"format":false}`, "#/format", "format"},
		{"string nullable", `{"nullable":"true"}`, "#/nullable", "nullable"},
		{"null nullable", `{"nullable":null}`, "#/nullable", "nullable"},
		{"numeric type", `{"type":0}`, "#/type", "type"},
		{"union type", `{"type":["string","null"]}`, "#/type", "type"},
		{"unknown type", `{"type":"other"}`, "#/type", "type"},
		{"null type", `{"type":null}`, "#/type", "type"},
		{"scalar required", `{"required":"id"}`, "#/required", "required"},
		{"non-string required entry", `{"required":["id",1]}`, "#/required", "required"},
		{"array properties", `{"properties":[]}`, "#/properties", "properties"},
		{"non-object property", `{"properties":{"id":1}}`, "#/properties/id", ""},
		{"scalar enum", `{"enum":"open"}`, "#/enum", "enum"},
		{"scalar items", `{"type":"array","items":1}`, "#/items", ""},
		{"null items", `{"type":"array","items":null}`, "#/items", ""},
		{"numeric additional properties", `{"additionalProperties":1}`, "#/additionalProperties", "additionalProperties"},
		{"null additional properties", `{"additionalProperties":null}`, "#/additionalProperties", "additionalProperties"},
		{"negative minimum length", `{"type":"string","minLength":-1}`, "#/minLength", "minLength"},
		{"fractional maximum length", `{"type":"string","maxLength":1.5}`, "#/maxLength", "maxLength"},
		{"boolean minimum", `{"type":"integer","minimum":true}`, "#/minimum", "minimum"},
		{"string maximum", `{"type":"number","maximum":"10"}`, "#/maximum", "maximum"},
		{"numeric pattern", `{"type":"string","pattern":1}`, "#/pattern", "pattern"},
		{"string read only", `{"type":"string","readOnly":"true"}`, "#/readOnly", "readOnly"},
		{"numeric write only", `{"type":"string","writeOnly":1}`, "#/writeOnly", "writeOnly"},
	}

	for scenario in cases {
		schema: openapi.Schema
		decode_err := json.unmarshal(transmute([]byte)scenario.source, &schema, .JSON)
		if !testing.expectf(t, decode_err == nil, "%s: schema JSON should decode", scenario.name) { continue }

		issues: diagnostics.Manager
		_, valid := parse(schema, make(map[string]openapi.Schema), &issues)

		testing.expectf(t, !valid, "%s: malformed schema must fail conversion", scenario.name)
		if !testing.expectf(t, len(issues.issues) == 1, "%s: expected one error, got %d", scenario.name, len(issues.issues)) { continue }

		issue := issues.issues[0]
		testing.expect_value(t, issue.path, scenario.path)
		testing.expect_value(t, issue.severity, diagnostics.Severity.error)
		testing.expect_value(t, issue.subject, scenario.subject)
	}
}

@(test)
empty_fields_and_false_values_preserve_schema_meaning :: proc(t: ^testing.T) {
	arena: virtual.Arena
	err := virtual.arena_init_growing(&arena)
	if !testing.expect(t, err == nil, "test arena should initialize") { return }
	defer virtual.arena_destroy(&arena)
	context.allocator = virtual.arena_allocator(&arena)

	unknown_sources := [2]string{`{}`, `{"nullable":false,"required":[]}`}
	for source in unknown_sources {
		schema: openapi.Schema
		if !testing.expect(t, json.unmarshal(transmute([]byte)source, &schema, .JSON) == nil, "unconstrained schema should decode") { continue }

		model, valid := parse(schema, make(map[string]openapi.Schema))
		unknown, is_unknown := model.(ir.UnknownModel)

		testing.expectf(t, valid && is_unknown && !unknown.nullable, "%s: absent type should stay unconstrained and non-nullable", source)
	}

	object_sources := [2]string{`{"properties":{}}`, `{"additionalProperties":false}`}
	for source in object_sources {
		schema: openapi.Schema
		if !testing.expect(t, json.unmarshal(transmute([]byte)source, &schema, .JSON) == nil, "object schema should decode") { continue }

		model, valid := parse(schema, make(map[string]openapi.Schema))
		object, is_object := model.(ir.ObjectModel)
		if !testing.expectf(t, valid && is_object, "%s: an explicit empty object field should still identify an object", source) { continue }

		testing.expect_value(t, len(object.fields), 0)
		testing.expect(t, object.additional_properties == nil, "false must not enable additional properties")
	}

	empty_enum: openapi.Schema
	empty_source: string = `{"enum":[]}`
	if !testing.expect(t, json.unmarshal(transmute([]byte)empty_source, &empty_enum, .JSON) == nil, "empty enum should decode") { return }

	empty_model, empty_valid := parse(empty_enum, make(map[string]openapi.Schema))
	empty_values, is_empty_enum := empty_model.(ir.Enumeration)

	testing.expect(t, empty_valid && is_empty_enum && len(empty_values.values) == 0, "an empty enum must not become an unconstrained schema")

	schema: openapi.Schema
	source: string = `{"enum":[0,false]}`
	if !testing.expect(t, json.unmarshal(transmute([]byte)source, &schema, .JSON) == nil, "zero and false enum should decode") { return }

	model, valid := parse(schema, make(map[string]openapi.Schema))
	values, is_enum := model.(ir.Enumeration)
	if !testing.expect(t, valid && is_enum && len(values.values) == 2, "zero and false must remain enum entries") { return }

	zero, is_integer := values.values[0].(json.Integer)
	flag, is_boolean := values.values[1].(json.Boolean)

	testing.expect(t, is_integer && zero == 0, "numeric zero must retain its JSON type")
	testing.expect(t, is_boolean && !flag, "boolean false must retain its JSON type")
}

@(test)
property_directions_preserve_requiredness_and_reference_annotations :: proc(t: ^testing.T) {
	arena: virtual.Arena
	if !testing.expect(t, virtual.arena_init_growing(&arena) == nil, "arena should initialize") { return }
	defer virtual.arena_destroy(&arena)
	context.allocator = virtual.arena_allocator(&arena)

	source := `{"type":"object","required":["id","password"],"properties":{
		"id":{"type":"string","readOnly":true},
		"password":{"type":"string","writeOnly":true},
		"name":{"type":"string","readOnly":false,"writeOnly":false},
		"computed":{"$ref":"#/components/schemas/Computed"}
	}}`
	schema: openapi.Schema
	if !testing.expect(t, json.unmarshal(transmute([]byte)source, &schema, .JSON) == nil, "schema should decode") { return }
	components := make(map[string]openapi.Schema)
	computed := make(openapi.Schema)
	computed["type"] = json.String("string")
	computed["readOnly"] = json.Boolean(true)
	components["Computed"] = computed
	issues: diagnostics.Manager
	model, valid := parse(schema, components, &issues)
	if !testing.expect(t, valid, "valid direction flags must permit generation") { return }
	fields := model.(ir.ObjectModel).fields
	testing.expect(t, fields["id"].required && fields["id"].read_only, "id must retain response-only requiredness")
	testing.expect(t, fields["password"].required && fields["password"].write_only, "password must retain request-only requiredness")
	testing.expect(t, !fields["name"].read_only && !fields["name"].write_only, "false must not restrict a property direction")
	testing.expect(t, fields["computed"].read_only, "referenced direction flags must apply to the property")
	testing.expect_value(t, len(issues.issues), 0)
}
