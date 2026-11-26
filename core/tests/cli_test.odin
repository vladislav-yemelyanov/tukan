package tests

import "core:fmt"
import virtual "core:mem/virtual"
import "core:os"
import "core:strings"
import "core:testing"

@(test)
cli_reports_build_version :: proc(t: ^testing.T) {
	arena: virtual.Arena
	if err := virtual.arena_init_growing(&arena); err != nil {
		testing.expectf(t, false, "test arena should initialize: %v", err)
		return
	}
	defer virtual.arena_destroy(&arena)
	context.allocator = virtual.arena_allocator(&arena)

	work, ready := make_test_workspace(t)
	if !ready { return }
	defer os.remove_all(work.dir)

	for flag in ([2]string{"-v", "--version"}) {
		state, stdout, stderr, run_err := run_cli(work, {flag})
		testing.expectf(t, run_err == nil && state.exit_code == 0, "%s: version should succeed without a project configuration", flag)
		testing.expect_value(t, string(stderr), "")
		lines := strings.split(strings.trim_space(string(stdout)), "\n")
		testing.expect_value(t, len(lines), 1)
		testing.expect(t, strings.has_prefix(string(stdout), "Tukan "), "version should identify the executable")
		testing.expect(t, len(strings.trim_space(string(stdout))) > len("Tukan "), "version must include a build number")
	}
	testing.expect(t, !os.exists(fmt.aprintf("%s/tukan-output", work.dir)), "version must not generate files")
}

@(test)
cli_selects_output_languages :: proc(t: ^testing.T) {
	arena: virtual.Arena
	err := virtual.arena_init_growing(&arena)
	if !testing.expect(t, err == nil, "test arena should initialize") { return }
	defer virtual.arena_destroy(&arena)
	context.allocator = virtual.arena_allocator(&arena)

	work, ready := make_test_workspace(t)
	if !ready { return }
	defer os.remove_all(work.dir)

	input := fmt.aprintf("%s/core/tests/fixtures/specs/valid-schemas.json", work.root)
	result_dir := fmt.aprintf("%s/tukan-output", work.dir)
	if !testing.expect(t, os.make_directory(result_dir) == nil, "output directory should be created") { return }

	ts_path := fmt.aprintf("%s/valid-schemas.ts", result_dir)
	dart_path := fmt.aprintf("%s/valid-schemas.dart", result_dir)

	cases := [4]struct { language: string, typescript: bool, dart: bool }{
		{"ts", true, false},
		{"dart", false, true},
		{"ts,dart", true, true},
		{"typescript", true, false},
	}

	for scenario in cases {
		if !testing.expect(t, os.write_entire_file(ts_path, "previous TypeScript") == nil, "TypeScript sentinel should be written") { return }
		if !testing.expect(t, os.write_entire_file(dart_path, "previous Dart") == nil, "Dart sentinel should be written") { return }

		state, _, stderr, run_err := run_cli(work, {"--lang", scenario.language, "--input", input})
		if !testing.expectf(t, run_err == nil && state.exit_code == 0, "%s: generation failed: %s", scenario.language, string(stderr)) { continue }

		ts, ts_err := os.read_entire_file(ts_path, context.allocator)
		dart, dart_err := os.read_entire_file(dart_path, context.allocator)
		if !testing.expect(t, ts_err == nil && dart_err == nil, "output should remain readable") { continue }

		testing.expectf(t, (string(ts) != "previous TypeScript") == scenario.typescript, "%s: incorrect TypeScript selection", scenario.language)
		testing.expectf(t, (string(dart) != "previous Dart") == scenario.dart, "%s: incorrect Dart selection", scenario.language)
	}
}

@(test)
cli_names_output_after_each_input :: proc(t: ^testing.T) {
	arena: virtual.Arena
	err := virtual.arena_init_growing(&arena)
	if !testing.expect(t, err == nil, "test arena should initialize") { return }
	defer virtual.arena_destroy(&arena)
	context.allocator = virtual.arena_allocator(&arena)

	work, ready := make_test_workspace(t)
	if !ready { return }
	defer os.remove_all(work.dir)

	source, read_err := os.read_entire_file(fmt.aprintf("%s/core/tests/fixtures/specs/valid-schemas.json", work.root), context.allocator)
	if !testing.expect(t, read_err == nil, "example should be readable") { return }

	for name in ([2]string{"orders", "orders.v2"}) {
		input := fmt.aprintf("%s/%s.json", work.dir, name)
		if !testing.expect(t, os.write_entire_file(input, source) == nil, "named input should be written") { return }

		state, _, stderr, run_err := run_cli(work, {"-l", "ts,dart", "-i", input})
		if !testing.expectf(t, run_err == nil && state.exit_code == 0, "%s: generation should succeed: %s", name, string(stderr)) { return }
	}

	// A second input must create its own files without replacing the first input's output.
	for name in ([2]string{"orders", "orders.v2"}) {
		for suffix in ([2]string{"ts", "dart"}) {
			path := fmt.aprintf("%s/tukan-output/%s.%s", work.dir, name, suffix)
			output, output_err := os.read_entire_file(path, context.allocator)
			testing.expectf(t, output_err == nil && len(output) > 0, "%s should retain generated types", path)
		}
	}

	testing.expect(t, !os.exists(fmt.aprintf("%s/tukan-output/spec.ts", work.dir)), "named input should not create a generic spec.ts")
	testing.expect(t, !os.exists(fmt.aprintf("%s/tukan-output/spec.dart", work.dir)), "named input should not create a generic spec.dart")
}

