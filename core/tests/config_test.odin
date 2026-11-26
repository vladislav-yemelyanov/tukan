package tests

import "core:fmt"
import virtual "core:mem/virtual"
import "core:os"
import "core:strings"
import "core:sync"
import "core:testing"
import "core:thread"

@(test)
config_init_creates_editable_project_config_without_overwriting :: proc(t: ^testing.T) {
	arena: virtual.Arena
	err := virtual.arena_init_growing(&arena)
	if !testing.expect(t, err == nil, "test arena should initialize") { return }
	defer virtual.arena_destroy(&arena)
	context.allocator = virtual.arena_allocator(&arena)

	work, ready := make_test_workspace(t)
	if !ready { return }
	defer os.remove_all(work.dir)

	state, _, stderr, run_err := run_cli(work, {"init"})
	if !testing.expectf(t, run_err == nil && state.exit_code == 0, "init should succeed: %s", string(stderr)) { return }
	path := fmt.aprintf("%s/tukan.json5", work.dir)
	original, read_err := os.read_entire_file(path, context.allocator)
	if !testing.expect(t, read_err == nil, "init should create tukan.json5") { return }

	again, _, again_stderr, again_err := run_cli(work, {"init"})
	testing.expectf(t, again_err == nil && again.exit_code != 0, "init must refuse replacement: %s", string(again_stderr))
	unchanged, unchanged_err := os.read_entire_file(path, context.allocator)
	if testing.expect(t, unchanged_err == nil, "configuration should remain readable") {
		testing.expect_value(t, string(unchanged), string(original))
	}

	body, body_err := os.read_entire_file(fmt.aprintf("%s/core/tests/fixtures/specs/valid-schemas.json", work.root), context.allocator)
	if !testing.expect(t, body_err == nil, "example should be readable") { return }
	if !testing.expect(t, os.write_entire_file(fmt.aprintf("%s/openapi.json", work.dir), body) == nil, "project input should be written") { return }

	generated, _, generated_stderr, generated_err := run_cli(work, {})
	testing.expectf(t, generated_err == nil && generated.exit_code == 0, "plain tukan should use the generated JSON5 config: %s", string(generated_stderr))
	testing.expect(t, os.exists(fmt.aprintf("%s/src/generated/api.ts", work.dir)), "template should generate its named TypeScript output")
	testing.expect(t, !os.exists(fmt.aprintf("%s/tukan-output", work.dir)), "project workflow should use its configured output")
}

@(test)
config_resolves_paths_and_replaces_settings_consistently_across_workers :: proc(t: ^testing.T) {
	arena: virtual.Arena
	err := virtual.arena_init_growing(&arena)
	if !testing.expect(t, err == nil, "test arena should initialize") { return }
	defer virtual.arena_destroy(&arena)
	context.allocator = virtual.arena_allocator(&arena)

	work, ready := make_test_workspace(t)
	if !ready { return }
	defer os.remove_all(work.dir)

	directory := fmt.aprintf("%s/project", work.dir)
	if !testing.expect(t, os.make_directory(directory) == nil, "configuration directory should be created") { return }
	body, read_err := os.read_entire_file(fmt.aprintf("%s/core/tests/fixtures/specs/valid-operations.json", work.root), context.allocator)
	if !testing.expect(t, read_err == nil, "operation example should be readable") { return }
	if !testing.expect(t, os.write_entire_file(fmt.aprintf("%s/source.json", directory), body) == nil, "relative input should be written") { return }
	config := `{
		// Comments, unquoted keys, and trailing commas are valid JSON5.
		defaults: { languages: ["ts", "dart"], output: "./generated", },
		specs: [
			{name: "api", input: "./source.json"},
			{name: "catalog", input: "./source.json", languages: ["dart"], output: "./mobile"},
		],
	}`
	path := fmt.aprintf("%s/tukan.json5", directory)
	if !testing.expect(t, os.write_entire_file(path, config) == nil, "configuration should be written") { return }

	state, _, stderr, run_err := run_cli(work, {"--config", path})
	if !testing.expectf(t, run_err == nil && state.exit_code == 0, "configuration should run from another working directory: %s", string(stderr)) { return }
	for file in ([3]string{"generated/api.ts", "generated/api.dart", "mobile/catalog.dart"}) {
		testing.expectf(t, os.exists(fmt.aprintf("%s/%s", directory, file)), "config-relative output should exist: %s", file)
	}
	testing.expect(t, !os.exists(fmt.aprintf("%s/mobile/catalog.ts", directory)), "per-spec language list should replace defaults")
	testing.expect(t, !os.exists(fmt.aprintf("%s/generated", work.dir)), "config paths should not use the process directory")

	for workers in ([2]string{"1", "4"}) {
		output := fmt.aprintf("workers-%s", workers)
		state, _, stderr, run_err := run_cli(work, {"-c", path, "-j", workers, "-l", "ts,dart", "-o", output})
		if !testing.expectf(t, run_err == nil && state.exit_code == 0, "%s workers should generate all overrides: %s", workers, string(stderr)) { return }
	}
	for name in ([2]string{"api", "catalog"}) {
		for extension in ([2]string{"ts", "dart"}) {
			serial, serial_err := os.read_entire_file(fmt.aprintf("%s/workers-1/%s.%s", work.dir, name, extension), context.allocator)
			parallel, parallel_err := os.read_entire_file(fmt.aprintf("%s/workers-4/%s.%s", work.dir, name, extension), context.allocator)
			if testing.expectf(t, serial_err == nil && parallel_err == nil, "%s.%s should exist for both worker counts", name, extension) {
				testing.expectf(t, string(serial) == string(parallel), "%s.%s should be identical under parallel generation", name, extension)
			}
		}
	}

}

