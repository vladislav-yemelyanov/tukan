package generators

import virtual "core:mem/virtual"
import "core:testing"
import ir "../ir"

@(test)
directions_preserve_recursive_links_and_the_original_document :: proc(t: ^testing.T) {
	arena: virtual.Arena
	if !testing.expect(t, virtual.arena_init_growing(&arena) == nil, "arena should initialize") { return }
	defer virtual.arena_destroy(&arena)
	context.allocator = virtual.arena_allocator(&arena)

	fields := make(map[string]ir.Field)
	fields["id"] = {model = ir.Primitive{type = .string}, required = true, read_only = true}
	fields["password"] = {model = ir.Primitive{type = .string}, required = true, write_only = true}
	fields["label"] = {model = ir.Primitive{type = .string}, required = true}
	ref: ir.Model = ir.Reference{name = "User", nullable = true}
	fields["children"] = {model = ir.ArrayModel{items = &ref}}
	inline_fields := make(map[string]ir.Field)
	inline_fields["computed"] = {model = ir.Primitive{type = .boolean}, read_only = true}
	fields["nested"] = {model = ir.ObjectModel{fields = inline_fields, additional_properties = &ref}}
	schemas := make(map[string]ir.Model)
	schemas["User"] = ir.ObjectModel{fields = fields}
	schemas["Alias"] = ir.Reference{name = "User"}
	schemas["UserRequest"] = ir.Primitive{type = .string}
	content := make(ir.Content)
	content["application/json"] = ir.Reference{name = "Alias"}
	methods := make(map[string]ir.Operation)
	responses := make(map[string]ir.Content)
	responses["200"] = content
	methods["post"] = {request_body = ir.RequestBody{content = content}, responses = responses}
	paths := make(map[string]map[string]ir.Operation)
	paths["/users"] = methods
	source := ir.Document{schemas = schemas, paths = paths}
	projected := project_directions(&source)

	request := projected.schemas["UserRequest2"].(ir.ObjectModel)
	response := projected.schemas["UserResponse"].(ir.ObjectModel)
	_, request_id := request.fields["id"]
	_, response_password := response.fields["password"]
	testing.expect(t, !request_id, "read-only id must be absent from requests even when required")
	testing.expect(t, !response_password, "write-only password must be absent from responses even when required")
	testing.expect(t, request.fields["password"].required && response.fields["id"].required, "retained directional fields must stay required")
	testing.expect(t, request.fields["label"].required && response.fields["label"].required, "ordinary required fields must stay required")
	children := request.fields["children"].model.(ir.ArrayModel)
	testing.expect_value(t, children.items^.(ir.Reference).name, "UserRequest2")
	testing.expect(t, children.items^.(ir.Reference).nullable, "recursive item nullability must survive projection")
	nested := request.fields["nested"].model.(ir.ObjectModel)
	testing.expect_value(t, len(nested.fields), 0)
	additional, _ := nested.additional_properties.?
	testing.expect_value(t, additional^.(ir.Reference).name, "UserRequest2")
	testing.expect_value(t, projected.schemas["AliasResponse"].(ir.Reference).name, "UserResponse")
	body, _ := projected.paths["/users"]["post"].request_body.?
	testing.expect_value(t, body.content["application/json"].(ir.Reference).name, "AliasRequest")
	testing.expect_value(t, projected.paths["/users"]["post"].responses["200"]["application/json"].(ir.Reference).name, "AliasResponse")

	testing.expect_value(t, len(source.schemas), 3)
	testing.expect_value(t, len(fields), 5)
	testing.expect_value(t, ref.(ir.Reference).name, "User")
	testing.expect_value(t, content["application/json"].(ir.Reference).name, "Alias")
	testing.expect_value(t, len(inline_fields), 1)
}

