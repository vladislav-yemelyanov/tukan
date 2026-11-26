package generators

import "core:encoding/json"
import virtual "core:mem/virtual"
import "core:testing"
import ir "../ir"

@(test)
readable_names_preserve_schemas_and_disambiguate_nested_types :: proc(t: ^testing.T) {
	arena: virtual.Arena
	if !testing.expect(t, virtual.arena_init_growing(&arena) == nil, "test arena should initialize") { return }
	defer virtual.arena_destroy(&arena)
	context.allocator = virtual.arena_allocator(&arena)

	values := [2]json.Value{json.String("open"), json.String("closed")}
	status: ir.Model = ir.Enumeration{values = values[:]}
	fields := make(map[string]ir.Field)
	fields["status"] = {model = status}
	fields["expand"] = {model = ir.ArrayModel{items = &status}}
	fields["a-b"] = {model = status}
	fields["a/b"] = {model = status}
	fields["aB"] = {model = ir.Primitive{type = .string}}
	fields["generated_Value"] = {model = ir.Primitive{type = .string}}
	fields["generatedValue"] = {model = ir.Primitive{type = .string}}
	fields["toJson"] = {model = ir.Primitive{type = .string}}
	fields["to-json"] = {model = ir.Primitive{type = .string}}
	fields["copyWith"] = {model = ir.Primitive{type = .string}}
	fields["identical"] = {model = ir.Primitive{type = .string}}
	schemas := make(map[string]ir.Model)
	schemas["Order"] = ir.ObjectModel{fields = fields}
	schemas["OrderStatus"] = ir.Primitive{type = .string}
	schemas["OrderStatus2"] = ir.Primitive{type = .string}
	schemas["AB"] = ir.Primitive{type = .string}
	schemas["a-b"] = ir.Primitive{type = .string}
	schemas["a/b"] = ir.Reference{name = "a-b"}
	schemas["OptionalValue"] = ir.Primitive{type = .string}
	schemas["OptionalValue2"] = ir.Primitive{type = .string}
	schemas["List"] = ir.Primitive{type = .string}
	schemas["List2"] = ir.Primitive{type = .string}

	root := child_path("schema", "Order")
	field_path := child_path(root, "fields")
	names := build_generator_names(schemas)
	testing.expect_value(t, names.types[child_path("schema", "AB")], "AB")
	testing.expect_value(t, names.types[child_path("schema", "a-b")], "AB2")
	testing.expect_value(t, names.types[child_path("schema", "a/b")], "AB3")
	testing.expect_value(t, names.types[child_path("schema", "OptionalValue")], "OptionalValue")
	testing.expect_value(t, names.types[child_path("schema", "OptionalValue2")], "OptionalValue2")
	testing.expect_value(t, names.types[child_path("schema", "List2")], "List2")
	testing.expect_value(t, names.types[child_path("schema", "List")], "List3")
	testing.expect_value(t, names.types[child_path(field_path, "status")], "OrderStatus3")
	testing.expect_value(t, names.types[child_path(child_path(field_path, "expand"), "items")], "OrderExpandItem")
	testing.expect_value(t, names.fields[child_path(field_path, "aB")], "aB")
	testing.expect_value(t, names.fields[child_path(field_path, "a-b")], "aB2")
	testing.expect_value(t, names.fields[child_path(field_path, "a/b")], "aB3")
	testing.expect_value(t, names.fields[child_path(field_path, "generated_Value")], "generated_Value")
	testing.expect_value(t, names.fields[child_path(field_path, "generatedValue")], "generatedValue")
	testing.expect_value(t, names.fields[child_path(field_path, "to-json")], "toJson2")
	testing.expect_value(t, names.fields[child_path(field_path, "toJson")], "toJson3")
	testing.expect_value(t, names.fields[child_path(field_path, "copyWith")], "copyWith2")
	testing.expect_value(t, names.fields[child_path(field_path, "identical")], "identical2")

	repeated := build_generator_names(schemas)
	for path, name in names.types { testing.expect_value(t, repeated.types[path], name) }
	for path, name in names.fields { testing.expect_value(t, repeated.fields[path], name) }
	testing.expect_value(t, len(schemas), 10)
	testing.expect_value(t, len(fields), 11)
}

@(test)
nullable_backing_types_avoid_member_collisions :: proc(t: ^testing.T) {
	arena: virtual.Arena
	if !testing.expect(t, virtual.arena_init_growing(&arena) == nil, "test arena should initialize") { return }
	defer virtual.arena_destroy(&arena)
	context.allocator = virtual.arena_allocator(&arena)

	fields := make(map[string]ir.Field)
	fields["MaybeValue2"] = {model = ir.Primitive{type = .string}}
	schemas := make(map[string]ir.Model)
	schemas["Maybe"] = ir.ObjectModel{fields = fields, nullable = true}
	schemas["MaybeValue"] = ir.Primitive{type = .string}
	root := child_path("schema", "Maybe")

	dart := build_generator_names(schemas)
	testing.expect_value(t, dart.types[child_path(root, "nullable")], "MaybeValue2")
	testing.expect_value(t, dart.fields[child_path(child_path(root, "fields"), "MaybeValue2")], "maybeValue2")
}
