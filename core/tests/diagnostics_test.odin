package tests

import "core:fmt"
import virtual "core:mem/virtual"
import "core:os"
import "core:strings"
import "core:testing"

@(test)
cli_warns_about_partial_support_and_preserves_output_on_schema_errors :: proc(t: ^testing.T) {
	arena: virtual.Arena
	err := virtual.arena_init_growing(&arena)
	if !testing.expect(t, err == nil, "test arena should initialize") { return }
	defer virtual.arena_destroy(&arena)
	context.allocator = virtual.arena_allocator(&arena)

	work, ready := make_test_workspace(t)
	if !ready { return }
	defer os.remove_all(work.dir)

	dir := work.dir
	binary := work.binary

	input := fmt.aprintf("%s/input.json", dir)
	partial_source := `{"openapi":"3.0.3","components":{"schemas":{"Partial":{"oneOf":[{"type":"string"}]}}}}`
	if !testing.expect(t, os.write_entire_file(input, partial_source) == nil, "partial specification should be written") { return }

	args := [5]string{binary, "-l", "ts,dart", "-i", input}
	state, stdout, warning_output, run_err := os.process_exec({working_dir = dir, command = args[:]}, context.allocator)
	if !testing.expectf(t, run_err == nil && state.exit_code == 0, "warnings should allow generation: %s", string(warning_output)) { return }

	testing.expectf(t, strings.has_prefix(string(stdout), fmt.aprintf("Specification: input\n  Input: %s\n\nStatistics\n", input)), "source and statistics should have separate headings: %s", string(stdout))
	testing.expectf(t, strings.contains(string(stdout), "\n\nGenerated files (2)\n  "), "generated files should have a separate heading: %s", string(stdout))
	testing.expectf(t, strings.has_prefix(string(warning_output), fmt.aprintf("\nDiagnostics\n  Specification: %s\n\n1. warning:", input)), "diagnostics should have a heading and source context: %s", string(warning_output))
	testing.expect(t, strings.contains(string(warning_output), "warning: Unsupported schema keyword"), "CLI should print warnings")
	testing.expect(t, strings.contains(string(warning_output), "#/components/schemas/Partial/oneOf"), "warning should identify the ignored keyword")

	total_ms, measured := read_total_time_ms(string(stdout))
	testing.expectf(t, measured && total_ms > 0, "local runs should report elapsed time: %s", string(stdout))

	ts_path := fmt.aprintf("%s/tukan-output/input.ts", dir)
	dart_path := fmt.aprintf("%s/tukan-output/input.dart", dir)
	previous_ts, ts_err := os.read_entire_file(ts_path, context.allocator)
	previous_dart, dart_err := os.read_entire_file(dart_path, context.allocator)
	if !testing.expect(t, ts_err == nil && dart_err == nil, "warnings should still produce both files") { return }

	invalid_source := `{"openapi":"3.0.3","components":{"schemas":{"Broken":{"type":"array","items":{"nullable":"yes"}}}}}`
	if !testing.expect(t, os.write_entire_file(input, invalid_source) == nil, "invalid specification should be written") { return }

	failed_state, failed_stdout, error_output, failed_err := os.process_exec({working_dir = dir, command = args[:]}, context.allocator)

	testing.expect(t, failed_err == nil && failed_state.exit_code != 0, "invalid nested field should fail the CLI")
	testing.expectf(t, strings.contains(string(failed_stdout), "\n\nGenerated files (0)\n  None.\n\nTotal time: "), "failed parse should report no generated files before total time: %s", string(failed_stdout))
	testing.expect(t, strings.contains(string(error_output), "#/components/schemas/Broken/items/nullable"), "error should identify the invalid nested field")

	current_ts, current_ts_err := os.read_entire_file(ts_path, context.allocator)
	current_dart, current_dart_err := os.read_entire_file(dart_path, context.allocator)
	if !testing.expect(t, current_ts_err == nil && current_dart_err == nil, "previous output should remain readable") { return }

	testing.expect_value(t, string(current_ts), string(previous_ts))
	testing.expect_value(t, string(current_dart), string(previous_dart))
}

