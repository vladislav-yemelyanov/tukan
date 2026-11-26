package generators

import "core:encoding/json"
import "core:fmt"
import virtual "core:mem/virtual"
import "core:os"
import "core:strings"
import "core:testing"
import ir "../ir"

@(test)
typescript_generates_schema_types :: proc(t: ^testing.T) {
	arena: virtual.Arena
	arena_err := virtual.arena_init_growing(&arena)
	if !testing.expect(t, arena_err == nil, "test arena should initialize") { return }
	defer virtual.arena_destroy(&arena)
	context.allocator = virtual.arena_allocator(&arena)

	dir, dir_err := os.make_directory_temp("", "tukan-ts-test-*", context.allocator)
	if !testing.expect(t, dir_err == nil, "temporary directory should be created") { return }
	defer os.remove_all(dir)
	path := fmt.aprintf("%s/spec.ts", dir)

	tags_item: ir.Model = ir.Primitive{type = .string}
	extra_value: ir.Model = ir.Primitive{type = .integer}
	fields := make(map[string]ir.Field)
	fields["name"] = ir.Field{model = ir.Primitive{type = .string}, required = true}
	fields["owner"] = ir.Field{model = ir.Reference{name = "User", nullable = true}}
	fields["tags"] = ir.Field{model = ir.ArrayModel{items = &tags_item}}
	fields["file"] = ir.Field{model = ir.Primitive{type = .string, format = "binary"}}

	values := [2]json.Value{json.String("open"), json.String("closed")}
	schemas := make(map[string]ir.Model)
	schemas["User"] = ir.Primitive{type = .string}
	schemas["Status"] = ir.Enumeration{values = values[:]}
	schemas["Project"] = ir.ObjectModel{fields = fields, additional_properties = &extra_value}
	unknown: ir.Model = ir.UnknownModel{}
	schemas["Problem"] = ir.ObjectModel{fields = fields, additional_properties = &unknown}

	err := generate_typescript(&ir.Document{schemas = schemas}, path)
	if !testing.expect(t, err == nil, "TypeScript file should be written") { return }

	output, read_err := os.read_entire_file(path, context.allocator)
	if !testing.expect(t, read_err == nil, "TypeScript file should be readable") { return }
	text := string(output)

	for expected in ([6]string{
		`"name": string;`, `"owner"?: Schemas["User"] | null;`, `"tags"?: string[];`,
		`"file"?: Blob;`, `"Status": "open" | "closed";`, `[key: string]: number |`,
	}) {
		testing.expectf(t, strings.contains(text, expected), "TypeScript should contain %s", expected)
	}
	testing.expect(t, strings.contains(text, "[key: string]: unknown;"), "unknown additional properties should not repeat named field types")
	user_index := strings.index(text, `"User":`)
	ops_index := strings.index(text, `"Operations":`)
	testing.expect(t, user_index >= 0 && ops_index > user_index, "Operations should be emitted after schema entries")
}

@(test)
dart_generates_classes_and_enum_values :: proc(t: ^testing.T) {
	arena: virtual.Arena
	arena_err := virtual.arena_init_growing(&arena)
	if !testing.expect(t, arena_err == nil, "test arena should initialize") { return }
	defer virtual.arena_destroy(&arena)
	context.allocator = virtual.arena_allocator(&arena)

	dir, dir_err := os.make_directory_temp("", "tukan-dart-test-*", context.allocator)
	if !testing.expect(t, dir_err == nil, "temporary directory should be created") { return }
	defer os.remove_all(dir)
	path := fmt.aprintf("%s/spec.dart", dir)

	fields := make(map[string]ir.Field)
	fields["name"] = ir.Field{model = ir.Primitive{type = .string}, required = true}
	fields["count"] = ir.Field{model = ir.Primitive{type = .integer, nullable = true}}
	fields["file"] = ir.Field{model = ir.Primitive{type = .string, format = "binary"}, required = true}

	values := [2]json.Value{json.Integer(1), json.Integer(2)}
	schemas := make(map[string]ir.Model)
	schemas["Project"] = ir.ObjectModel{fields = fields}
	schemas["Priority"] = ir.Enumeration{values = values[:]}

	err := generate_dart(&ir.Document{schemas = schemas}, path)
	if !testing.expect(t, err == nil, "Dart file should be written") { return }

	output, read_err := os.read_entire_file(path, context.allocator)
	if !testing.expect(t, read_err == nil, "Dart file should be readable") { return }
	text := string(output)

	for expected in ([9]string{
		"class Project {", "final String name;", "final int? count;",
		"final List<int> file;", "required this.name,", "this.count,", "value0(1),",
		"copyWith(", "operator ==",
	}) {
		testing.expectf(t, strings.contains(text, expected), "Dart should contain %s", expected)
	}
	testing.expect(t, strings.contains(text, "int get hashCode"), "Dart should generate hashCode")
	testing.expect(t, !strings.contains(text, "OptionalValue"), "Dart should use nullable fields instead of OptionalValue")
}

