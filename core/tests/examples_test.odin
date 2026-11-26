package tests

import "core:fmt"
import virtual "core:mem/virtual"
import "core:os"
import "core:strings"
import "core:testing"

@(test)
valid_examples_generate_types :: proc(t: ^testing.T) {
	arena: virtual.Arena
	err := virtual.arena_init_growing(&arena)
	if !testing.expect(t, err == nil, "test arena should initialize") { return }
	defer virtual.arena_destroy(&arena)
	context.allocator = virtual.arena_allocator(&arena)

	work, ready := make_test_workspace(t)
	if !ready { return }
	defer os.remove_all(work.dir)

	cases := [10]struct {
		file: string,
		schema_count: int,
		operation_count: int,
		expected_typescript: []string,
		expected_dart: []string,
		expected_warning: string,
	}{
		{"valid-annotations.json", 3, 1, {"minLength: 3", "Currency identifier.", "Upload input", "Encoding.currency-id.contentType: text/plain"}, {"defaults not applied", "Currency identifier.", "Upload input"}, ""},
		{"valid-schemas.json", 6, 0, {`"photo"?: Blob;`}, {"final List<int>? photo;", "enum Priority {"}, ""},
		{"valid-operations.json", 3, 2, {`"multipart/form-data"`}, {"class GetDocumentPathParameters {"}, ""},
		{"valid-directions.json", 1, 5, {`Schemas["UserRequest"]`, `Schemas["UserResponse"]`}, {"class UserRequest {", "class UserResponse {", "class CreateInlineRequest {", "class CreateInlineResponseItem {"}, ""},
		{"valid-security.json", 1, 5, {`"TukanMetadata": string;`, "Authentication: Bearer.", "Authentication: none required.", "Authentication: (Bearer AND Key) OR OAuth (scopes: write:user)."}, {"typedef TukanMetadata = String;"}, ""},
		{"valid-wire.json", 5, 2, {`"ready" | "in-progress"`, `"amount"?: number`}, {"class Patch {", "copyWith("}, ""},
		{"valid-recursive.json", 1, 0, {`Schemas["Node"]`}, {"class Node {", "final List<Node>? children;"}, ""},
		{"valid-names.json", 4, 0, {`"A/B~C"`, `"class": string;`}, {"class Class {"}, ""},
		{"billing.json", 38, 26, {`"application/pdf"`, `"application/x-www-form-urlencoded"`, `Schemas["LedgerEntry"]`}, {"class Invoice {", "class CreatePayment {"}, ""},
		{"catalog.json", 44, 26, {`"Localized/Title~Map"`, `"application/xml"`}, {"class Product {", "class SearchResult {"}, "#/components/schemas/PromotionTarget/oneOf"},
	}

	for scenario in cases {
		directory := "core/tests/fixtures/specs"
		if scenario.file == "billing.json" || scenario.file == "catalog.json" { directory = "test-specs" }
		input := fmt.aprintf("%s/%s/%s", work.root, directory, scenario.file)
		output_dir := fmt.aprintf("%s/tukan-output", work.root)
		state, stdout, stderr, run_err := run_cli(work, {"-l", "ts,dart", "-i", input, "-o", output_dir})
		if !testing.expectf(t, run_err == nil && state.exit_code == 0, "%s: generation failed: %s", scenario.file, string(stderr)) { continue }

		if scenario.expected_warning == "" {
			testing.expect_value(t, string(stderr), "")
		} else {
			testing.expectf(t, strings.contains(string(stderr), scenario.expected_warning), "%s: missing warning: %s", scenario.file, string(stderr))
		}
		testing.expectf(t, strings.contains(string(stdout), fmt.aprintf("Schemas: %d parsed, 0 failed", scenario.schema_count)), "%s: unexpected schema counts: %s", scenario.file, string(stdout))
		testing.expectf(t, strings.contains(string(stdout), fmt.aprintf("Operations: %d parsed, 0 failed", scenario.operation_count)), "%s: unexpected operation counts: %s", scenario.file, string(stdout))

		name := os.stem(scenario.file)
		ts, ts_err := os.read_entire_file(fmt.aprintf("%s/%s.ts", output_dir, name), context.allocator)
		dart, dart_err := os.read_entire_file(fmt.aprintf("%s/%s.dart", output_dir, name), context.allocator)
		if !testing.expectf(t, ts_err == nil && dart_err == nil, "%s: both outputs should exist", scenario.file) { continue }

		for expected in scenario.expected_typescript {
			testing.expectf(t, strings.contains(string(ts), expected), "%s: missing TypeScript %s", scenario.file, expected)
		}

		for expected in scenario.expected_dart {
			testing.expectf(t, strings.contains(string(dart), expected), "%s: missing Dart %s", scenario.file, expected)
		}
	}
}

