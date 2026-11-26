package openapi

import virtual "core:mem/virtual"
import "core:testing"

@(test)
decode_supported_component_pointers :: proc(t: ^testing.T) {
	arena: virtual.Arena
	err := virtual.arena_init_growing(&arena)
	if !testing.expect(t, err == nil, "test arena should initialize") { return }
	defer virtual.arena_destroy(&arena)
	context.allocator = virtual.arena_allocator(&arena)

	cases := []struct { name: string, ref: string, section: string, expected: string, valid: bool }{
		{"schema pointer escapes", "#/components/schemas/A~1B~0C", "schemas", "A/B~C", true},
		{"parameter percent encoding", "#/components/parameters/A%20B", "parameters", "A B", true},
		{"body pointer", "#/components/requestBodies/Input", "requestBodies", "Input", true},
		{"response pointer", "#/components/responses/Found", "responses", "Found", true},
		{"external document", "https://example.com/spec.json#/components/schemas/A", "schemas", "", false},
		{"wrong section", "#/components/responses/A", "schemas", "", false},
		{"empty target", "#/components/schemas/", "schemas", "", false},
		{"nested target", "#/components/schemas/A/properties/id", "schemas", "", false},
		{"invalid percent encoding", "#/components/schemas/A%GG", "schemas", "", false},
		{"invalid pointer escape", "#/components/schemas/A~2", "schemas", "", false},
		{"unfinished pointer escape", "#/components/schemas/A~", "schemas", "", false},
	}

	for scenario in cases {
		name, valid := component_name(scenario.ref, scenario.section).?
		if !testing.expectf(t, valid == scenario.valid, "%s: unexpected pointer validity", scenario.name) { continue }

		if valid { testing.expect_value(t, name, scenario.expected) }
	}
}
