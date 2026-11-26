package parser

import virtual "core:mem/virtual"
import "core:testing"
import "../openapi"
import "../diagnostics"
import ir "../ir"

@(test)
resolve_multiple_component_hops :: proc(t: ^testing.T) {
	arena: virtual.Arena
	err := virtual.arena_init_growing(&arena)
	if !testing.expect(t, err == nil, "test arena should initialize") { return }
	defer virtual.arena_destroy(&arena)
	context.allocator = virtual.arena_allocator(&arena)

	source := `{"openapi":"3.0.3","components":{
		"parameters":{"A":{"$ref":"#/components/parameters/B"},"B":{"$ref":"#/components/parameters/C"},"C":{"name":"id","in":"query","schema":{"type":"integer"}}},
		"requestBodies":{"A":{"$ref":"#/components/requestBodies/B"},"B":{"$ref":"#/components/requestBodies/C"},"C":{"required":true,"content":{"application/json":{"schema":{"type":"string"}}}}},
		"responses":{"A":{"$ref":"#/components/responses/B"},"B":{"$ref":"#/components/responses/C"},"C":{"content":{"application/json":{"schema":{"type":"boolean"}}}}}
	},"paths":{"/items":{"post":{"parameters":[{"$ref":"#/components/parameters/A"}],"requestBody":{"$ref":"#/components/requestBodies/A"},"responses":{"200":{"$ref":"#/components/responses/A"}}}}}}`
	spec, decoded := openapi.decode(transmute([]byte)source)
	if !testing.expect(t, decoded, "reference chain document should decode") { return }

	issues: diagnostics.Manager
	result := parse(&spec, &issues)
	if !testing.expect(t, result.valid, "all three component chains should resolve") { return }

	testing.expect_value(t, len(issues.issues), 0)

	operation := result.document.paths["/items"]["post"]
	parameter, is_parameter := operation.parameters[.query].fields["id"].model.(ir.Primitive)
	if testing.expect(t, is_parameter, "query parameter should resolve to the final schema") {
		testing.expect_value(t, parameter.type, ir.PrimitiveType.integer)
	}

	body, has_body := operation.request_body.?
	if testing.expect(t, has_body, "request body should resolve") {
		testing.expect(t, body.required, "the final component should define body requiredness")

		model, is_primitive := body.content["application/json"].(ir.Primitive)
		if testing.expect(t, is_primitive, "body content should resolve") {
			testing.expect_value(t, model.type, ir.PrimitiveType.string)
		}
	}

	response, is_response := operation.responses["200"]["application/json"].(ir.Primitive)
	if testing.expect(t, is_response, "response should resolve to the final schema") {
		testing.expect_value(t, response.type, ir.PrimitiveType.boolean)
	}
}

@(test)
reject_cycles_between_different_components :: proc(t: ^testing.T) {
	arena: virtual.Arena
	err := virtual.arena_init_growing(&arena)
	if !testing.expect(t, err == nil, "test arena should initialize") { return }
	defer virtual.arena_destroy(&arena)
	context.allocator = virtual.arena_allocator(&arena)

	source := `{"openapi":"3.0.3","components":{
		"parameters":{"A":{"$ref":"#/components/parameters/%42"},"B":{"$ref":"#/components/parameters/A"}},
		"requestBodies":{"A":{"$ref":"#/components/requestBodies/B"},"B":{"$ref":"#/components/requestBodies/A"}},
		"responses":{"A":{"$ref":"#/components/responses/B"},"B":{"$ref":"#/components/responses/A"}}
	},"paths":{"/items":{"post":{"parameters":[{"$ref":"#/components/parameters/A"}],"requestBody":{"$ref":"#/components/requestBodies/A"},"responses":{"200":{"$ref":"#/components/responses/A"}}}}}}`
	spec, decoded := openapi.decode(transmute([]byte)source)
	if !testing.expect(t, decoded, "cyclic document should decode") { return }

	issues: diagnostics.Manager
	result := parse(&spec, &issues)

	testing.expect(t, !result.valid, "multi-component cycles must fail conversion")
	testing.expect_value(t, result.stats.operations_failed, 1)
	if !testing.expect_value(t, len(issues.issues), 3) { return }

	// Diagnostic order follows map traversal, so compare issues by their source path.
	actual := make(map[string]diagnostics.Issue)
	for issue in issues.issues { actual[issue.path] = issue }

	cases := [3]struct { path: string, subject: string, message: string }{
		{"#/components/parameters/B/$ref", "#/components/parameters/A", "Cyclic parameter reference"},
		{"#/components/requestBodies/B/$ref", "#/components/requestBodies/A", "Cyclic request body reference"},
		{"#/components/responses/B/$ref", "#/components/responses/A", "Cyclic response reference"},
	}

	for scenario in cases {
		issue, found := actual[scenario.path]
		if !testing.expectf(t, found, "missing cycle diagnostic at %s", scenario.path) { continue }

		testing.expect_value(t, issue.severity, diagnostics.Severity.error)
		testing.expect_value(t, issue.subject, scenario.subject)
		testing.expect_value(t, issue.message, scenario.message)
	}
}