@(test)
cli_rejects_invalid_arguments :: proc(t: ^testing.T) {
	arena: virtual.Arena
	err := virtual.arena_init_growing(&arena)
	if !testing.expect(t, err == nil, "test arena should initialize") { return }
	defer virtual.arena_destroy(&arena)
	context.allocator = virtual.arena_allocator(&arena)

	work, ready := make_test_workspace(t)
	if !ready { return }
	defer os.remove_all(work.dir)

	cases := [?]struct { name: string, arguments: []string, expected_error: string }{
		{"missing config", {"--config"}, "Missing configuration file"},
		{"missing input list", {"--input-list"}, "Missing input list file"},
		{"missing concurrency", {"--concurrency"}, "Missing concurrency value"},
		{"invalid concurrency", {"--concurrency", "0"}, "Concurrency must be an integer"},
		{"fractional concurrency", {"--concurrency", "2.5"}, "Concurrency must be an integer"},
		{"excessive concurrency", {"--concurrency", "65"}, "Concurrency must be an integer"},
		{"mixed input modes", {"--config", "tukan.json5", "-i", "a.json"}, "Configuration cannot be combined"},
		{"multiple direct modes", {"--input-list", "a.txt", "-i", "a.json"}, "Choose either"},
		{"repeated config", {"--config", "a", "-c", "b"}, "Option can only be specified once"},
		{"no arguments", {}, "Run tukan init"},
		{"input without language", {"-i", "missing.json"}, "Missing required language option"},
		{"output without language", {"--output", "generated"}, "Missing required language option"},
		{"unsupported language", {"-l", "python"}, "Unsupported output language"},
		{"removed cs language", {"-l", "cs"}, "Unsupported output language"},
		{"removed kt language", {"-l", "kt"}, "Unsupported output language"},
		{"empty language", {"-l", ""}, "Unsupported output language"},
		{"trailing separator", {"-l", "ts,"}, "Unsupported output language"},
		{"missing language", {"-l"}, "Missing language list"},
		{"missing input", {"-i"}, "Missing input file or URL"},
		{"missing output", {"-o"}, "Missing output directory"},
		{"positional input", {"spec.json"}, "Unexpected argument"},
		{"duplicate input", {"-i", "a", "-i", "b"}, "Input can only be specified once"},
		{"duplicate language", {"-l", "ts", "-l", "dart"}, "Language option can only be specified once"},
		{"duplicate output", {"-o", "a", "-o", "b"}, "Output directory can only be specified once"},
		{"unknown option", {"--unknown"}, "Unknown option"},
		{"option instead of input", {"-i", "-l", "ts"}, "Missing input file or URL"},
	}

	for scenario in cases {
		state, _, stderr, run_err := run_cli(work, scenario.arguments)

		testing.expectf(t, run_err == nil && state.exit_code != 0, "%s: invalid arguments should fail", scenario.name)
		testing.expectf(t, strings.contains(string(stderr), scenario.expected_error), "%s: expected %s, got %s", scenario.name, scenario.expected_error, string(stderr))
	}

	testing.expect(t, !os.exists(fmt.aprintf("%s/tukan-output", work.dir)), "invalid arguments should not create output")
}

@(test)
cli_describes_options_in_help :: proc(t: ^testing.T) {
	arena: virtual.Arena
	err := virtual.arena_init_growing(&arena)
	if !testing.expect(t, err == nil, "test arena should initialize") { return }
	defer virtual.arena_destroy(&arena)
	context.allocator = virtual.arena_allocator(&arena)

	work, ready := make_test_workspace(t)
	if !ready { return }
	defer os.remove_all(work.dir)

	for flag in ([2]string{"-h", "--help"}) {
		state, stdout, stderr, run_err := run_cli(work, {flag})

		testing.expectf(t, run_err == nil && state.exit_code == 0, "%s: help should succeed", flag)
		testing.expect_value(t, string(stderr), "")
		testing.expect(t, strings.contains(string(stdout), "tukan -l languages"), "usage should show language as required")
		testing.expect(t, strings.contains(string(stdout), "Required output languages"), "help should explain that language selection is required")

		for option in ([3]string{"-i, --input", "-l, --lang", "-o, --output"}) {
			testing.expectf(t, strings.contains(string(stdout), option), "help should describe %s", option)
		}
	}
}

