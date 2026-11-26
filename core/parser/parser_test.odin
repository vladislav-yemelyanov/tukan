#+feature dynamic-literals

package parser

import "core:encoding/json"
import "core:testing"
import "../openapi"
import virtual "core:mem/virtual"
import ir "../ir"
import "../diagnostics"

@(test)
parse_operation_with_component_references :: proc(t: ^testing.T) {
	arena: virtual.Arena
	arena_err := virtual.arena_init_growing(&arena)
	if !testing.expect(t, arena_err == nil, "test arena should initialize") { return }
	defer virtual.arena_destroy(&arena)
	context.allocator = virtual.arena_allocator(&arena)

	source := `{
		"openapi": "3.0.3",
		"info": {"title": "Test", "version": "1"},
		"components": {
			"schemas": {"User": {"type": "object", "properties": {"id": {"type": "string"}}}},
			"parameters": {"Limit": {"name": "limit", "in": "query", "schema": {"type": "integer"}}},
			"requestBodies": {"Input": {"required": true, "content": {"application/json": {"schema": {"$ref": "#/components/schemas/User"}}}}},
			"responses": {"Found": {"description": "Found", "content": {"application/json": {"schema": {"$ref": "#/components/schemas/User"}}}}}
		},
		"paths": {"/users/{id}": {
			"parameters": [{"$ref": "#/components/parameters/Limit"}, {"name": "id", "in": "path", "required": true, "schema": {"type": "string"}}],
			"post": {
				"operationId": "createUser",
				"parameters": [{"name": "limit", "in": "query", "required": true, "schema": {"type": "string"}}],
				"requestBody": {"$ref": "#/components/requestBodies/Input"},
				"responses": {"200": {"$ref": "#/components/responses/Found"}}
			}
		}}
	}`
	spec: openapi.OpenApiSpec
	err := json.unmarshal(transmute([]byte)source, &spec, .JSON)
	if !testing.expect(t, err == nil, "OpenAPI JSON should parse") { return }

	components, has_components := spec.components.?
	if !testing.expect(t, has_components, "components should be present") { return }
	schemas, has_schemas := components.schemas.?
	if !testing.expect(t, has_schemas, "schemas should be present") { return }

	model, valid := parse_operations(&spec, schemas)
	if !testing.expect(t, valid, "operation references should resolve") { return }

	operation, found := model["/users/{id}"]["post"]
	if !testing.expect(t, found, "post operation should exist") { return }

	operation_id, has_id := operation.operation_id.?
	if testing.expect(t, has_id, "operationId should be preserved") {
		testing.expect_value(t, operation_id, "createUser")
	}

	query := operation.parameters[.query]
	limit, ok_limit := query.fields["limit"].model.(ir.Primitive)
	if testing.expect(t, ok_limit, "limit should be primitive") {
		testing.expect_value(t, limit.type, ir.PrimitiveType.string)
		testing.expect(t, query.fields["limit"].required, "operation parameter should override path parameter")
	}

	testing.expect(t, operation.parameters[.path].fields["id"].required, "path id should be required")

	body, has_body := operation.request_body.?
	if testing.expect(t, has_body, "request body should resolve") {
		testing.expect(t, body.required, "request body should be required")

		ref, is_ref := body.content["application/json"].(ir.Reference)
		if testing.expect(t, is_ref, "request schema should reference User") {
			testing.expect_value(t, ref.name, "User")
		}
	}

	ref, is_ref := operation.responses["200"]["application/json"].(ir.Reference)
	if testing.expect(t, is_ref, "response schema should reference User") {
		testing.expect_value(t, ref.name, "User")
	}
}

@(test)
reject_invalid_operation_references :: proc(t: ^testing.T) {
	arena: virtual.Arena
	arena_err := virtual.arena_init_growing(&arena)
	if !testing.expect(t, arena_err == nil, "test arena should initialize") { return }
	defer virtual.arena_destroy(&arena)
	context.allocator = virtual.arena_allocator(&arena)

	parameters := make(map[string]openapi.Parameter)
	parameters["Loop"] = openapi.Parameter{ref = "#/components/parameters/Loop"}
	components := openapi.Components{parameters = parameters}

	_, cycle_ok, _ := resolve_parameter(openapi.Parameter{ref = "#/components/parameters/Loop"}, components)
	_, missing_ok, _ := resolve_response(openapi.Response{ref = "#/components/responses/Missing"}, components)

	testing.expect(t, !cycle_ok, "cyclic parameter reference should fail")
	testing.expect(t, !missing_ok, "missing response reference should fail")
}

