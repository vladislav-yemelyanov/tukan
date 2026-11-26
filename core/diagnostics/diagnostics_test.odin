package diagnostics

import virtual "core:mem/virtual"
import "core:testing"

@(test)
collect_and_format_errors :: proc(t: ^testing.T) {
	arena: virtual.Arena
	err := virtual.arena_init_growing(&arena)
	if !testing.expect(t, err == nil, "test arena should initialize") { return }

	defer virtual.arena_destroy(&arena)
	context.allocator = virtual.arena_allocator(&arena)

	issues: Manager
	testing.expect(t, !has_errors(&issues), "new manager should have no errors")

	add(&issues, "Missing schema", "#/components/schemas/User")
	add(&issues, "Cannot write output")

	testing.expect(t, has_errors(&issues), "manager should report collected errors")
	testing.expect_value(t, len(issues.issues), 2)
	testing.expect_value(t, format(&issues), "1. error: Cannot write output\n\n2. error: Missing schema\n   #/components/schemas/User\n")
}

@(test)
format_warnings_with_paths :: proc(t: ^testing.T) {
	arena: virtual.Arena
	err := virtual.arena_init_growing(&arena)
	if !testing.expect(t, err == nil, "test arena should initialize") { return }

	defer virtual.arena_destroy(&arena)
	context.allocator = virtual.arena_allocator(&arena)

	issues: Manager
	path := child_path("#/components/schemas", "A/B~C")

	add(&issues, "Ignored keyword", "oneOf", path, .warning)

	testing.expect(t, !has_errors(&issues), "a warning should not fail generation")
	testing.expect_value(t, format(&issues), "1. warning: Ignored keyword\n   at #/components/schemas/A~1B~0C\n   oneOf\n")

	add(&issues, "Missing target", "Missing", path)

	testing.expect(t, has_errors(&issues), "an error should fail generation even when warnings precede it")
}

@(test)
diagnostics_are_deduplicated_and_formatted_in_stable_order :: proc(t: ^testing.T) {
	arena: virtual.Arena
	if !testing.expect(t, virtual.arena_init_growing(&arena) == nil, "arena should initialize") { return }
	defer virtual.arena_destroy(&arena)
	context.allocator = virtual.arena_allocator(&arena)

	first, second: Manager
	add(&first, "Loss of precision", "value", "#/b", .warning, "precision", "TypeScript")
	add(&first, "Missing items", "", "#/a", .error, "missing-items")
	add(&first, "Loss of precision", "value", "#/b", .warning, "precision", "TypeScript")
	add(&second, "Missing items", "", "#/a", .error, "missing-items")
	add(&second, "Loss of precision", "value", "#/b", .warning, "precision", "TypeScript")

	testing.expect_value(t, len(first.issues), 2)
	testing.expect_value(t, format(&first), format(&second))
	testing.expect_value(t, first.issues[0].path, "#/b")
}