@(test)
config_rejects_invalid_settings_before_processing_any_specification :: proc(t: ^testing.T) {
	arena: virtual.Arena
	err := virtual.arena_init_growing(&arena)
	if !testing.expect(t, err == nil, "test arena should initialize") { return }
	defer virtual.arena_destroy(&arena)
	context.allocator = virtual.arena_allocator(&arena)

	work, ready := make_test_workspace(t)
	if !ready { return }
	defer os.remove_all(work.dir)

	cases := [?]struct { config: string, expected: string }{
		{`{`, "Failed to parse configuration JSON5"},
		{`[]`, "Configuration must be an object"},
		{`{specs: []}`, "non-empty specs array"},
		{`{specs: [{input: "missing.json"}], concurency: 3}`, "#/concurency"},
		{`{specs: [{input: "missing.json"}], concurrency: 1.5}`, "#/concurrency"},
		{`{specs: [{input: "missing.json"}], concurrency: 0}`, "#/concurrency"},
		{`{specs: [{input: "missing.json"}], concurrency: 65}`, "#/concurrency"},
		{`{specs: [{input: "missing.json"}], defaults: null}`, "#/defaults"},
		{`{specs: [{input: "missing.json"}], defaults: {input: "bad"}}`, "#/defaults/input"},
		{`{specs: [{input: "missing.json", langauges: ["ts"]}]}`, "#/specs/0/langauges"},
		{`{specs: [{name: "api"}]}`, "#/specs/0/input"},
		{`{specs: [{input: "missing.json", languages: []}]}`, "#/specs/0/languages"},
		{`{specs: [{input: "missing.json", languages: [null]}]}`, "#/specs/0/languages/0"},
		{`{specs: [{input: "missing.json", languages: ["python"]}]}`, "Unsupported output language"},
		{`{specs: [{input: "missing.json", output: ""}]}`, "#/specs/0/output"},
		{`{specs: [{input: "missing.json", name: "../escape"}]}`, "Specification name must be a file name"},
		{`{specs: [null]}`, "#/specs/0"},
		{`{specs: [{input: "a.json", name: "api"}, {input: "b.json", name: "api", output: "./src/generated/../generated"}]}`, "Conflicting output path"},
		{`{specs: [{input: "missing.json", outputs: []}]}`, "#/specs/0/outputs"},
		{`{specs: [{input: "missing.json", outputs: "bad"}]}`, "#/specs/0/outputs"},
		{`{specs: [{input: "missing.json", outputs: [null]}]}`, "#/specs/0/outputs/0"},
		{`{specs: [{input: "missing.json", outputs: [{language: "ts", path: "./a", extra: 1}]}]}`, "#/specs/0/outputs/0/extra"},
		{`{specs: [{input: "missing.json", outputs: [{path: "./a"}]}]}`, "#/specs/0/outputs/0/language"},
		{`{specs: [{input: "missing.json", outputs: [{language: "python", path: "./a"}]}]}`, "#/specs/0/outputs/0/language"},
		{`{specs: [{input: "missing.json", outputs: [{language: "ts", path: ""}]}]}`, "#/specs/0/outputs/0/path"},
		{`{defaults: {outputs: [{language: "ts", path: "./a"}], output: "./b"}, specs: [{input: "missing.json"}]}`, "#/defaults/outputs"},
		{`{specs: [{input: "missing.json", outputs: [{language: "ts", path: "./a"}], languages: ["ts"]}]}`, "#/specs/0/outputs"},
		{`{specs: [{input: "a.json", name: "api", outputs: [{language: "ts", path: "./a"}, {language: "ts", path: "./a/../a"}]}]}`, "Conflicting output path"},
		{`{defaults: {optional: "yes"}, specs: [{input: "missing.json"}]}`, "#/defaults/optional"},
		{`{specs: [{input: "missing.json", optional: 1}]}`, "#/specs/0/optional"},
		{`{specs: [{input: "missing.json", optional: null}]}`, "#/specs/0/optional"},
	}
	path := fmt.aprintf("%s/tukan.json5", work.dir)
	for scenario in cases {
		if !testing.expect(t, os.write_entire_file(path, scenario.config) == nil, "invalid config should be written") { return }
		state, stdout, stderr, run_err := run_cli(work, {})
		testing.expectf(t, run_err == nil && state.exit_code != 0, "invalid configuration should fail: %s", scenario.config)
		testing.expectf(t, strings.contains(string(stderr), scenario.expected), "%s: expected %s, got %s", scenario.config, scenario.expected, string(stderr))
		testing.expectf(t, !strings.contains(string(stdout), "Specification:"), "invalid configuration must not start input processing: %s", scenario.config)
	}
	testing.expect(t, !os.exists(fmt.aprintf("%s/src", work.dir)), "invalid configurations must not create output directories")
}