@(test)
cli_preserves_failed_language_outputs_and_reports_generator_context :: proc(t: ^testing.T) {
	arena: virtual.Arena
	if !testing.expect(t, virtual.arena_init_growing(&arena) == nil, "arena should initialize") { return }
	defer virtual.arena_destroy(&arena)
	context.allocator = virtual.arena_allocator(&arena)

	work, ready := make_test_workspace(t)
	if !ready { return }
	defer os.remove_all(work.dir)
	input := fmt.aprintf("%s/cycle.json", work.dir)
	source := `{"openapi":"3.0.3","components":{"schemas":{"A":{"$ref":"#/components/schemas/B"},"B":{"$ref":"#/components/schemas/A"}}}}`
	if !testing.expect(t, os.write_entire_file(input, source) == nil, "cycle input should exist") { return }
	output := fmt.aprintf("%s/output", work.dir)
	if !testing.expect(t, os.make_directory(output) == nil, "output directory should exist") { return }
	for extension in ([2]string{"ts", "dart"}) {
		if !testing.expect(t, os.write_entire_file(fmt.aprintf("%s/cycle.%s", output, extension), "previous output") == nil, "previous output should exist") { return }
	}

	state, stdout, stderr, err := run_cli(work, {"-l", "ts,dart", "-i", input, "-o", output})
	testing.expect(t, err == nil && state.exit_code == 1, "unsupported languages should fail the run")
	testing.expectf(t, strings.contains(string(stderr), "code: unsupported-alias-cycle"), "missing generator rule: %s", string(stderr))
	testing.expectf(t, strings.contains(string(stderr), "language: TypeScript") && strings.contains(string(stderr), "language: Dart"), "diagnostics must identify both failed languages: %s", string(stderr))
	testing.expectf(t, strings.contains(string(stderr), "#/components/schemas/A"), "cycle diagnostic must identify its schema: %s", string(stderr))
	testing.expect(t, !strings.contains(string(stderr), "Failed to write"), "semantic failures must not be reported as file errors")
	for extension in ([2]string{"ts", "dart"}) {
		previous, read_err := os.read_entire_file(fmt.aprintf("%s/cycle.%s", output, extension), context.allocator)
		if testing.expect(t, read_err == nil, "previous output should remain readable") { testing.expect_value(t, string(previous), "previous output") }
	}
	testing.expectf(t, strings.contains(string(stdout), "Generated files (0)"), "report must count only successful output: %s", string(stdout))

	array_cycle := fmt.aprintf("%s/array-cycle.json", work.dir)
	array_source := `{"openapi":"3.0.3","components":{"schemas":{"Node":{"type":"array","items":{"$ref":"#/components/schemas/Node"}}}}}`
	if !testing.expect(t, os.write_entire_file(array_cycle, array_source) == nil, "array cycle input should exist") { return }
	for extension in ([2]string{"ts", "dart"}) {
		if !testing.expect(t, os.write_entire_file(fmt.aprintf("%s/array-cycle.%s", output, extension), "previous output") == nil, "previous output should exist") { return }
	}
	array_state, array_stdout, array_stderr, array_err := run_cli(work, {"-l", "ts,dart", "-i", array_cycle, "-o", output})
	testing.expect(t, array_err == nil && array_state.exit_code == 1, "Dart recursive array alias should fail the run")
	testing.expectf(t, strings.contains(string(array_stderr), "code: unsupported-alias-cycle"), "missing generator rule: %s", string(array_stderr))
	testing.expectf(t, strings.contains(string(array_stderr), "language: Dart") && !strings.contains(string(array_stderr), "language: TypeScript"), "only Dart should fail on a recursive array alias: %s", string(array_stderr))
	previous_dart, dart_read_err := os.read_entire_file(fmt.aprintf("%s/array-cycle.dart", output), context.allocator)
	if testing.expect(t, dart_read_err == nil, "previous Dart output should remain readable") { testing.expect_value(t, string(previous_dart), "previous output") }
	generated_ts, ts_read_err := os.read_entire_file(fmt.aprintf("%s/array-cycle.ts", output), context.allocator)
	if testing.expect(t, ts_read_err == nil, "supported TypeScript output should still be generated") {
		testing.expect(t, strings.contains(string(generated_ts), `"Node":`), "TypeScript output should contain the recursive array schema")
	}
	testing.expectf(t, strings.contains(string(array_stdout), "Generated files (1)"), "report must count only successful output: %s", string(array_stdout))
}