@(test)
invalid_examples_preserve_previous_output :: proc(t: ^testing.T) {
	arena: virtual.Arena
	err := virtual.arena_init_growing(&arena)
	if !testing.expect(t, err == nil, "test arena should initialize") { return }
	defer virtual.arena_destroy(&arena)
	context.allocator = virtual.arena_allocator(&arena)

	work, ready := make_test_workspace(t)
	if !ready { return }
	defer os.remove_all(work.dir)

	result_dir := fmt.aprintf("%s/tukan-output", work.dir)
	if !testing.expect(t, os.make_directory(result_dir) == nil, "output directory should be created") { return }

	cases := [6]struct { file: string, expected_counts: string, expected_errors: []string }{
		{"invalid-spec.json", "Schemas: 0 parsed, 1 failed", {"MissingCustomer", "MissingItem", "Invalid~2Escape", "https://example.com/schemas.json"}},
		{"invalid-operations.json", "Operations: 0 parsed, 3 failed", {"MissingFilter", "MissingBody", "MissingResponse"}},
		{"invalid-security.json", "Operations: 0 parsed, 1 failed", {"missing-security-scheme", "#/paths/~1users/get/security/0/Missing"}},
		{"invalid-json.json", "Could not count schemas or operations", {"Failed to parse specification JSON"}},
		{"identity.json", "Schemas: 17 parsed, 7 failed", {"MissingManager", "#/components/schemas/AccountPatch/required", "MissingIdentityCommand", "MissingIdentityUnavailable"}},
		{"fulfillment.json", "Operations: 21 parsed, 3 failed", {"warning:", "MissingCustomsItem", "#/components/schemas/CarrierBatch/properties/retryCount/nullable", "MissingCarrierBatch", "MissingCarrierFailure"}},
	}

	for scenario in cases {
		name := os.stem(scenario.file)
		ts_path := fmt.aprintf("%s/%s.ts", result_dir, name)
		dart_path := fmt.aprintf("%s/%s.dart", result_dir, name)

		if !testing.expect(t, os.write_entire_file(ts_path, "previous TypeScript") == nil, "TypeScript sentinel should be written") { return }
		if !testing.expect(t, os.write_entire_file(dart_path, "previous Dart") == nil, "Dart sentinel should be written") { return }

		directory := "core/tests/fixtures/specs"
		if scenario.file == "identity.json" || scenario.file == "fulfillment.json" { directory = "test-specs" }
		input := fmt.aprintf("%s/%s/%s", work.root, directory, scenario.file)
		state, stdout, stderr, run_err := run_cli(work, {"-l", "ts,dart", "-i", input})
		if !testing.expectf(t, run_err == nil, "%s: CLI should start", scenario.file) { continue }

		testing.expectf(t, state.exit_code != 0, "%s: invalid input should fail", scenario.file)
		testing.expectf(t, strings.contains(string(stdout), scenario.expected_counts), "%s: unexpected counts: %s", scenario.file, string(stdout))
		for expected in scenario.expected_errors {
			testing.expectf(t, strings.contains(string(stderr), expected), "%s: missing diagnostic %s", scenario.file, expected)
		}

		ts, ts_err := os.read_entire_file(ts_path, context.allocator)
		dart, dart_err := os.read_entire_file(dart_path, context.allocator)
		if !testing.expect(t, ts_err == nil && dart_err == nil, "previous output should remain readable") { continue }

		testing.expect_value(t, string(ts), "previous TypeScript")
		testing.expect_value(t, string(dart), "previous Dart")
	}
}