@(test)
dart_generates_readable_operation_types :: proc(t: ^testing.T) {
	arena: virtual.Arena
	arena_err := virtual.arena_init_growing(&arena)
	if !testing.expect(t, arena_err == nil, "test arena should initialize") { return }
	defer virtual.arena_destroy(&arena)
	context.allocator = virtual.arena_allocator(&arena)

	dir, dir_err := os.make_directory_temp("", "tukan-operation-test-*", context.allocator)
	if !testing.expect(t, dir_err == nil, "temporary directory should be created") { return }
	defer os.remove_all(dir)
	path := fmt.aprintf("%s/spec.dart", dir)

	query_fields := make(map[string]ir.Field)
	query_fields["limit"] = ir.Field{model = ir.Primitive{type = .integer}}

	content := make(ir.Content)
	content["application/json"] = ir.Reference{name = "Project"}
	responses := make(map[string]ir.Content)
	responses["200"] = content

	parameters := make(map[ir.ParameterLocation]ir.ObjectModel)
	parameters[.query] = ir.ObjectModel{fields = query_fields}

	methods := make(map[string]ir.Operation)
	methods["get"] = ir.Operation{operation_id = "listProjects", parameters = parameters, responses = responses}
	methods["delete"] = ir.Operation{responses = responses}
	paths := make(map[string]map[string]ir.Operation)
	paths["/projects"] = methods

	schemas := make(map[string]ir.Model)
	schemas["Project"] = ir.Primitive{type = .string}

	bearer := make(ir.SecurityRequirement)
	bearer["Bearer"] = nil
	schemes := make(json.Object)
	scheme := make(json.Object)
	scheme["type"] = json.String("http")
	scheme["scheme"] = json.String("bearer")
	schemes["Bearer"] = scheme
	document := ir.Document{schemas = schemas, paths = paths, security = []ir.SecurityRequirement{bearer}, security_schemes = schemes}
	err := generate_dart(&document, path)
	if !testing.expect(t, err == nil, "Dart operation types should be written") { return }

	output, read_err := os.read_entire_file(path, context.allocator)
	if !testing.expect(t, read_err == nil, "Dart file should be readable") { return }
	text := string(output)

	testing.expect(t, strings.contains(text, "class ListProjectsQueryParameters {"), "operationId should name the query parameters")
	testing.expect(t, strings.contains(text, "/// GET /projects"), "operation documentation should appear on its parameter type")
	testing.expect(t, strings.contains(text, "/// Authentication: Bearer."), "operation type documentation should retain effective authentication")
	testing.expect(t, strings.contains(text, "abstract final class Paths {"), "Dart should emit a Paths tree root")
	testing.expect(t, strings.contains(text, "/// DELETE /projects"), "DELETE /projects should be documented on its Paths operation method")
	testing.expect(t, !strings.contains(text, "Security schemes (documentation only"), "security definitions must not form a file-level catalog")
	testing.expect(t, !strings.contains(text, "\n// GET /projects"), "operation documentation must not form a separate file-level catalog")
	testing.expect(t, !strings.contains(text, "ListProjectsResponse200"), "a referenced response must use Project directly without an alias")
	testing.expect(t, !strings.contains(text, "class Operations {"), "Dart should not emit a deeply nested Operations class")
}