@(test)
directional_variants_are_created_only_when_fields_change :: proc(t: ^testing.T) {
	arena: virtual.Arena
	if !testing.expect(t, virtual.arena_init_growing(&arena) == nil, "arena should initialize") { return }
	defer virtual.arena_destroy(&arena)
	context.allocator = virtual.arena_allocator(&arena)

	read_fields := make(map[string]ir.Field)
	read_fields["id"] = {model = ir.Primitive{type = .string}, read_only = true}
	write_fields := make(map[string]ir.Field)
	write_fields["password"] = {model = ir.Primitive{type = .string}, write_only = true}
	schemas := make(map[string]ir.Model)
	schemas["AccountResponse"] = ir.ObjectModel{fields = read_fields}
	schemas["SecretRequest"] = ir.ObjectModel{fields = write_fields}
	schemas["ExistingResponse"] = ir.ObjectModel{fields = write_fields}
	schemas["AccountList"] = ir.Reference{name = "AccountResponse"}

	request_content := make(ir.Content)
	request_content["application/json"] = ir.Reference{name = "AccountList"}
	response_content := make(ir.Content)
	response_content["application/json"] = ir.Reference{name = "AccountResponse"}
	response_content["application/vnd.secret+json"] = ir.Reference{name = "SecretRequest"}
	response_content["application/vnd.existing+json"] = ir.Reference{name = "ExistingResponse"}
	responses := make(map[string]ir.Content)
	responses["200"] = response_content
	methods := make(map[string]ir.Operation)
	methods["post"] = {request_body = ir.RequestBody{content = request_content}, responses = responses}
	paths := make(map[string]map[string]ir.Operation)
	paths["/accounts"] = methods
	source := ir.Document{schemas = schemas, paths = paths}
	projected := project_directions(&source)

	_, request_exists := projected.schemas["AccountRequest"]
	_, response_exists := projected.schemas["SecretResponse"]
	_, response_view_exists := projected.schemas["ExistingResponseView"]
	_, list_request_exists := projected.schemas["AccountListRequest"]
	testing.expect(t, request_exists && response_exists && response_view_exists && list_request_exists, "only changed reachable directions and their dependent schemas should get clear names")
	for name in ([4]string{"AccountResponseResponse", "SecretRequestRequest", "AccountListResponse", "ExistingResponseRequest"}) {
		_, exists := projected.schemas[name]
		testing.expectf(t, !exists, "%s must not be generated", name)
	}
	body, _ := projected.paths["/accounts"]["post"].request_body.?
	testing.expect_value(t, body.content["application/json"].(ir.Reference).name, "AccountListRequest")
	testing.expect_value(t, projected.paths["/accounts"]["post"].responses["200"]["application/json"].(ir.Reference).name, "AccountResponse")
	testing.expect_value(t, projected.paths["/accounts"]["post"].responses["200"]["application/vnd.secret+json"].(ir.Reference).name, "SecretResponse")
	testing.expect_value(t, projected.paths["/accounts"]["post"].responses["200"]["application/vnd.existing+json"].(ir.Reference).name, "ExistingResponseView")
	testing.expect_value(t, len(source.schemas), 4)
}

@(test)
directional_variants_skip_unreachable_schemas :: proc(t: ^testing.T) {
	arena: virtual.Arena
	if !testing.expect(t, virtual.arena_init_growing(&arena) == nil, "arena should initialize") { return }
	defer virtual.arena_destroy(&arena)
	context.allocator = virtual.arena_allocator(&arena)

	read_fields := make(map[string]ir.Field)
	read_fields["balance"] = {model = ir.Primitive{type = .number}, read_only = true}
	read_fields["currency"] = {model = ir.Primitive{type = .string}}
	page_fields := make(map[string]ir.Field)
	item_ref: ir.Model = ir.Reference{name = "AdminAccountResponse"}
	page_fields["data"] = {model = ir.ArrayModel{items = &item_ref}}
	write_fields := make(map[string]ir.Field)
	write_fields["secret"] = {model = ir.Primitive{type = .string}, write_only = true}

	schemas := make(map[string]ir.Model)
	schemas["AdminAccountResponse"] = ir.ObjectModel{fields = read_fields}
	schemas["AdminAccountPaging"] = ir.ObjectModel{fields = page_fields}
	schemas["CreateSecret"] = ir.ObjectModel{fields = write_fields}
	schemas["Orphan"] = ir.ObjectModel{fields = read_fields}

	req_content := make(ir.Content)
	req_content["application/json"] = ir.Reference{name = "CreateSecret"}
	resp_content := make(ir.Content)
	resp_content["application/json"] = ir.Reference{name = "AdminAccountPaging"}
	responses := make(map[string]ir.Content)
	responses["200"] = resp_content

	methods := make(map[string]ir.Operation)
	methods["get"] = {responses = responses}
	methods["post"] = {request_body = ir.RequestBody{content = req_content}, responses = make(map[string]ir.Content)}
	paths := make(map[string]map[string]ir.Operation)
	paths["/accounts"] = methods
	source := ir.Document{schemas = schemas, paths = paths}
	projected := project_directions(&source)

	for unexpected in ([5]string{"AdminAccountRequest", "AdminAccountPagingRequest", "CreateSecretResponse", "OrphanRequest", "OrphanResponse"}) {
		_, exists := projected.schemas[unexpected]
		testing.expectf(t, !exists, "unreachable directional variant %s must not be generated", unexpected)
	}
	testing.expect_value(t, len(projected.schemas), 4)
}
