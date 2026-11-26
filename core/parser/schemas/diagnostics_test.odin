package schemas

import "core:encoding/json"
import virtual "core:mem/virtual"
import "core:testing"
import "../../diagnostics"
import "../../openapi"
import ir "../../ir"

@(test)
validate_schema_annotations :: proc(t: ^testing.T) {
	arena: virtual.Arena
	if !testing.expect(t, virtual.arena_init_growing(&arena) == nil, "arena should initialize") { return }
	defer virtual.arena_destroy(&arena)
	context.allocator = virtual.arena_allocator(&arena)

	cases := [?]struct { source, code, path: string }{
		{`{"type":"string","minLength":3,"maxLength":2}`, "invalid-length-range", "#/maxLength"},
		{`{"type":"integer","minimum":11,"maximum":10}`, "invalid-number-range", "#/maximum"},
		{`{"type":"string","default":12}`, "default-type-mismatch", "#/default"},
		{`{"type":"string","readOnly":true,"writeOnly":true}`, "conflicting-property-direction", "#/writeOnly"},
	}
	for scenario in cases {
		schema: openapi.Schema
		if !testing.expect(t, json.unmarshal(transmute([]byte)scenario.source, &schema, .JSON) == nil, "schema should decode") { continue }
		issues: diagnostics.Manager
		_, valid := parse(schema, nil, &issues)
		testing.expectf(t, !valid, "%s must fail conversion", scenario.source)
		found := false
		for issue in issues.issues {
			if issue.code == scenario.code && issue.path == scenario.path && issue.severity == .error { found = true }
		}
		testing.expectf(t, found, "%s should report %s at %s", scenario.source, scenario.code, scenario.path)
	}

	schema: openapi.Schema
	source := `{"type":"string","minLength":0,"maxLength":0,"default":"","readOnly":false}`
	if !testing.expect(t, json.unmarshal(transmute([]byte)source, &schema, .JSON) == nil, "valid annotation schema should decode") { return }
	issues: diagnostics.Manager
	model, valid := parse(schema, nil, &issues)
	testing.expect(t, valid, "valid annotations must permit generation")
	testing.expect_value(t, len(issues.issues), 0)
	annotations := model.(ir.Primitive).annotations
	testing.expect_value(t, annotations["minLength"].(json.Integer), 0)
	testing.expect_value(t, string(annotations["default"].(json.String)), "")
}

@(test)
reject_missing_items_and_enum_type_conflicts :: proc(t: ^testing.T) {
	arena: virtual.Arena
	if !testing.expect(t, virtual.arena_init_growing(&arena) == nil, "arena should initialize") { return }
	defer virtual.arena_destroy(&arena)
	context.allocator = virtual.arena_allocator(&arena)

	cases := [?]struct { source, code, path: string }{
		{`{"type":"array"}`, "missing-array-items", "#/items"},
		{`{"type":"integer","enum":["text"]}`, "enum-type-mismatch", "#/enum/0"},
		{`{"type":"integer","enum":[1.5]}`, "enum-type-mismatch", "#/enum/0"},
		{`{"type":"boolean","enum":[null]}`, "enum-type-mismatch", "#/enum/0"},
	}
	for scenario in cases {
		schema: openapi.Schema
		if !testing.expect(t, json.unmarshal(transmute([]byte)scenario.source, &schema, .JSON) == nil, "schema should decode") { continue }
		issues: diagnostics.Manager
		_, valid := parse(schema, nil, &issues)
		testing.expectf(t, !valid, "%s must fail conversion", scenario.source)
		if !testing.expectf(t, len(issues.issues) == 1, "%s should have one diagnostic, got %v", scenario.source, issues.issues) { continue }
		testing.expect_value(t, issues.issues[0].code, scenario.code)
		testing.expect_value(t, issues.issues[0].path, scenario.path)
		testing.expect_value(t, issues.issues[0].severity, diagnostics.Severity.error)
		_, without_manager := parse(schema, nil)
		testing.expect(t, !without_manager, "validity must not depend on collecting diagnostics")
	}
}

@(test)
explicit_type_takes_priority_over_object_keywords :: proc(t: ^testing.T) {
	arena: virtual.Arena
	if !testing.expect(t, virtual.arena_init_growing(&arena) == nil, "arena should initialize") { return }
	defer virtual.arena_destroy(&arena)
	context.allocator = virtual.arena_allocator(&arena)

	schema: openapi.Schema
	source := `{"type":"string","properties":{"id":{"type":"integer"}}}`
	if !testing.expect(t, json.unmarshal(transmute([]byte)source, &schema, .JSON) == nil, "schema should decode") { return }
	issues: diagnostics.Manager
	model, valid := parse(schema, nil, &issues, "#/components/schemas/Value")
	primitive, is_primitive := model.(ir.Primitive)
	testing.expect(t, valid && is_primitive, "object keywords must not turn a declared string into an object")
	testing.expect_value(t, primitive.type, ir.PrimitiveType.string)
	if !testing.expect_value(t, len(issues.issues), 1) { return }
	testing.expect_value(t, issues.issues[0].code, "inapplicable-schema-keyword")
	testing.expect_value(t, issues.issues[0].severity, diagnostics.Severity.warning)
	testing.expect_value(t, primitive.source_path, "#/components/schemas/Value")
}

@(test)
warn_about_required_properties_without_a_model :: proc(t: ^testing.T) {
	arena: virtual.Arena
	if !testing.expect(t, virtual.arena_init_growing(&arena) == nil, "arena should initialize") { return }
	defer virtual.arena_destroy(&arena)
	context.allocator = virtual.arena_allocator(&arena)

	schema: openapi.Schema
	source := `{"required":["a/b~c"]}`
	if !testing.expect(t, json.unmarshal(transmute([]byte)source, &schema, .JSON) == nil, "schema should decode") { return }
	issues: diagnostics.Manager
	_, valid := parse(schema, nil, &issues)
	testing.expect(t, valid, "requiring an additional property is legal but cannot be represented")
	if !testing.expect_value(t, len(issues.issues), 1) { return }
	testing.expect_value(t, issues.issues[0].code, "unrepresented-required-property")
	testing.expect_value(t, issues.issues[0].subject, "a/b~c")
	testing.expect_value(t, issues.issues[0].path, "#/required/0")
	testing.expect_value(t, issues.issues[0].severity, diagnostics.Severity.warning)
}