@(test)
parse_all_methods_and_parameter_content :: proc(t: ^testing.T) {
	arena: virtual.Arena
	arena_err := virtual.arena_init_growing(&arena)
	if !testing.expect(t, arena_err == nil, "test arena should initialize") { return }
	defer virtual.arena_destroy(&arena)
	context.allocator = virtual.arena_allocator(&arena)

	source := `{"openapi":"3.0.3","info":{"title":"Test","version":"1"},"paths":{"/resource":{
		"get":{"parameters":[{"name":"filter","in":"query","content":{"application/json":{"schema":{"type":"integer"}}}}],"responses":{"204":{"description":"Empty"}}},
		"post":{"requestBody":{"content":{"application/json":{"schema":{"type":"string"}},"text/plain":{"schema":{"type":"string"}}}},"responses":{"204":{}}},
		"put":{"responses":{"204":{}}},"patch":{"responses":{"204":{}}},"delete":{"responses":{"204":{}}},"head":{"responses":{"204":{}}},"options":{"responses":{"204":{}}},"trace":{"responses":{"204":{}}}
	}}}`
	spec: openapi.OpenApiSpec
	if !testing.expect(t, json.unmarshal(transmute([]byte)source, &spec, .JSON) == nil, "operations document should parse") { return }

	model, valid := parse_operations(&spec, make(map[string]openapi.Schema))
	if !testing.expect(t, valid, "operations should parse") { return }

	methods := model["/resource"]
	for method in ([8]string{"get", "post", "put", "patch", "delete", "head", "options", "trace"}) {
		_, found := methods[method]
		testing.expectf(t, found, "method %s should be present", method)
	}

	content, ok_content := methods["get"].parameters[.query].fields["filter"].model.(ir.ObjectModel)
	if !testing.expect(t, ok_content, "parameter content should be grouped by media type") { return }
	filter, ok_filter := content.fields["application/json"].model.(ir.Primitive)
	if testing.expect(t, ok_filter, "parameter content schema should be primitive") {
		testing.expect_value(t, filter.type, ir.PrimitiveType.integer)
	}

	body, has_body := methods["post"].request_body.?
	if testing.expect(t, has_body, "request body should contain media types") {
		testing.expect(t, !body.required, "request body should be optional by default")

		_, json_found := body.content["application/json"]
		_, text_found := body.content["text/plain"]

		testing.expect(t, json_found && text_found, "both request media types should be preserved")
	}
}

@(test)
reject_missing_and_cyclic_component_references :: proc(t: ^testing.T) {
	arena: virtual.Arena
	arena_err := virtual.arena_init_growing(&arena)
	if !testing.expect(t, arena_err == nil, "test arena should initialize") { return }
	defer virtual.arena_destroy(&arena)
	context.allocator = virtual.arena_allocator(&arena)

	bodies := make(map[string]openapi.RequestBody)
	bodies["Loop"] = openapi.RequestBody{ref = "#/components/requestBodies/Loop"}
	responses := make(map[string]openapi.Response)
	responses["Loop"] = openapi.Response{ref = "#/components/responses/Loop"}
	components := openapi.Components{request_bodies = bodies, responses = responses}

	_, missing_parameter, _ := resolve_parameter(openapi.Parameter{ref = "#/components/parameters/Missing"}, components)
	_, cyclic_body, _ := resolve_body(openapi.RequestBody{ref = "#/components/requestBodies/Loop"}, components)
	_, cyclic_response, _ := resolve_response(openapi.Response{ref = "#/components/responses/Loop"}, components)

	testing.expect(t, !missing_parameter, "missing parameter should fail")
	testing.expect(t, !cyclic_body, "cyclic body reference should fail")
	testing.expect(t, !cyclic_response, "cyclic response reference should fail")
}

@(test)
count_successful_and_failed_operations :: proc(t: ^testing.T) {
	arena: virtual.Arena
	arena_err := virtual.arena_init_growing(&arena)
	if !testing.expect(t, arena_err == nil, "test arena should initialize") { return }
	defer virtual.arena_destroy(&arena)
	context.allocator = virtual.arena_allocator(&arena)

	source: string = `{"openapi":"3.0.3","info":{"title":"Test","version":"1"},"paths":{"/items":{"get":{"responses":{"204":{}}},"post":{"responses":{"200":{"$ref":"#/components/responses/Missing"}}}}}}`
	spec: openapi.OpenApiSpec
	if !testing.expect(t, json.unmarshal(transmute([]byte)source, &spec, .JSON) == nil, "specification should parse") { return }

	issues: diagnostics.Manager
	stats: ParseStats
	_, valid := parse_operations(&spec, make(map[string]openapi.Schema), &issues, &stats)

	testing.expect(t, !valid, "missing response should invalidate operations")
	testing.expect_value(t, stats.operations_parsed, 1)
	testing.expect_value(t, stats.operations_failed, 1)
	testing.expect_value(t, len(issues.issues), 1)
}