@(test)
dart_generates_typed_path_tree :: proc(t: ^testing.T) {
	arena: virtual.Arena
	if !testing.expect(t, virtual.arena_init_growing(&arena) == nil, "test arena should initialize") { return }
	defer virtual.arena_destroy(&arena)
	context.allocator = virtual.arena_allocator(&arena)

	dir, dir_err := os.make_directory_temp("", "tukan-dart-paths-test-*", context.allocator)
	if !testing.expect(t, dir_err == nil, "temporary directory should be created") { return }
	defer os.remove_all(dir)
	path := fmt.aprintf("%s/spec.dart", dir)

	schemas := make(map[string]ir.Model)
	schemas["Paths"] = ir.Primitive{type = .string}
	user_fields := make(map[string]ir.Field)
	user_fields["id"] = ir.Field{model = ir.Primitive{type = .string}, required = true}
	schemas["User"] = ir.ObjectModel{fields = user_fields}
	problem_fields := make(map[string]ir.Field)
	problem_fields["detail"] = ir.Field{model = ir.Primitive{type = .string}}
	schemas["Problem"] = ir.ObjectModel{fields = problem_fields}

	path_fields := make(map[string]ir.Field)
	path_fields["id"] = ir.Field{model = ir.Primitive{type = .string}, required = true}
	query_fields := make(map[string]ir.Field)
	query_fields["expand"] = ir.Field{model = ir.Primitive{type = .boolean}}

	get_params := make(map[ir.ParameterLocation]ir.ObjectModel)
	get_params[.path] = ir.ObjectModel{fields = path_fields}
	get_params[.query] = ir.ObjectModel{fields = query_fields}

	ok_content := make(ir.Content)
	ok_content["application/json"] = ir.Reference{name = "User"}
	bad_content := make(ir.Content)
	bad_content["application/problem+json"] = ir.Reference{name = "Problem"}

	get_responses := make(map[string]ir.Content)
	get_responses["200"] = ok_content
	get_responses["400"] = bad_content
	get_responses["401"] = make(ir.Content)

	post_content := make(ir.Content)
	post_content["application/json"] = ir.Reference{name = "User"}
	post_responses := make(map[string]ir.Content)
	post_responses["204"] = make(ir.Content)

	users_methods := make(map[string]ir.Operation)
	users_methods["post"] = ir.Operation{
		request_body = ir.RequestBody{required = true, content = post_content},
		responses    = post_responses,
	}

	user_by_id_methods := make(map[string]ir.Operation)
	user_by_id_methods["get"] = ir.Operation{parameters = get_params, responses = get_responses}

	paths := make(map[string]map[string]ir.Operation)
	paths["/api/v1/users"] = users_methods
	paths["/api/v1/users/{id}"] = user_by_id_methods

	err := generate_dart(&ir.Document{schemas = schemas, paths = paths}, path)
	if !testing.expect(t, err == nil, "Dart path tree should be written") { return }

	output, read_err := os.read_entire_file(path, context.allocator)
	if !testing.expect(t, read_err == nil, "Dart path tree file should be readable") { return }
	text := string(output)

	for expected in ([16]string{
		"typedef Paths = String;",
		"abstract final class Paths_ {",
		"typedef OperationRequest<T, E> = ({",
		"static const PathApi api = PathApi._();",
		"PathApiV1 get v1 => const PathApiV1._();",
		"PathApiV1Users get users => const PathApiV1Users._();",
		"PathApiV1UsersPost get post => const PathApiV1UsersPost._();",
		"OperationRequest<void, Never> get request => (",
		"PathApiV1UsersPostReady body({",
		"PathApiV1UsersPostReady withBody(User value) =>",
		"PathApiV1UsersById get byId => const PathApiV1UsersById._();",
		"PathApiV1UsersByIdBound call(String id) => PathApiV1UsersByIdBound._(id);",
		"PathApiV1UsersByIdGet query({",
		"PathApiV1UsersByIdGet withQuery(GetUsersByIdQueryParameters? value) =>",
		"OperationRequest<User, Problem> get request => (",
		"400: (Object? data) => Problem.fromJson",
	}) {
		testing.expectf(t, strings.contains(text, expected), "Dart Paths tree should contain %s", expected)
	}
}

@(test)
generators_report_file_errors :: proc(t: ^testing.T) {
	arena: virtual.Arena
	arena_err := virtual.arena_init_growing(&arena)
	if !testing.expect(t, arena_err == nil, "test arena should initialize") { return }
	defer virtual.arena_destroy(&arena)
	context.allocator = virtual.arena_allocator(&arena)

	dir, dir_err := os.make_directory_temp("", "tukan-error-test-*", context.allocator)
	if !testing.expect(t, dir_err == nil, "temporary directory should be created") { return }
	defer os.remove_all(dir)
	path := fmt.aprintf("%s/missing/spec", dir)
	schemas := make(map[string]ir.Model)

	testing.expect(t, generate_typescript(&ir.Document{schemas = schemas}, path) != nil, "TypeScript generator should report an unwritable path")
	testing.expect(t, generate_dart(&ir.Document{schemas = schemas}, path) != nil, "Dart generator should report an unwritable path")
}