@(test)
config_continues_other_specs_and_preserves_outputs_of_failed_specs :: proc(t: ^testing.T) {
	arena: virtual.Arena
	err := virtual.arena_init_growing(&arena)
	if !testing.expect(t, err == nil, "test arena should initialize") { return }
	defer virtual.arena_destroy(&arena)
	context.allocator = virtual.arena_allocator(&arena)

	work, ready := make_test_workspace(t)
	if !ready { return }
	defer os.remove_all(work.dir)
	output := fmt.aprintf("%s/output", work.dir)
	if !testing.expect(t, os.make_directory(output) == nil, "output directory should exist") { return }
	for name in ([3]string{"invalid", "missing", "malformed"}) {
		for extension in ([2]string{"ts", "dart"}) {
			if !testing.expect(t, os.write_entire_file(fmt.aprintf("%s/%s.%s", output, name, extension), "previous output") == nil, "previous output should be written") { return }
		}
	}
	config := `{
		defaults: {languages: ["ts", "dart"], output: "./output"},
		specs: [
			{name: "invalid", input: INVALID_SOURCE},
			{name: "valid", input: VALID_SOURCE},
			{name: "missing", input: "./does-not-exist.json"},
			{name: "malformed", input: MALFORMED_SOURCE},
		],
	}`
	config, _ = strings.replace_all(config, "INVALID_SOURCE", fmt.aprintf("%q", fmt.aprintf("%s/core/tests/fixtures/specs/invalid-spec.json", work.root)))
	config, _ = strings.replace_all(config, "VALID_SOURCE", fmt.aprintf("%q", fmt.aprintf("%s/core/tests/fixtures/specs/valid-schemas.json", work.root)))
	config, _ = strings.replace_all(config, "MALFORMED_SOURCE", fmt.aprintf("%q", fmt.aprintf("%s/core/tests/fixtures/specs/invalid-json.json", work.root)))
	if !testing.expect(t, os.write_entire_file(fmt.aprintf("%s/tukan.json5", work.dir), config) == nil, "batch config should be written") { return }

	state, stdout, stderr, run_err := run_cli(work, {})
	testing.expect(t, run_err == nil && state.exit_code != 0, "batch should report failed specifications")
	summary_index := strings.index(string(stdout), "\nGenerated files (2)\n")
	if testing.expectf(t, summary_index >= 0, "batch should summarize only the two successful outputs: %s", string(stdout)) {
		summary := string(stdout)[summary_index:]
		for extension in ([2]string{"ts", "dart"}) {
			testing.expectf(t, strings.contains(summary, fmt.aprintf("%s/valid.%s\n", output, extension)), "summary should include the generated %s file: %s", extension, summary)
		}
		for name in ([3]string{"invalid", "missing", "malformed"}) {
			testing.expectf(t, !strings.contains(summary, fmt.aprintf("%s/%s.", output, name)), "summary should exclude preserved %s output: %s", name, summary)
		}
	}
	for source in ([3]string{"invalid-spec.json", "does-not-exist.json", "invalid-json.json"}) {
		testing.expectf(t, strings.contains(string(stderr), source), "diagnostics should identify failed source %s: %s", source, string(stderr))
	}
	for extension in ([2]string{"ts", "dart"}) {
		generated, generated_err := os.read_entire_file(fmt.aprintf("%s/valid.%s", output, extension), context.allocator)
		testing.expectf(t, generated_err == nil && len(generated) > 0, "valid specification should generate %s despite other failures", extension)
		for name in ([3]string{"invalid", "missing", "malformed"}) {
			previous, read_err := os.read_entire_file(fmt.aprintf("%s/%s.%s", output, name, extension), context.allocator)
			if testing.expectf(t, read_err == nil, "%s.%s should remain readable", name, extension) {
				testing.expectf(t, string(previous) == "previous output", "%s.%s must remain unchanged", name, extension)
			}
		}
	}
}

