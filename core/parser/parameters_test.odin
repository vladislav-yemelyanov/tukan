package parser

import virtual "core:mem/virtual"
import "core:testing"
import "../openapi"
import ir "../ir"

@(test)
parameter_locations_keep_equal_names_separate :: proc(t: ^testing.T) {
	arena: virtual.Arena
	err := virtual.arena_init_growing(&arena)
	if !testing.expect(t, err == nil, "test arena should initialize") { return }
	defer virtual.arena_destroy(&arena)
	context.allocator = virtual.arena_allocator(&arena)

	source := `{"openapi":"3.0.3","paths":{"/items/{id}":{
		"parameters":[{"name":"id","in":"path","required":true,"schema":{"type":"string"}},{"name":"id","in":"query","schema":{"type":"integer"}},{"name":"id","in":"header","schema":{"type":"integer"}}],
		"get":{"responses":{"204":{}},"parameters":[{"name":"id","in":"header","required":true,"schema":{"type":"string"}},{"name":"id","in":"cookie","schema":{"type":"boolean"}}]}
	}}}`

	spec, decoded := openapi.decode(transmute([]byte)source)
	if !testing.expect(t, decoded, "parameter document should decode") { return }

	result := parse(&spec)
	if !testing.expect(t, result.valid, "all four supported locations should convert") { return }

	groups := result.document.paths["/items/{id}"]["get"].parameters
	testing.expect_value(t, len(groups), 4)

	cases := [4]struct { location: ir.ParameterLocation, expected_type: ir.PrimitiveType, required: bool }{
		{.path, .string, true}, {.query, .integer, false}, {.header, .string, true}, {.cookie, .boolean, false},
	}

	for scenario in cases {
		group, found := groups[scenario.location]
		if !testing.expectf(t, found, "missing %v parameter group", scenario.location) { continue }

		testing.expect_value(t, len(group.fields), 1)

		field := group.fields["id"]
		model, primitive := field.model.(ir.Primitive)
		if !testing.expectf(t, primitive, "%v id should remain a primitive", scenario.location) { continue }

		testing.expect_value(t, model.type, scenario.expected_type)
		testing.expect_value(t, field.required, scenario.required)
	}
}