@(test)
typescript_preserves_complex_enum_values :: proc(t: ^testing.T) {
	arena: virtual.Arena
	arena_err := virtual.arena_init_growing(&arena)
	if !testing.expect(t, arena_err == nil, "test arena should initialize") { return }
	defer virtual.arena_destroy(&arena)
	context.allocator = virtual.arena_allocator(&arena)

	value: json.Value
	source: string = `[{"kind":"active"},[1,true,null]]`
	err := json.unmarshal(transmute([]byte)source, &value, .JSON)
	if !testing.expect(t, err == nil, "enum values should parse") { return }

	values, ok := value.(json.Array)
	if !testing.expect(t, ok, "enum values should be an array") { return }

	model: ir.Model = ir.Enumeration{values = values[:]}
	output := model_to_ts(model)

	testing.expect(t, strings.contains(output, `{"kind":"active"}`), "object enum value should be emitted as a literal type")
	testing.expect(t, strings.contains(output, `[1,true,null]`), "array enum value should be emitted as a tuple type")
}

@(test)
dart_operation_names_handle_collisions :: proc(t: ^testing.T) {
	arena: virtual.Arena
	arena_err := virtual.arena_init_growing(&arena)
	if !testing.expect(t, arena_err == nil, "test arena should initialize") { return }
	defer virtual.arena_destroy(&arena)
	context.allocator = virtual.arena_allocator(&arena)

	query_fields := make(map[string]ir.Field)
	query_fields["limit"] = ir.Field{model = ir.Primitive{type = .integer}}

	parameters := make(map[ir.ParameterLocation]ir.ObjectModel)
	parameters[.query] = ir.ObjectModel{fields = query_fields}

	methods := make(map[string]ir.Operation)
	methods["get"] = ir.Operation{parameters = parameters}
	paths := make(map[string]map[string]ir.Operation)
	paths["/projects"] = methods

	// Occupy the fallback name before generating the operation's parameter type.
	schemas := make(map[string]ir.Model)
	schemas["GetProjectsQueryParameters"] = ir.Primitive{type = .string}

	document := ir.Document{paths = paths}
	generate_operation_types(&schemas, &document)

	_, found := schemas["GetProjectsQueryParameters2"]
	testing.expect(t, found, "fallback method/path name should receive a suffix when it collides with a schema")

	original, ok := schemas["GetProjectsQueryParameters"].(ir.Primitive)
	if testing.expect(t, ok, "existing schema should not be replaced") {
		testing.expect_value(t, original.type, ir.PrimitiveType.string)
	}
}

@(test)
typescript_projects_operations_without_replacing_named_schemas :: proc(t: ^testing.T) {
	arena: virtual.Arena
	err := virtual.arena_init_growing(&arena)
	if !testing.expect(t, err == nil, "test arena should initialize") { return }
	defer virtual.arena_destroy(&arena)
	context.allocator = virtual.arena_allocator(&arena)

	dir, dir_err := os.make_directory_temp("", "tukan-operation-export-*", context.allocator)
	if !testing.expect(t, dir_err == nil, "temporary directory should be created") { return }
	defer os.remove_all(dir)
	path := fmt.aprintf("%s/spec.ts", dir)

	document := ir.Document{schemas = make(map[string]ir.Model), paths = make(map[string]map[string]ir.Operation)}
	document.schemas["Operations"] = ir.Primitive{type = .string}
	content := make(ir.Content)
	content["application/json"] = ir.Primitive{type = .integer}
	methods := make(map[string]ir.Operation)
	methods["post"] = ir.Operation{request_body = ir.RequestBody{content = content}}
	document.paths["/items"] = methods

	write_err := generate_typescript(&document, path)
	if !testing.expect(t, write_err == nil, "TypeScript file should be written") { return }

	output, read_err := os.read_entire_file(path, context.allocator)
	if !testing.expect(t, read_err == nil, "TypeScript output should be readable") { return }
	text := string(output)

	for expected in ([5]string{`"Operations": string;`, `"Operations_": {`, `"/items": {`, `"requestBody"?: {`, `"application/json": number;`}) {
		testing.expectf(t, strings.contains(text, expected), "public TypeScript output should contain %s", expected)
	}

	// Synthetic exports belong only to the output, not to the caller's document.
	testing.expect_value(t, len(document.schemas), 1)
	_, synthetic_schema := document.schemas["Operations_"]
	testing.expect(t, !synthetic_schema, "generation should preserve the input document")
	schema_ops_index := strings.index(text, `"Operations":`)
	generated_ops_index := strings.index(text, `"Operations_":`)
	testing.expect(t, schema_ops_index >= 0 && generated_ops_index > schema_ops_index, "Operations_ should appear after named schemas")
}

