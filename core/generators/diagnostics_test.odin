package generators

import "core:encoding/json"
import "core:fmt"
import virtual "core:mem/virtual"
import "core:os"
import "core:strings"
import "core:testing"
import "../diagnostics"
import ir "../ir"

@(test)
alias_cycles_fail_for_typescript_and_dart :: proc(t: ^testing.T) {
	arena: virtual.Arena
	if !testing.expect(t, virtual.arena_init_growing(&arena) == nil, "arena should initialize") { return }
	defer virtual.arena_destroy(&arena)
	context.allocator = virtual.arena_allocator(&arena)

	dir, err := os.make_directory_temp("", "tukan-cycle-*", context.allocator)
	if !testing.expect(t, err == nil, "workspace should exist") { return }
	defer os.remove_all(dir)
	document := ir.Document{schemas = make(map[string]ir.Model)}
	document.schemas["A"] = ir.Reference{name = "B", source_path = "#/components/schemas/A"}
	document.schemas["B"] = ir.Reference{name = "A", source_path = "#/components/schemas/B"}

	for language in GenerationLanguage {
		issues: diagnostics.Manager
		valid := validate_generation(&document, &issues, language)
		testing.expectf(t, !valid, "alias cycle must fail for %v", language)
		if !testing.expect_value(t, len(issues.issues), 1) { continue }
		testing.expect_value(t, issues.issues[0].code, "unsupported-alias-cycle")
		testing.expect_value(t, issues.issues[0].path, "#/components/schemas/A")
		testing.expect_value(t, issues.issues[0].language, generation_language_name(language))
	}

	path := fmt.aprintf("%s/previous.ts", dir)
	if !testing.expect(t, os.write_entire_file(path, "previous output") == nil, "previous output should exist") { return }
	testing.expect(t, generate_typescript(&document, path) != nil, "cycle must fail even without a diagnostics manager")
	previous, read_err := os.read_entire_file(path, context.allocator)
	if testing.expect(t, read_err == nil, "previous output should remain readable") {
		testing.expect_value(t, string(previous), "previous output")
	}
	testing.expect(t, generate_dart(&document, fmt.aprintf("%s/new.dart", dir)) != nil, "Dart cycle should fail")
	testing.expect(t, !os.exists(fmt.aprintf("%s/new.dart", dir)), "invalid output must not be created")
}

@(test)
recursive_objects_remain_supported_and_dart_collection_aliases_fail :: proc(t: ^testing.T) {
	arena: virtual.Arena
	if !testing.expect(t, virtual.arena_init_growing(&arena) == nil, "arena should initialize") { return }
	defer virtual.arena_destroy(&arena)
	context.allocator = virtual.arena_allocator(&arena)

	ref: ir.Model = ir.Reference{name = "Node"}
	fields := make(map[string]ir.Field)
	fields["children"] = {model = ir.ArrayModel{items = &ref}}
	document := ir.Document{schemas = make(map[string]ir.Model)}
	document.schemas["Node"] = ir.ObjectModel{fields = fields}
	for language in GenerationLanguage {
		testing.expectf(t, validate_generation(&document, nil, language), "recursive objects must remain supported in %v", language)
	}

	document.schemas["Node"] = ir.ArrayModel{items = &ref}
	testing.expect(t, validate_generation(&document, nil, .typescript), "TypeScript supports recursive array properties")
	testing.expect(t, !validate_generation(&document, nil, .dart), "Dart cannot represent a recursive collection typedef")
}

