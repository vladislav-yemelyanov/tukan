package parser

import "core:encoding/json"
import virtual "core:mem/virtual"
import "core:testing"
import "../openapi"
import "../diagnostics"
import ir "../ir"

@(test)
parse_document_preserves_typed_operations_and_input :: proc(t: ^testing.T) {
	arena: virtual.Arena
	err := virtual.arena_init_growing(&arena)
	if !testing.expect(t, err == nil, "test arena should initialize") { return }
	defer virtual.arena_destroy(&arena)
	context.allocator = virtual.arena_allocator(&arena)

	source := `{"openapi":"3.0.3","components":{"schemas":{"Operations":{"type":"string"},"Node":{"type":"object","properties":{"next":{"$ref":"#/components/schemas/Node"}}}}},"paths":{"/nodes":{"post":{"operationId":"createNode","requestBody":{"required":true,"content":{"application/json":{"schema":{"$ref":"#/components/schemas/Node"}}}},"responses":{"201":{"content":{"application/json":{"schema":{"$ref":"#/components/schemas/Node"}}}}}}}}}`
	spec, decoded := openapi.decode(transmute([]byte)source)
	if !testing.expect(t, decoded, "document should decode") { return }

	issues: diagnostics.Manager
	result := parse(&spec, &issues)
	if !testing.expect(t, result.valid, "recursive document should produce a valid IR") { return }

	testing.expect_value(t, len(issues.issues), 0)
	testing.expect_value(t, result.stats.schemas_parsed, 2)
	testing.expect_value(t, result.stats.operations_parsed, 1)

	_, schema_exists := result.document.schemas["Operations"]
	testing.expect(t, schema_exists, "a schema named Operations should remain separate from API operations")

	operation := result.document.paths["/nodes"]["post"]
	body, has_body := operation.request_body.?
	if testing.expect(t, has_body, "typed operation should retain a request body") {
		testing.expect(t, body.required, "request body should retain requiredness")

		ref, is_reference := body.content["application/json"].(ir.Reference)
		if testing.expect(t, is_reference, "request body should reference Node") {
			testing.expect_value(t, ref.name, "Node")
		}
	}

	components, _ := spec.components.?
	schemas, _ := components.schemas.?
	schema_type, _ := schemas["Operations"]["type"].(json.String)

	testing.expect_value(t, string(schema_type), "string")
	testing.expect_value(t, len(schemas), 2)
}

@(test)
reject_invalid_nested_fields_with_source_paths :: proc(t: ^testing.T) {
	arena: virtual.Arena
	err := virtual.arena_init_growing(&arena)
	if !testing.expect(t, err == nil, "test arena should initialize") { return }
	defer virtual.arena_destroy(&arena)
	context.allocator = virtual.arena_allocator(&arena)

	source := `{"openapi":"3.0.3","components":{"schemas":{"Broken":{"type":"object","properties":{"a/b~c":{"type":"array","items":{"type":12}},"dictionary":{"additionalProperties":17}}}}}}`
	spec, decoded := openapi.decode(transmute([]byte)source)
	if !testing.expect(t, decoded, "syntax should decode before schema conversion") { return }

	issues: diagnostics.Manager
	result := parse(&spec, &issues)

	testing.expect(t, !result.valid, "malformed schemas must not become successful unknown models")
	testing.expect_value(t, result.stats.schemas_failed, 1)
	testing.expect_value(t, len(result.document.schemas), 0)
	testing.expect_value(t, len(issues.issues), 2)

	// Map traversal can change diagnostic order; source paths identify each failure.
	actual := make(map[string]diagnostics.Issue)
	for issue in issues.issues { actual[issue.path] = issue }

	expected := [2]diagnostics.Issue{
		{path = "#/components/schemas/Broken/properties/a~1b~0c/items/type", subject = "type", severity = .error},
		{path = "#/components/schemas/Broken/properties/dictionary/additionalProperties", subject = "additionalProperties", severity = .error},
	}

	for expected_issue in expected {
		issue, found := actual[expected_issue.path]
		if !testing.expectf(t, found, "missing diagnostic at %s", expected_issue.path) { continue }

		testing.expect_value(t, issue.severity, expected_issue.severity)
		testing.expect_value(t, issue.subject, expected_issue.subject)
	}

	without_diagnostics := parse(&spec)
	testing.expect(t, !without_diagnostics.valid, "conversion failure should not depend on an optional diagnostics manager")
}