@(test)
config_downloads_multiple_specs_concurrently :: proc(t: ^testing.T) {
	arena: virtual.Arena
	err := virtual.arena_init_growing(&arena)
	if !testing.expect(t, err == nil, "test arena should initialize") { return }
	defer virtual.arena_destroy(&arena)
	context.allocator = virtual.arena_allocator(&arena)

	work, ready := make_test_workspace(t)
	if !ready { return }
	defer os.remove_all(work.dir)
	body, read_err := os.read_entire_file(fmt.aprintf("%s/core/tests/fixtures/specs/valid-operations.json", work.root), context.allocator)
	if !testing.expect(t, read_err == nil, "example should be readable") { return }

	requests: sync.Wait_Group
	sync.wait_group_add(&requests, 2)
	first, second: HttpFixture
	if !start_http_fixture(t, &first, body, requests_ready = &requests) { return }
	defer thread.destroy(first.worker)
	if !start_http_fixture(t, &second, body, requests_ready = &requests) { return }
	defer thread.destroy(second.worker)
	config := `{
		concurrency: 2,
		defaults: {languages: ["ts", "dart"]},
		specs: [{name: "first", input: FIRST_URL}, {name: "second", input: SECOND_URL}],
	}`
	config, _ = strings.replace_all(config, "FIRST_URL", fmt.aprintf("%q", first.url))
	config, _ = strings.replace_all(config, "SECOND_URL", fmt.aprintf("%q", second.url))
	if !testing.expect(t, os.write_entire_file(fmt.aprintf("%s/tukan.json5", work.dir), config) == nil, "remote config should be written") { return }

	state, _, stderr, run_err := run_cli(work, {})
	thread.join(first.worker)
	thread.join(second.worker)
	testing.expectf(t, first.failure == "" && second.failure == "", "both requests must overlap: %s / %s", first.failure, second.failure)
	if !testing.expectf(t, run_err == nil && state.exit_code == 0, "concurrent downloads should generate all outputs: %s", string(stderr)) { return }
	for extension in ([2]string{"ts", "dart"}) {
		first_output, first_err := os.read_entire_file(fmt.aprintf("%s/src/generated/first.%s", work.dir, extension), context.allocator)
		second_output, second_err := os.read_entire_file(fmt.aprintf("%s/src/generated/second.%s", work.dir, extension), context.allocator)
		if testing.expectf(t, first_err == nil && second_err == nil, "both sources should generate %s", extension) {
			testing.expectf(t, string(first_output) == string(second_output), "%s generation should stay isolated across concurrent inputs", extension)
		}
	}
}