@(test)
cli_creates_requested_output_directories :: proc(t: ^testing.T) {
	arena: virtual.Arena
	err := virtual.arena_init_growing(&arena)
	if !testing.expect(t, err == nil, "test arena should initialize") { return }
	defer virtual.arena_destroy(&arena)
	context.allocator = virtual.arena_allocator(&arena)

	work, ready := make_test_workspace(t)
	if !ready { return }
	defer os.remove_all(work.dir)

	input := fmt.aprintf("%s/core/tests/fixtures/specs/valid-schemas.json", work.root)
	for output in ([2]string{"generated/client", fmt.aprintf("%s/absolute-output", work.dir)}) {
		state, _, stderr, run_err := run_cli(work, {"-i", input, "-l", "ts", "--output", output})
		if !testing.expectf(t, run_err == nil && state.exit_code == 0, "%s: generation should succeed: %s", output, string(stderr)) { continue }

		directory := output
		if !strings.has_prefix(output, "/") { directory = fmt.aprintf("%s/%s", work.dir, output) }

		testing.expectf(t, os.exists(fmt.aprintf("%s/valid-schemas.ts", directory)), "%s: TypeScript should exist", output)
		testing.expectf(t, !os.exists(fmt.aprintf("%s/valid-schemas.dart", directory)), "%s: unselected Dart should not exist", output)
	}

	testing.expect(t, !os.exists(fmt.aprintf("%s/tukan-output", work.dir)), "custom output should not create the default directory")
}

@(test)
cli_rejects_output_path_that_is_a_file :: proc(t: ^testing.T) {
	arena: virtual.Arena
	err := virtual.arena_init_growing(&arena)
	if !testing.expect(t, err == nil, "test arena should initialize") { return }
	defer virtual.arena_destroy(&arena)
	context.allocator = virtual.arena_allocator(&arena)

	work, ready := make_test_workspace(t)
	if !ready { return }
	defer os.remove_all(work.dir)

	input := fmt.aprintf("%s/core/tests/fixtures/specs/valid-schemas.json", work.root)
	blocked := fmt.aprintf("%s/not-a-directory", work.dir)
	if !testing.expect(t, os.write_entire_file(blocked, "keep") == nil, "blocking file should be written") { return }

	for output in ([2]string{blocked, fmt.aprintf("%s/child", blocked)}) {
		state, stdout, stderr, run_err := run_cli(work, {"-l", "ts", "-i", input, "-o", output})
		testing.expectf(t, run_err == nil && state.exit_code != 0, "%s: output path blocked by a file should fail", output)
		testing.expect(t, strings.contains(string(stderr), "Failed to create output directory"), "output failure should be explained")
		testing.expectf(t, strings.contains(string(stdout), "Generated files (0)\n  None."), "failed writes should not appear as generated files: %s", string(stdout))
	}

	content, read_err := os.read_entire_file(blocked, context.allocator)
	if testing.expect(t, read_err == nil, "blocking file should remain readable") {
		testing.expect_value(t, string(content), "keep")
	}
}

@(test)
cli_reads_specification_from_default_path :: proc(t: ^testing.T) {
	arena: virtual.Arena
	err := virtual.arena_init_growing(&arena)
	if !testing.expect(t, err == nil, "test arena should initialize") { return }
	defer virtual.arena_destroy(&arena)
	context.allocator = virtual.arena_allocator(&arena)

	work, ready := make_test_workspace(t)
	if !ready { return }
	defer os.remove_all(work.dir)

	source, read_err := os.read_entire_file(fmt.aprintf("%s/core/tests/fixtures/specs/valid-schemas.json", work.root), context.allocator)
	if !testing.expect(t, read_err == nil, "example should be readable") { return }
	if !testing.expect(t, os.write_entire_file(fmt.aprintf("%s/spec.json", work.dir), source) == nil, "default input should be written") { return }

	state, _, stderr, run_err := run_cli(work, {"-l", "ts"})

	testing.expectf(t, run_err == nil && state.exit_code == 0, "default input should work: %s", string(stderr))
	testing.expect(t, os.exists(fmt.aprintf("%s/tukan-output/spec.ts", work.dir)), "default input should generate TypeScript")
}

@(test)
cli_reports_missing_input_files :: proc(t: ^testing.T) {
	arena: virtual.Arena
	err := virtual.arena_init_growing(&arena)
	if !testing.expect(t, err == nil, "test arena should initialize") { return }
	defer virtual.arena_destroy(&arena)
	context.allocator = virtual.arena_allocator(&arena)

	work, ready := make_test_workspace(t)
	if !ready { return }
	defer os.remove_all(work.dir)

	state, _, stderr, run_err := run_cli(work, {"-l", "ts", "-i", "missing.json"})

	testing.expect(t, run_err == nil && state.exit_code != 0, "missing input should fail")
	testing.expect(t, strings.contains(string(stderr), "Failed to read specification"), "missing file should be explained")
	testing.expect(t, !os.exists(fmt.aprintf("%s/tukan-output", work.dir)), "missing input should not create output")
}