@(test)
operation_types_reuse_models_and_deduplicate_inline_payloads :: proc(t: ^testing.T) {
	arena: virtual.Arena
	if !testing.expect(t, virtual.arena_init_growing(&arena) == nil, "arena should initialize") { return }
	defer virtual.arena_destroy(&arena)
	context.allocator = virtual.arena_allocator(&arena)

	fields := make(map[string]ir.Field)
	fields["label"] = {model = ir.Primitive{type = .string}, required = true}
	first_item: ir.Model = ir.ObjectModel{fields = fields, source_path = "#/first"}
	second_item: ir.Model = ir.ObjectModel{fields = fields, source_path = "#/second"}
	content := make(ir.Content)
	content["application/json"] = ir.ArrayModel{items = &first_item}
	content["application/xml"] = ir.ArrayModel{items = &second_item}
	responses := make(map[string]ir.Content)
	responses["200"] = content
	responses["202"] = content
	existing := make(ir.Content)
	existing["application/json"] = ir.Reference{name = "ProblemDetails"}
	responses["400"] = existing
	methods := make(map[string]ir.Operation)
	methods["get"] = {responses = responses}
	paths := make(map[string]map[string]ir.Operation)
	paths["/api/v1/accounts/{id}"] = methods
	document := ir.Document{paths = paths}
	schemas := make(map[string]ir.Model)
	generate_operation_types(&schemas, &document)

	_, item_exists := schemas["GetAccountsByIdResponseItem"]
	testing.expect(t, item_exists, "inline array items need a usable named model")
	testing.expect_value(t, len(schemas), 1)
	item := schemas["GetAccountsByIdResponseItem"]
	comment := annotation_comment(item, .dart)
	testing.expect(t, strings.contains(comment, "Response status: 200.") && strings.contains(comment, "Response status: 202."), "reused inline types should document every status")
	_, alias_exists := schemas["GetAccountsByIdResponse400"]
	testing.expect(t, !alias_exists, "an existing response model must not gain an alias")
	testing.expect_value(t, operation_name("get", "/service/api/v1/accounts/{id}"), "GetAccountsById")
}

@(test)
operation_types_reuse_referenced_request_models_and_name_inline_payloads :: proc(t: ^testing.T) {
	arena: virtual.Arena
	if !testing.expect(t, virtual.arena_init_growing(&arena) == nil, "arena should initialize") { return }
	defer virtual.arena_destroy(&arena)
	context.allocator = virtual.arena_allocator(&arena)

	inline_fields := make(map[string]ir.Field)
	inline_fields["label"] = {model = ir.Primitive{type = .string}, required = true}
	content := make(ir.Content)
	content["application/json"] = ir.Reference{name = "Order", source_path = "#/json"}
	content["application/xml"] = ir.ObjectModel{fields = inline_fields, source_path = "#/xml"}
	content["application/problem+json"] = ir.ObjectModel{fields = inline_fields, source_path = "#/problem"}
	methods := make(map[string]ir.Operation)
	methods["post"] = {operation_id = "createOrder", request_body = ir.RequestBody{content = content}}
	paths := make(map[string]map[string]ir.Operation)
	paths["/orders"] = methods
	document := ir.Document{paths = paths}
	schemas := make(map[string]ir.Model)
	generate_operation_types(&schemas, &document)

	_, wrapper_exists := schemas["CreateOrderRequestBody"]
	testing.expect(t, !wrapper_exists, "referenced payloads should not create RequestBody wrappers")
	_, inline_exists := schemas["CreateOrderRequest"]
	testing.expect(t, inline_exists, "inline object request payload should receive a named model")
	testing.expect_value(t, len(schemas), 1)
}