@(test)
input_list_resolves_relative_files_and_preserves_spaces_and_line_endings :: proc(t: ^testing.T) {
	arena: virtual.Arena
	err := virtual.arena_init_growing(&arena)
	if !testing.expect(t, err == nil, "test arena should initialize") { return }
	defer virtual.arena_destroy(&arena)
	context.allocator = virtual.arena_allocator(&arena)

	work, ready := make_test_workspace(t)
	if !ready { return }
	defer os.remove_all(work.dir)
	directory := fmt.aprintf("%s/specs", work.dir)
	if !testing.expect(t, os.make_directory(directory) == nil, "input directory should be created") { return }
	body, read_err := os.read_entire_file(fmt.aprintf("%s/core/tests/fixtures/specs/valid-schemas.json", work.root), context.allocator)
	if !testing.expect(t, read_err == nil, "example should be readable") { return }
	for file in ([2]string{"first api.json", "second.json"}) {
		if !testing.expect(t, os.write_entire_file(fmt.aprintf("%s/%s", directory, file), body) == nil, "list input should be written") { return }
	}
	list := fmt.aprintf("%s/inputs.txt", directory)
	if !testing.expect(t, os.write_entire_file(list, "\xef\xbb\xbf  first api.json \r\n\r\nsecond.json") == nil, "input list should be written") { return }
	state, _, stderr, run_err := run_cli(work, {"--input-list", list, "-l", "ts,dart"})
	if !testing.expectf(t, run_err == nil && state.exit_code == 0, "list generation should succeed: %s", string(stderr)) { return }
	for name in ([2]string{"first api", "second"}) {
		for extension in ([2]string{"ts", "dart"}) {
			testing.expectf(t, os.exists(fmt.aprintf("%s/tukan-output/%s.%s", work.dir, name, extension)), "%s.%s should be generated", name, extension)
		}
	}
}

@(test)
config_rejects_output_aliases_and_preserves_input_files :: proc(t: ^testing.T) {
	arena: virtual.Arena
	err := virtual.arena_init_growing(&arena)
	if !testing.expect(t, err == nil, "test arena should initialize") { return }
	defer virtual.arena_destroy(&arena)
	context.allocator = virtual.arena_allocator(&arena)

	work, ready := make_test_workspace(t)
	if !ready { return }
	defer os.remove_all(work.dir)
	output := fmt.aprintf("%s/output", work.dir)
	alias := fmt.aprintf("%s/alias", work.dir)
	if !testing.expect(t, os.make_directory(output) == nil, "output directory should be created") { return }
	if !testing.expect(t, os.symlink(output, alias) == nil, "output alias should be created") { return }
	input := fmt.aprintf("%s/input.ts", work.dir)
	source := `{"openapi":"3.0.3","components":{"schemas":{"Value":{"type":"string"}}}}`
	if !testing.expect(t, os.write_entire_file(input, source) == nil, "JSON input with a target-language extension should be written") { return }
	first := fmt.aprintf("%s/first.ts", output)
	second := fmt.aprintf("%s/second.ts", output)
	if !testing.expect(t, os.write_entire_file(first, "previous output") == nil, "existing output should be written") { return }
	if !testing.expect(t, os.link(first, second) == nil, "hard-linked output should be created") { return }

	cases := [?]struct { config: string, expected: string }{
		{`{specs: [{name: "api", input: "input.ts", output: "./output"}, {name: "api", input: "input.ts", output: "./alias"}]}`, "Conflicting output path"},
		{`{specs: [{name: "input", input: "input.ts", output: "."}]}`, "Output would overwrite an input specification"},
		{`{defaults: {output: "./output"}, specs: [{name: "first", input: "input.ts"}, {name: "second", input: "input.ts"}]}`, "Conflicting output path"},
	}
	for scenario in cases {
		if !testing.expect(t, os.write_entire_file(fmt.aprintf("%s/tukan.json5", work.dir), scenario.config) == nil, "conflicting configuration should be written") { return }
		state, stdout, stderr, run_err := run_cli(work, {})
		testing.expectf(t, run_err == nil && state.exit_code != 0, "conflicting config should fail: %s", scenario.config)
		testing.expectf(t, strings.contains(string(stderr), scenario.expected), "expected %s, got %s", scenario.expected, string(stderr))
		testing.expect(t, !strings.contains(string(stdout), "Specification:"), "conflicts should be rejected before input processing")
	}
	unchanged, read_err := os.read_entire_file(input, context.allocator)
	if testing.expect(t, read_err == nil, "original input should remain readable") {
		testing.expect_value(t, string(unchanged), source)
	}
	for file in ([2]string{first, second}) {
		unchanged, read_err := os.read_entire_file(file, context.allocator)
		if testing.expectf(t, read_err == nil, "%s should remain readable", file) {
			testing.expect_value(t, string(unchanged), "previous output")
		}
	}
}