@(test)
collect_independent_operation_errors :: proc(t: ^testing.T) {
	arena: virtual.Arena
	err := virtual.arena_init_growing(&arena)
	if !testing.expect(t, err == nil, "test arena should initialize") { return }
	defer virtual.arena_destroy(&arena)
	context.allocator = virtual.arena_allocator(&arena)

	source := `{"openapi":"3.0.3","paths":{"/items":{"post":{"parameters":[{"name":"bad","in":"body"},{"$ref":"#/components/parameters/Missing"}],"requestBody":{"$ref":"#/components/requestBodies/Missing"},"responses":{"200":{"$ref":"#/components/responses/Missing"}}}}}}`
	spec, decoded := openapi.decode(transmute([]byte)source)
	if !testing.expect(t, decoded, "operation should decode") { return }

	issues: diagnostics.Manager
	result := parse(&spec, &issues)

	testing.expect(t, !result.valid, "operation with independent failures should be invalid")
	testing.expect_value(t, result.stats.operations_failed, 1)
	testing.expect_value(t, len(issues.issues), 4)

	actual := make(map[string]diagnostics.Issue)
	for issue in issues.issues { actual[issue.path] = issue }

	expected := [4]diagnostics.Issue{
		{path = "#/paths/~1items/post/parameters/0/in", subject = "body", severity = .error},
		{path = "#/paths/~1items/post/parameters/1/$ref", subject = "#/components/parameters/Missing", severity = .error},
		{path = "#/paths/~1items/post/requestBody/$ref", subject = "#/components/requestBodies/Missing", severity = .error},
		{path = "#/paths/~1items/post/responses/200/$ref", subject = "#/components/responses/Missing", severity = .error},
	}

	for expected_issue in expected {
		issue, found := actual[expected_issue.path]
		if !testing.expectf(t, found, "missing diagnostic at %s", expected_issue.path) { continue }

		testing.expect_value(t, issue.severity, expected_issue.severity)
		testing.expect_value(t, issue.subject, expected_issue.subject)
	}
}

@(test)
component_errors_point_to_definitions :: proc(t: ^testing.T) {
	arena: virtual.Arena
	err := virtual.arena_init_growing(&arena)
	if !testing.expect(t, err == nil, "test arena should initialize") { return }
	defer virtual.arena_destroy(&arena)
	context.allocator = virtual.arena_allocator(&arena)

	source := `{"openapi":"3.0.3","components":{"parameters":{"Filter":{"name":"filter","in":"query","schema":{"$ref":"#/components/schemas/Missing"}},"Loop":{"$ref":"#/components/parameters/%4Coop"}}},"paths":{"/items":{"get":{"responses":{"204":{}},"parameters":[{"$ref":"#/components/parameters/Filter"},{"$ref":"#/components/parameters/Loop"}]}}}}`
	spec, decoded := openapi.decode(transmute([]byte)source)
	if !testing.expect(t, decoded, "component references should decode") { return }

	issues: diagnostics.Manager
	result := parse(&spec, &issues)

	testing.expect(t, !result.valid, "missing schema and canonical reference cycle should fail")
	testing.expect_value(t, len(issues.issues), 2)

	actual := make(map[string]diagnostics.Issue)
	for issue in issues.issues { actual[issue.path] = issue }

	expected := [2]diagnostics.Issue{
		{path = "#/components/parameters/Filter/schema/$ref", subject = "#/components/schemas/Missing", severity = .error},
		{path = "#/components/parameters/Loop/$ref", subject = "#/components/parameters/%4Coop", severity = .error},
	}

	for expected_issue in expected {
		issue, found := actual[expected_issue.path]
		if !testing.expectf(t, found, "missing diagnostic at %s", expected_issue.path) { continue }

		testing.expect_value(t, issue.severity, expected_issue.severity)
		testing.expect_value(t, issue.subject, expected_issue.subject)
	}

	testing.expect_value(t, actual["#/components/parameters/Loop/$ref"].message, "Cyclic parameter reference")
}

@(test)
warn_about_unsupported_features_without_blocking_generation :: proc(t: ^testing.T) {
	arena: virtual.Arena
	err := virtual.arena_init_growing(&arena)
	if !testing.expect(t, err == nil, "test arena should initialize") { return }
	defer virtual.arena_destroy(&arena)
	context.allocator = virtual.arena_allocator(&arena)

	source := `{"openapi":"3.1.0","servers":[{"url":"https://example.com"}],"components":{"securitySchemes":{},"schemas":{"Partial":{"oneOf":[{"type":"string"}],"description":"Annotation","x-owner":"team"}}},"paths":{"/items":{"get":{"parameters":[{"name":"limit","in":"query","style":"form","schema":{"type":"integer","minimum":1}}],"responses":{"200":{"headers":{"X-Id":{}},"content":{"application/json":{"schema":{"type":"string"},"encoding":{}}}}}}}}}`
	spec, decoded := openapi.decode(transmute([]byte)source)
	if !testing.expect(t, decoded, "unsupported features should remain available after decoding") { return }

	issues: diagnostics.Manager
	result := parse(&spec, &issues)

	testing.expect(t, result.valid, "unsupported features should preserve permissive conversion")
	testing.expect(t, !diagnostics.has_errors(&issues), "warnings must not be treated as errors")
	testing.expect_value(t, len(issues.issues), 2)

	actual := make(map[string]diagnostics.Issue)
	for issue in issues.issues { actual[issue.path] = issue }

	expected := [2]diagnostics.Issue{
		{path = "#/openapi", subject = "3.1.0", severity = .warning},
		{path = "#/components/schemas/Partial/oneOf", subject = "oneOf", severity = .warning},
	}

	for expected_issue in expected {
		issue, found := actual[expected_issue.path]
		if !testing.expectf(t, found, "missing diagnostic at %s", expected_issue.path) { continue }

		testing.expect_value(t, issue.severity, expected_issue.severity)
		testing.expect_value(t, issue.subject, expected_issue.subject)
	}
}
