package parser

import "core:fmt"
import virtual "core:mem/virtual"
import "core:testing"
import "../diagnostics"
import "../openapi"

@(test)
reject_invalid_parameter_contracts :: proc(t: ^testing.T) {
	arena: virtual.Arena
	if !testing.expect(t, virtual.arena_init_growing(&arena) == nil, "arena should initialize") { return }
	defer virtual.arena_destroy(&arena)
	context.allocator = virtual.arena_allocator(&arena)

	cases := [?]struct { parameters, code: string }{
		{`[{"name":"q","in":"query"}]`, "parameter-schema-or-content"},
		{`[{"name":"q","in":"query","schema":{},"content":{"application/json":{}}}]`, "parameter-schema-or-content"},
		{`[{"name":"q","in":"query","content":{}}]`, "parameter-content-count"},
		{`[{"name":"q","in":"query","content":{"application/json":{},"text/plain":{}}}]`, "parameter-content-count"},
		{`[{"name":"q","in":"query","schema":{}},{"name":"q","in":"query","schema":{}}]`, "duplicate-parameter"},
	}
	for scenario in cases {
		source := fmt.aprintf(`{{"openapi":"3.0.3","paths":{{"/items":{{"get":{{"parameters":%s,"responses":{{"204":{{}}}}}}}}}}}}`, scenario.parameters)
		spec, decoded := openapi.decode(transmute([]byte)source)
		if !testing.expect(t, decoded, "parameter document should decode") { continue }
		issues: diagnostics.Manager
		result := parse(&spec, &issues)
		testing.expectf(t, !result.valid, "%s must fail conversion", scenario.parameters)
		if !testing.expectf(t, len(issues.issues) == 1, "expected one diagnostic, got %v", issues.issues) { continue }
		testing.expect_value(t, issues.issues[0].code, scenario.code)
		testing.expect_value(t, issues.issues[0].severity, diagnostics.Severity.error)
		if scenario.code == "duplicate-parameter" {
			testing.expect_value(t, issues.issues[0].path, "#/paths/~1items/get/parameters/1")
			testing.expect_value(t, issues.issues[0].subject, "q (query); first declared at #/paths/~1items/get/parameters/0")
		}
	}
}

@(test)
validate_path_templates_and_required_flags :: proc(t: ^testing.T) {
	arena: virtual.Arena
	if !testing.expect(t, virtual.arena_init_growing(&arena) == nil, "arena should initialize") { return }
	defer virtual.arena_destroy(&arena)
	context.allocator = virtual.arena_allocator(&arena)

	cases := [?]struct { route, parameters, code: string }{
		{"/items/{id}", `[]`, "missing-path-parameter"},
		{"/items/{id}", `[{"name":"id","in":"path","schema":{}}]`, "path-parameter-not-required"},
		{"/items/{id}", `[{"name":"id","in":"path","required":false,"schema":{}}]`, "path-parameter-not-required"},
		{"/items", `[{"name":"id","in":"path","required":true,"schema":{}}]`, "unmatched-path-parameter"},
	}
	for scenario in cases {
		source := fmt.aprintf(`{{"openapi":"3.0.3","paths":{{%q:{{"get":{{"parameters":%s,"responses":{{"204":{{}}}}}}}}}}}}`, scenario.route, scenario.parameters)
		spec, decoded := openapi.decode(transmute([]byte)source)
		if !testing.expect(t, decoded, "path document should decode") { continue }
		issues: diagnostics.Manager
		result := parse(&spec, &issues)
		testing.expect(t, !result.valid, "invalid path contract should fail")
		if !testing.expect_value(t, len(issues.issues), 1) { continue }
		testing.expect_value(t, issues.issues[0].code, scenario.code)
	}
}

@(test)
validate_operation_responses :: proc(t: ^testing.T) {
	arena: virtual.Arena
	if !testing.expect(t, virtual.arena_init_growing(&arena) == nil, "arena should initialize") { return }
	defer virtual.arena_destroy(&arena)
	context.allocator = virtual.arena_allocator(&arena)

	cases := [?]struct { operation: string, valid: bool, code: string }{
		{`{}`, false, "missing-operation-responses"},
		{`{"responses":{}}`, false, "missing-operation-responses"},
		{`{"responses":{"x-note":{}}}`, false, "missing-operation-responses"},
		{`{"responses":{"banana":{}}}`, false, "invalid-response-status"},
		{`{"responses":{"600":{}}}`, false, "invalid-response-status"},
		{`{"responses":{"2xx":{}}}`, false, "invalid-response-status"},
		{`{"responses":{"200":{},"default":{},"2XX":{}}}`, true, ""},
	}
	for scenario in cases {
		source := fmt.aprintf(`{{"openapi":"3.0.3","paths":{{"/items":{{"get":%s}}}}}}`, scenario.operation)
		spec, decoded := openapi.decode(transmute([]byte)source)
		if !testing.expect(t, decoded, "response document should decode") { continue }
		issues: diagnostics.Manager
		result := parse(&spec, &issues)
		testing.expectf(t, result.valid == scenario.valid, "unexpected validity for %s", scenario.operation)
		if scenario.valid {
			testing.expect_value(t, len(issues.issues), 0)
		} else if testing.expect_value(t, len(issues.issues), 1) {
			testing.expect_value(t, issues.issues[0].code, scenario.code)
		}
	}
}

@(test)
missing_version_fails_but_unknown_version_warns :: proc(t: ^testing.T) {
	arena: virtual.Arena
	if !testing.expect(t, virtual.arena_init_growing(&arena) == nil, "arena should initialize") { return }
	defer virtual.arena_destroy(&arena)
	context.allocator = virtual.arena_allocator(&arena)

	for source in ([2]string{`{}`, `{"openapi":"3.1.0"}`}) {
		spec, decoded := openapi.decode(transmute([]byte)source)
		if !testing.expect(t, decoded, "document should decode") { continue }
		issues: diagnostics.Manager
		result := parse(&spec, &issues)
		testing.expect(t, result.valid == (spec.openapi != ""), "only missing versions must fail")
		if !testing.expect_value(t, len(issues.issues), 1) { continue }
		testing.expect_value(t, issues.issues[0].path, "#/openapi")
	}
}

@(test)
request_encoding_rejects_non_object_values :: proc(t: ^testing.T) {
	arena: virtual.Arena
	if !testing.expect(t, virtual.arena_init_growing(&arena) == nil, "arena should initialize") { return }
	defer virtual.arena_destroy(&arena)
	context.allocator = virtual.arena_allocator(&arena)

	source := `{"openapi":"3.0.3","paths":{"/upload":{"post":{"requestBody":{"content":{"multipart/form-data":{"schema":{"type":"string"},"encoding":null}}},"responses":{"204":{}}}}}}`
	spec, decoded := openapi.decode(transmute([]byte)source)
	if !testing.expect(t, decoded, "encoding must reach semantic validation") { return }
	issues: diagnostics.Manager
	result := parse(&spec, &issues)
	testing.expect(t, !result.valid, "malformed encoding must prevent generation")
	if !testing.expect_value(t, len(issues.issues), 1) { return }
	testing.expect_value(t, issues.issues[0].code, "invalid-media-encoding")
	testing.expect_value(t, issues.issues[0].path, "#/paths/~1upload/post/requestBody/content/multipart~1form-data/encoding")
}