@(test)
cli_preserves_all_outputs_when_new_parser_checks_fail :: proc(t: ^testing.T) {
	arena: virtual.Arena
	if !testing.expect(t, virtual.arena_init_growing(&arena) == nil, "arena should initialize") { return }
	defer virtual.arena_destroy(&arena)
	context.allocator = virtual.arena_allocator(&arena)

	work, ready := make_test_workspace(t)
	if !ready { return }
	defer os.remove_all(work.dir)
	input := fmt.aprintf("%s/invalid.json", work.dir)
	output := fmt.aprintf("%s/output", work.dir)
	if !testing.expect(t, os.make_directory(output) == nil, "output directory should exist") { return }
	for extension in ([2]string{"ts", "dart"}) {
		if !testing.expect(t, os.write_entire_file(fmt.aprintf("%s/invalid.%s", output, extension), "previous output") == nil, "previous output should exist") { return }
	}
	cases := [?]struct { source, code: string }{
		{`{}`, "missing-openapi-version"},
		{`{"openapi":"3.0.3","components":{"schemas":{"Value":{"type":"array"}}}}`, "missing-array-items"},
		{`{"openapi":"3.0.3","components":{"schemas":{"Value":{"type":"integer","enum":["wrong"]}}}}`, "enum-type-mismatch"},
	}
	for scenario in cases {
		if !testing.expect(t, os.write_entire_file(input, scenario.source) == nil, "invalid input should exist") { return }
		state, stdout, stderr, err := run_cli(work, {"-l", "ts,dart", "-i", input, "-o", output})
		testing.expectf(t, err == nil && state.exit_code == 1, "%s should fail the CLI", scenario.code)
		testing.expectf(t, strings.contains(string(stderr), scenario.code), "expected %s diagnostic: %s", scenario.code, string(stderr))
		testing.expectf(t, strings.contains(string(stdout), "Generated files (0)"), "invalid input should not generate files: %s", string(stdout))
		for extension in ([2]string{"ts", "dart"}) {
			previous, read_err := os.read_entire_file(fmt.aprintf("%s/invalid.%s", output, extension), context.allocator)
			if testing.expect(t, read_err == nil, "previous output should remain readable") { testing.expect_value(t, string(previous), "previous output") }
		}
	}
}

@(test)
cli_reports_only_model_files_and_preserves_them_on_parse_errors :: proc(t: ^testing.T) {
	arena: virtual.Arena
	if !testing.expect(t, virtual.arena_init_growing(&arena) == nil, "arena should initialize") { return }
	defer virtual.arena_destroy(&arena)
	context.allocator = virtual.arena_allocator(&arena)
	work, ready := make_test_workspace(t)
	if !ready { return }
	defer os.remove_all(work.dir)
	fixture, read_err := os.read_entire_file(fmt.aprintf("%s/core/tests/fixtures/specs/valid-annotations.json", work.root), context.allocator)
	if !testing.expect(t, read_err == nil, "annotated fixture should be readable") { return }
	input := fmt.aprintf("%s/input.json", work.dir)
	output := fmt.aprintf("%s/output", work.dir)
	if !testing.expect(t, os.write_entire_file(input, fixture) == nil, "input should exist") { return }
	state, stdout, stderr, err := run_cli(work, {"-l", "ts,dart", "-i", input, "-o", output})
	if !testing.expectf(t, err == nil && state.exit_code == 0, "documented generation should succeed: %s", string(stderr)) { return }
	testing.expect(t, strings.contains(string(stdout), "Generated files (2)"), "report should include one model file per language")
	model_path := fmt.aprintf("%s/input.dart", output)
	testing.expect(t, !os.exists(fmt.aprintf("%s/input.metadata.dart", output)), "documentation must not create companion files")
	previous, model_err := os.read_entire_file(model_path, context.allocator)
	if !testing.expect(t, model_err == nil, "model output should exist") { return }
	testing.expect(t, strings.contains(string(previous), "minLength: 3"), "constraints should be documented beside fields")
	if !testing.expect(t, os.write_entire_file(input, `{"openapi":"3.0.3","components":{"schemas":{"Broken":{"type":"array"}}}}`) == nil, "invalid replacement should exist") { return }
	failed, _, _, failed_err := run_cli(work, {"-l", "ts,dart", "-i", input, "-o", output})
	testing.expect(t, failed_err == nil && failed.exit_code != 0, "invalid input must fail")
	retained, retained_err := os.read_entire_file(model_path, context.allocator)
	if testing.expect(t, retained_err == nil, "previous model should remain readable") {
		testing.expect_value(t, string(retained), string(previous))
	}
}