@(test)
config_supports_multi_output_targets_in_defaults_and_specs :: proc(t: ^testing.T) {
	arena: virtual.Arena
	err := virtual.arena_init_growing(&arena)
	if !testing.expect(t, err == nil, "test arena should initialize") { return }
	defer virtual.arena_destroy(&arena)
	context.allocator = virtual.arena_allocator(&arena)

	work, ready := make_test_workspace(t)
	if !ready { return }
	defer os.remove_all(work.dir)

	directory := fmt.aprintf("%s/monorepo", work.dir)
	if !testing.expect(t, os.make_directory(directory) == nil, "monorepo directory should be created") { return }
	body, read_err := os.read_entire_file(fmt.aprintf("%s/core/tests/fixtures/specs/valid-operations.json", work.root), context.allocator)
	if !testing.expect(t, read_err == nil, "operation example should be readable") { return }
	if !testing.expect(t, os.write_entire_file(fmt.aprintf("%s/auth.json", directory), body) == nil, "auth spec should be written") { return }
	if !testing.expect(t, os.write_entire_file(fmt.aprintf("%s/tasks.json", directory), body) == nil, "tasks spec should be written") { return }
	if !testing.expect(t, os.write_entire_file(fmt.aprintf("%s/billing.json", directory), body) == nil, "billing spec should be written") { return }

	config := `{
		defaults: {
			outputs: [
				{ language: "ts", path: "./web" },
				{ language: "ts", path: "./admin" },
				{ language: "dart", path: "./mobile" },
			],
		},
		specs: [
			{ name: "auth", input: "./auth.json" },
			{
				name: "tasks",
				input: "./tasks.json",
				outputs: [
					{ language: "dart", path: "./tasks-mobile" },
				],
			},
			{
				name: "billing",
				input: "./billing.json",
				languages: ["dart"],
				output: "./legacy-dart",
			},
		],
	}`
	config_path := fmt.aprintf("%s/tukan.json5", directory)
	if !testing.expect(t, os.write_entire_file(config_path, config) == nil, "multi-output config should be written") { return }

	state, stdout, stderr, run_err := run_cli(work, {"--config", config_path})
	if !testing.expectf(t, run_err == nil && state.exit_code == 0, "multi-output config should succeed: %s", string(stderr)) { return }
	testing.expect_value(t, strings.count(string(stdout), "Specification:"), 3)
	testing.expect(t, strings.contains(string(stdout), "Generated files (5)"), "three auth + one tasks + one billing files should be generated")

	expected_files := [5]string{
		"web/auth.ts",
		"admin/auth.ts",
		"mobile/auth.dart",
		"tasks-mobile/tasks.dart",
		"legacy-dart/billing.dart",
	}
	for file in expected_files {
		testing.expectf(t, os.exists(fmt.aprintf("%s/%s", directory, file)), "expected multi-output file: %s", file)
	}
	testing.expect(t, !os.exists(fmt.aprintf("%s/legacy-dart/billing.ts", directory)), "classic override should clear defaults.outputs")

	// -l dart filters outputs targets without writing .dart into TS directories.
	filter_config := `{
		defaults: {
			outputs: [
				{ language: "ts", path: "./filtered-web" },
				{ language: "dart", path: "./filtered-mobile" },
			],
		},
		specs: [{ name: "auth", input: "./auth.json" }],
	}`
	filter_path := fmt.aprintf("%s/filter.json5", directory)
	if !testing.expect(t, os.write_entire_file(filter_path, filter_config) == nil, "filter config should be written") { return }

	filter_state, _, filter_stderr, filter_err := run_cli(work, {"--config", filter_path, "-l", "dart"})
	if !testing.expectf(t, filter_err == nil && filter_state.exit_code == 0, "filtered multi-output should succeed: %s", string(filter_stderr)) { return }
	testing.expect(t, os.exists(fmt.aprintf("%s/filtered-mobile/auth.dart", directory)), "filtered dart output should exist")
	testing.expect(t, !os.exists(fmt.aprintf("%s/filtered-web/auth.dart", directory)), "-l dart must not write dart into ts target path")
	testing.expect(t, !os.exists(fmt.aprintf("%s/filtered-web/auth.ts", directory)), "-l dart must skip ts target")

	override_state, _, override_stderr, override_err := run_cli(work, {"--config", filter_path, "-l", "ts,dart", "-o", "./override-all"})
	if !testing.expectf(t, override_err == nil && override_state.exit_code == 0, "override multi-output should succeed: %s", string(override_stderr)) { return }
	testing.expect(t, os.exists(fmt.aprintf("%s/override-all/auth.ts", work.dir)), "override ts output should exist")
	testing.expect(t, os.exists(fmt.aprintf("%s/override-all/auth.dart", work.dir)), "override dart output should exist")
}