@(test)
dart_paths_emit_callable_operations_and_bound_param_segments :: proc(t: ^testing.T) {
	arena: virtual.Arena
	if !testing.expect(t, virtual.arena_init_growing(&arena) == nil, "arena should initialize") { return }
	defer virtual.arena_destroy(&arena)
	context.allocator = virtual.arena_allocator(&arena)

	dir, dir_err := os.make_directory_temp("", "tukan-dart-paths-test-*", context.allocator)
	if !testing.expect(t, dir_err == nil, "temporary directory should be created") { return }
	defer os.remove_all(dir)
	path := fmt.aprintf("%s/spec.dart", dir)

	nullable_body_fields := make(map[string]ir.Field)
	nullable_body_fields["title"] = {model = ir.Primitive{type = .string}, required = true}
	schemas := make(map[string]ir.Model)
	schemas["PatchBody"] = ir.ObjectModel{fields = nullable_body_fields, nullable = true}

	err_bad_fields := make(map[string]ir.Field)
	err_bad_fields["reason"] = {model = ir.Primitive{type = .string}, required = true}
	schemas["ErrBad"] = ir.ObjectModel{fields = err_bad_fields}

	err_auth_fields := make(map[string]ir.Field)
	err_auth_fields["message"] = {model = ir.Primitive{type = .string}, required = true}
	schemas["ErrAuth"] = ir.ObjectModel{fields = err_auth_fields}

	org_param := make(map[string]ir.Field)
	org_param["orgId"] = {model = ir.Primitive{type = .string}, required = true}
	task_param := make(map[string]ir.Field)
	task_param["taskId"] = {model = ir.Primitive{type = .string}, required = true}
	org_task_param := make(map[string]ir.Field)
	org_task_param["orgId"] = {model = ir.Primitive{type = .string}, required = true}
	org_task_param["taskId"] = {model = ir.Primitive{type = .string}, required = true}

	query_fields := make(map[string]ir.Field)
	query_fields["limit"] = {model = ir.Primitive{type = .integer}}
	header_fields := make(map[string]ir.Field)
	header_fields["xTrace"] = {model = ir.Primitive{type = .string}}
	cookie_fields := make(map[string]ir.Field)
	cookie_fields["sid"] = {model = ir.Primitive{type = .string}}

	patch_params := make(map[ir.ParameterLocation]ir.ObjectModel)
	patch_params[.path] = ir.ObjectModel{fields = org_task_param}
	patch_params[.query] = ir.ObjectModel{fields = query_fields}
	patch_params[.header] = ir.ObjectModel{fields = header_fields}
	patch_params[.cookie] = ir.ObjectModel{fields = cookie_fields}
	patch_content := make(ir.Content)
	patch_content["application/json"] = ir.Reference{name = "PatchBody"}

	org_task_ops := make(map[string]ir.Operation)
	org_task_ops["patch"] = {
		operation_id = "patchOrgTask",
		parameters   = patch_params,
		request_body = ir.RequestBody{required = true, content = patch_content},
		responses    = make(map[string]ir.Content),
	}

	org_params := make(map[ir.ParameterLocation]ir.ObjectModel)
	org_params[.path] = ir.ObjectModel{fields = org_param}
	org_ops := make(map[string]ir.Operation)
	org_ops["get"] = {operation_id = "getOrg", parameters = org_params, responses = make(map[string]ir.Content)}

	// Conflicting path parameter types on /items/{id} must fall back to pathParams + make pathParams(...) -> Ready.
	item_get_param := make(map[string]ir.Field)
	item_get_param["id"] = {model = ir.Primitive{type = .integer}, required = true}
	item_get_params := make(map[ir.ParameterLocation]ir.ObjectModel)
	item_get_params[.path] = ir.ObjectModel{fields = item_get_param}

	item_del_param := make(map[string]ir.Field)
	item_del_param["id"] = {model = ir.Primitive{type = .string}, required = true}
	item_del_params := make(map[ir.ParameterLocation]ir.ObjectModel)
	item_del_params[.path] = ir.ObjectModel{fields = item_del_param}

	item_ops := make(map[string]ir.Operation)
	item_ops["get"] = {operation_id = "getItem", parameters = item_get_params, responses = make(map[string]ir.Content)}
	item_ops["delete"] = {operation_id = "deleteItem", parameters = item_del_params, responses = make(map[string]ir.Content)}

	// Two required slots (headers + body) emit a 4-state typestate chain (base, S1, S2, Ready).
	two_req_headers := make(map[string]ir.Field)
	two_req_headers["xAuth"] = {model = ir.Primitive{type = .string}, required = true}
	two_req_params := make(map[ir.ParameterLocation]ir.ObjectModel)
	two_req_params[.header] = ir.ObjectModel{fields = two_req_headers}
	two_req_content := make(ir.Content)
	two_req_content["application/json"] = ir.Reference{name = "PatchBody"}
	two_req_ops := make(map[string]ir.Operation)
	two_req_ops["post"] = {
		operation_id = "createSecureOrder",
		parameters   = two_req_params,
		request_body = ir.RequestBody{required = true, content = two_req_content},
		responses    = make(map[string]ir.Content),
	}

	multi_err_ok := make(ir.Content)
	multi_err_ok["application/json"] = ir.Reference{name = "PatchBody"}
	multi_err_bad := make(ir.Content)
	multi_err_bad["application/json"] = ir.Reference{name = "ErrBad"}
	multi_err_auth := make(ir.Content)
	multi_err_auth["application/json"] = ir.Reference{name = "ErrAuth"}
	multi_err_responses := make(map[string]ir.Content)
	multi_err_responses["200"] = multi_err_ok
	multi_err_responses["400"] = multi_err_bad
	multi_err_responses["401"] = multi_err_auth
	multi_err_responses["404"] = multi_err_auth
	multi_err_ops := make(map[string]ir.Operation)
	multi_err_ops["post"] = {
		operation_id = "runMultiErr",
		responses    = multi_err_responses,
	}

	paths := make(map[string]map[string]ir.Operation)
	paths["/orgs/{orgId}"] = org_ops
	paths["/orgs/{orgId}/tasks/{taskId}"] = org_task_ops
	paths["/items/{id}"] = item_ops
	paths["/secure-orders"] = two_req_ops
	paths["/multi-err"] = multi_err_ops

	document := ir.Document{schemas = schemas, paths = paths}
	write_err := generate_dart(&document, path)
	if !testing.expect(t, write_err == nil, "Dart file should be written") { return }

	output, read_err := os.read_entire_file(path, context.allocator)
	if !testing.expect(t, read_err == nil, "Dart output should be readable") { return }
	text := string(output)

	for expected in ([29]string{
		"PathOrgsByOrgIdBound call(String orgId) => PathOrgsByOrgIdBound._(orgId);",
		"PathOrgsByOrgIdTasks get tasks => PathOrgsByOrgIdTasks._(_orgId);",
		"PathOrgsByOrgIdTasksByTaskIdBound call(String taskId) => PathOrgsByOrgIdTasksByTaskIdBound._(_orgId, taskId);",
		"String get method => 'PATCH';",
		"String get path => \"/orgs/{orgId}/tasks/{taskId}\";",
		"PathOrgsByOrgIdTasksByTaskIdPatchReady body({",
		"PathOrgsByOrgIdTasksByTaskIdPatchReady._(_orgId, _taskId,",
		"body: PatchBodyValue(",
		"PathOrgsByOrgIdTasksByTaskIdPatchReady withBody(PatchBody value) =>",
		"query({",
		"headers({",
		"cookie({",
		"pathParams: <String, dynamic>{\"orgId\": _orgId, \"taskId\": _taskId},",
		"PathItemsByIdGetReady pathParams({",
		"PathItemsByIdGetReady withPathParams(GetItemPathParameters value) =>",
		"final class PathSecureOrdersPostS1 {",
		"final class PathSecureOrdersPostS2 {",
		"PathSecureOrdersPostS1 headers({",
		"PathSecureOrdersPostS2 body({",
		"OperationRequest<void, Never> get request => (",
		"sealed class RunMultiErrError {",
		"ErrBad? get errBad => null;",
		"ErrAuth? get errAuth => null;",
		"final class RunMultiErrErrorErrBad extends RunMultiErrError {",
		"final class RunMultiErrErrorErrAuth extends RunMultiErrError {",
		"OperationRequest<PatchBody, RunMultiErrError> get request => (",
		"400: (Object? data) => RunMultiErrErrorErrBad(",
		"401: (Object? data) => RunMultiErrErrorErrAuth(",
		"404: (Object? data) => RunMultiErrErrorErrAuth(",
	}) {
		testing.expectf(t, strings.contains(text, expected), "Dart output should contain: %s", expected)
	}
	testing.expect(t, !strings.contains(text, "PathItemsByIdBound"), "conflicting param types must fall back to unbound segment")
}