@(test)
generator_warnings_keep_component_paths_and_do_not_repeat :: proc(t: ^testing.T) {
	arena: virtual.Arena
	if !testing.expect(t, virtual.arena_init_growing(&arena) == nil, "arena should initialize") { return }
	defer virtual.arena_destroy(&arena)
	context.allocator = virtual.arena_allocator(&arena)

	fields := make(map[string]ir.Field)
	fields["label"] = {model = ir.Primitive{type = .string}, required = true}
	additional: ir.Model = ir.Primitive{type = .integer}
	document := ir.Document{schemas = make(map[string]ir.Model), paths = make(map[string]map[string]ir.Operation)}
	document.schemas["Value"] = ir.ObjectModel{fields = fields, additional_properties = &additional, source_path = "#/components/schemas/A~1B~0C"}
	content := make(ir.Content)
	content["application/json"] = ir.Primitive{type = .string}
	methods := make(map[string]ir.Operation)
	for method in ([2]string{"post", "put"}) {
		methods[method] = ir.Operation{request_body = ir.RequestBody{required = true, content = content, source_path = "#/components/requestBodies/Input"}}
	}
	document.paths["/items"] = methods

	issues: diagnostics.Manager
	testing.expect(t, validate_generation(&document, &issues, .typescript), "widened output should remain usable with a warning")
	if !testing.expect_value(t, len(issues.issues), 1) { return }
	testing.expect_value(t, issues.issues[0].code, "widened-additional-properties")
	testing.expect_value(t, issues.issues[0].path, "#/components/schemas/A~1B~0C/additionalProperties")
	issues = {}
	testing.expect(t, validate_generation(&document, &issues, .dart), "Dart does not emit TypeScript index-widening warnings")
	testing.expect_value(t, len(issues.issues), 0)
	testing.expect(t, !diagnostics.has_errors(&issues), "representation warnings should not fail generation")
}

@(test)
typescript_warns_about_unsafe_mixed_enum_integers :: proc(t: ^testing.T) {
	arena: virtual.Arena
	if !testing.expect(t, virtual.arena_init_growing(&arena) == nil, "arena should initialize") { return }
	defer virtual.arena_destroy(&arena)
	context.allocator = virtual.arena_allocator(&arena)

	values := []json.Value{json.Integer(9007199254740993), json.Float(0.5)}
	document := ir.Document{schemas = make(map[string]ir.Model)}
	document.schemas["Precise"] = ir.Enumeration{values = values, source_path = "#/components/schemas/Precise"}
	issues: diagnostics.Manager
	testing.expect(t, validate_generation(&document, &issues, .typescript), "precision loss should be visible without disabling TypeScript output")
	if !testing.expect_value(t, len(issues.issues), 1) { return }
	testing.expect_value(t, issues.issues[0].code, "enum-integer-precision-loss")
	testing.expect_value(t, issues.issues[0].path, "#/components/schemas/Precise/enum/0")

	// Exactly representable large integers do not need a precision warning.
	values[0] = json.Integer(9007199254740992)
	issues = {}
	testing.expect(t, validate_generation(&document, &issues, .typescript), "exact integers should remain supported")
	testing.expect_value(t, len(issues.issues), 0)
}

@(test)
typescript_compatible_named_fields_do_not_warn :: proc(t: ^testing.T) {
	arena: virtual.Arena
	if !testing.expect(t, virtual.arena_init_growing(&arena) == nil, "arena should initialize") { return }
	defer virtual.arena_destroy(&arena)
	context.allocator = virtual.arena_allocator(&arena)

	fields := make(map[string]ir.Field)
	fields["label"] = {model = ir.Primitive{type = .string}, required = true}
	additional: ir.Model = ir.Primitive{type = .string, nullable = true}
	object := ir.ObjectModel{fields = fields, additional_properties = &additional}
	testing.expect(t, !typescript_index_widens(object), "a required string fits an index accepting strings and null")
	fields["label"] = {model = ir.Enumeration{values = []json.Value{json.String("only")}}, required = true}
	testing.expect(t, !typescript_index_widens(object), "string enum literals fit a string index")
	fields["label"] = {model = ir.Primitive{type = .string}, required = false}
	testing.expect(t, typescript_index_widens(object), "an optional field adds undefined to a nullable string index")
}

@(test)
decimal_format_does_not_warn :: proc(t: ^testing.T) {
	arena: virtual.Arena
	if !testing.expect(t, virtual.arena_init_growing(&arena) == nil, "arena should initialize") { return }
	defer virtual.arena_destroy(&arena)
	context.allocator = virtual.arena_allocator(&arena)

	document := ir.Document{schemas = make(map[string]ir.Model)}
	document.schemas["Balance"] = ir.Primitive{type = .number, format = "decimal"}
	document.schemas["Amount"] = ir.Primitive{type = .number, format = "decimal"}
	for language in GenerationLanguage {
		issues: diagnostics.Manager
		testing.expect(t, validate_generation(&document, &issues, language), "decimal representation should remain available")
		testing.expect_value(t, len(issues.issues), 0)
	}
}