@(test)
config_optional_specs_warn_on_load_failure_and_respect_inheritance_and_strict :: proc(t: ^testing.T) {
	arena: virtual.Arena
	err := virtual.arena_init_growing(&arena)
	if !testing.expect(t, err == nil, "test arena should initialize") { return }
	defer virtual.arena_destroy(&arena)
	context.allocator = virtual.arena_allocator(&arena)

	work, ready := make_test_workspace(t)
	if !ready { return }
	defer os.remove_all(work.dir)

	output := fmt.aprintf("%s/output", work.dir)
	if !testing.expect(t, os.make_directory(output) == nil, "output directory should exist") { return }
	for name in ([3]string{"missing", "malformed", "invalid"}) {
		for extension in ([2]string{"ts", "dart"}) {
			if !testing.expect(t, os.write_entire_file(fmt.aprintf("%s/%s.%s", output, name, extension), "previous output") == nil, "previous output should be written") { return }
		}
	}

	valid_source := fmt.aprintf("%s/core/tests/fixtures/specs/valid-schemas.json", work.root)
	config := `{
		defaults: {languages: ["ts", "dart"], output: "./output", optional: true},
		specs: [
			{name: "missing", input: "./does-not-exist.json"},
			{name: "inherited_valid", input: VALID_SOURCE},
			{name: "required_valid", input: VALID_SOURCE, optional: false},
		],
	}`
	config, _ = strings.replace_all(config, "VALID_SOURCE", fmt.aprintf("%q", valid_source))
	if !testing.expect(t, os.write_entire_file(fmt.aprintf("%s/tukan.json5", work.dir), config) == nil, "optional config should be written") { return }

	state, stdout, stderr, run_err := run_cli(work, {})
	testing.expectf(t, run_err == nil && state.exit_code == 0, "optional missing spec should not fail run: %s", string(stderr))
	testing.expectf(t, strings.contains(string(stdout), "Skipped optional specification"), "stdout should explain skipped optional spec: %s", string(stdout))
	testing.expectf(t, strings.contains(string(stdout), "\nGenerated files (4)\n"), "only required/available outputs should be generated: %s", string(stdout))
	testing.expectf(t, !strings.contains(string(stdout), fmt.aprintf("%s/missing.", output)), "skipped optional spec should not be listed in Generated files: %s", string(stdout))
	testing.expectf(t, strings.contains(string(stderr), "warning: Failed to read specification"), "missing optional spec should emit a warning: %s", string(stderr))
	testing.expectf(t, !strings.contains(string(stderr), "error:"), "optional load failure must not emit error: %s", string(stderr))

	for extension in ([2]string{"ts", "dart"}) {
		for name in ([2]string{"inherited_valid", "required_valid"}) {
			testing.expectf(t, os.exists(fmt.aprintf("%s/%s.%s", output, name, extension)), "%s.%s should be generated", name, extension)
		}
		previous, read_err := os.read_entire_file(fmt.aprintf("%s/missing.%s", output, extension), context.allocator)
		if testing.expectf(t, read_err == nil, "missing.%s should remain readable", extension) {
			testing.expect_value(t, string(previous), "previous output")
		}
	}

	strict_state, _, strict_stderr, strict_err := run_cli(work, {"--strict"})
	testing.expectf(t, strict_err == nil && strict_state.exit_code == 1, "--strict should fail on missing optional spec: %s", string(strict_stderr))
	testing.expectf(t, strings.contains(string(strict_stderr), "error: Failed to read specification"), "--strict should emit an error: %s", string(strict_stderr))
	for extension in ([2]string{"ts", "dart"}) {
		previous, read_err := os.read_entire_file(fmt.aprintf("%s/missing.%s", output, extension), context.allocator)
		if testing.expectf(t, read_err == nil, "missing.%s should remain readable after --strict", extension) {
			testing.expect_value(t, string(previous), "previous output")
		}
	}

	// Explicit optional: false overrides defaults.optional: true even without --strict.
	override_config := `{
		defaults: {languages: ["ts", "dart"], output: "./output", optional: true},
		specs: [
			{name: "missing", input: "./does-not-exist.json", optional: false},
			{name: "valid", input: VALID_SOURCE},
		],
	}`
	override_config, _ = strings.replace_all(override_config, "VALID_SOURCE", fmt.aprintf("%q", valid_source))
	if !testing.expect(t, os.write_entire_file(fmt.aprintf("%s/tukan.json5", work.dir), override_config) == nil, "override config should be written") { return }

	override_state, _, override_stderr, override_err := run_cli(work, {})
	testing.expectf(t, override_err == nil && override_state.exit_code == 1, "optional: false should override defaults.optional: %s", string(override_stderr))
	testing.expectf(t, strings.contains(string(override_stderr), "error: Failed to read specification"), "optional: false should emit error: %s", string(override_stderr))

	// Invalid JSON and invalid OpenAPI schemas must still fail even when optional: true.
	parse_fail_cases := [?]struct { name, input_file, expected: string }{
		{"malformed", fmt.aprintf("%s/core/tests/fixtures/specs/invalid-json.json", work.root), "Failed to parse specification JSON"},
		{"invalid", fmt.aprintf("%s/core/tests/fixtures/specs/invalid-spec.json", work.root), "error:"},
	}
	for scenario in parse_fail_cases {
		cfg := `{defaults: {languages: ["ts", "dart"], output: "./output"}, specs: [{name: SPEC_NAME, input: SPEC_INPUT, optional: true}]}`
		cfg, _ = strings.replace_all(cfg, "SPEC_NAME", fmt.aprintf("%q", scenario.name))
		cfg, _ = strings.replace_all(cfg, "SPEC_INPUT", fmt.aprintf("%q", scenario.input_file))
		if !testing.expect(t, os.write_entire_file(fmt.aprintf("%s/tukan.json5", work.dir), cfg) == nil, "parse-fail optional config should be written") { return }
		fail_state, _, fail_stderr, fail_err := run_cli(work, {})
		testing.expectf(t, fail_err == nil && fail_state.exit_code == 1, "%s: decode/parse error must still fail when optional: true: %s", scenario.name, string(fail_stderr))
		testing.expectf(t, strings.contains(string(fail_stderr), scenario.expected), "%s: expected %s in stderr: %s", scenario.name, scenario.expected, string(fail_stderr))
		for extension in ([2]string{"ts", "dart"}) {
			previous, read_err := os.read_entire_file(fmt.aprintf("%s/%s.%s", output, scenario.name, extension), context.allocator)
			if testing.expectf(t, read_err == nil, "%s.%s should remain readable", scenario.name, extension) {
				testing.expect_value(t, string(previous), "previous output")
			}
		}
	}
}
