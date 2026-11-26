package tests

import "core:fmt"
import virtual "core:mem/virtual"
import "core:net"
import "core:os"
import "core:strings"
import "core:testing"
import "core:thread"
import "core:time"

@(test)
http_input_matches_file_input :: proc(t: ^testing.T) {
	arena: virtual.Arena
	err := virtual.arena_init_growing(&arena)
	if !testing.expect(t, err == nil, "test arena should initialize") { return }
	defer virtual.arena_destroy(&arena)
	context.allocator = virtual.arena_allocator(&arena)

	work, ready := make_test_workspace(t)
	if !ready { return }
	defer os.remove_all(work.dir)

	source := fmt.aprintf("%s/core/tests/fixtures/specs/valid-schemas.json", work.root)
	body, read_err := os.read_entire_file(source, context.allocator)
	if !testing.expect(t, read_err == nil, "example specification should be readable") { return }

	local_dir := fmt.aprintf("%s/local", work.dir)
	local, _, local_stderr, local_err := run_cli(work, {"-l", "ts,dart", "-i", source, "-o", local_dir})
	if !testing.expectf(t, local_err == nil && local.exit_code == 0, "file input should generate types: %s", string(local_stderr)) { return }

	fixture: HttpFixture
	if !start_http_fixture(t, &fixture, body, request_target = "/spec.json?download=1", response_delay = 100 * time.Millisecond) { return }
	defer thread.destroy(fixture.worker)

	remote, stdout, stderr, run_err := run_cli(work, {"-l", "ts,dart", "-i", fmt.aprintf("%s?download=1#schema", fixture.url)})
	thread.join(fixture.worker)

	if !testing.expectf(t, fixture.failure == "", "HTTP fixture failed during %s: %v", fixture.failure, fixture.network_error) { return }
	if !testing.expectf(t, run_err == nil && remote.exit_code == 0, "HTTP input should generate types: %s", string(stderr)) { return }
	total_ms, total_measured := read_total_time_ms(string(stdout))
	testing.expectf(t, total_measured && total_ms >= 100, "elapsed time should include waiting for the delayed response: %s", string(stdout))
	testing.expect_value(t, string(stderr), "")
	testing.expect(t, strings.contains(string(stdout), "Schemas: 6 parsed, 0 failed"), "HTTP input should preserve schema counts")

	for suffix in ([2]string{"ts", "dart"}) {
		local_output, local_read_err := os.read_entire_file(fmt.aprintf("%s/valid-schemas.%s", local_dir, suffix), context.allocator)
		remote_output, remote_read_err := os.read_entire_file(fmt.aprintf("%s/tukan-output/spec.%s", work.dir, suffix), context.allocator)
		if !testing.expectf(t, local_read_err == nil && remote_read_err == nil, "%s output should exist for both input sources", suffix) { continue }

		testing.expect_value(t, string(remote_output), string(local_output))
	}
}

@(test)
http_invalid_json_preserves_previous_output :: proc(t: ^testing.T) {
	arena: virtual.Arena
	err := virtual.arena_init_growing(&arena)
	if !testing.expect(t, err == nil, "test arena should initialize") { return }
	defer virtual.arena_destroy(&arena)
	context.allocator = virtual.arena_allocator(&arena)

	work, ready := make_test_workspace(t)
	if !ready { return }
	defer os.remove_all(work.dir)

	output_dir, output_err := write_previous_http_output(work, "previous output")
	if !testing.expectf(t, output_err == nil, "previous output should be written: %v", output_err) { return }

	body, read_err := os.read_entire_file(fmt.aprintf("%s/core/tests/fixtures/specs/invalid-json.json", work.root), context.allocator)
	if !testing.expect(t, read_err == nil, "invalid JSON example should be readable") { return }

	fixture: HttpFixture
	if !start_http_fixture(t, &fixture, body) { return }
	defer thread.destroy(fixture.worker)

	state, _, stderr, run_err := run_cli(work, {"-l", "ts,dart", "-i", fixture.url})
	thread.join(fixture.worker)

	testing.expectf(t, fixture.failure == "", "HTTP fixture failed during %s: %v", fixture.failure, fixture.network_error)
	testing.expect(t, run_err == nil && state.exit_code != 0, "invalid HTTP JSON should fail the CLI")
	testing.expect(t, strings.contains(string(stderr), "Failed to parse specification JSON"), "invalid HTTP JSON should be explained")

	for name in ([2]string{"spec.ts", "spec.dart"}) {
		content, output_err := os.read_entire_file(fmt.aprintf("%s/%s", output_dir, name), context.allocator)
		if testing.expectf(t, output_err == nil, "%s should remain readable", name) {
			testing.expect_value(t, string(content), "previous output")
		}
	}
}

@(test)
http_error_status_preserves_output_even_with_valid_json :: proc(t: ^testing.T) {
	arena: virtual.Arena
	err := virtual.arena_init_growing(&arena)
	if !testing.expect(t, err == nil, "test arena should initialize") { return }
	defer virtual.arena_destroy(&arena)
	context.allocator = virtual.arena_allocator(&arena)

	work, ready := make_test_workspace(t)
	if !ready { return }
	defer os.remove_all(work.dir)

	output_dir, output_err := write_previous_http_output(work, "previous output")
	if !testing.expectf(t, output_err == nil, "previous output should be written: %v", output_err) { return }

	body, read_err := os.read_entire_file(fmt.aprintf("%s/core/tests/fixtures/specs/valid-schemas.json", work.root), context.allocator)
	if !testing.expect(t, read_err == nil, "valid specification should be readable") { return }

	fixture: HttpFixture
	if !start_http_fixture(t, &fixture, body, "404 Not Found", response_delay = 100 * time.Millisecond) { return }
	defer thread.destroy(fixture.worker)

	state, stdout, stderr, run_err := run_cli(work, {"-l", "ts,dart", "-i", fixture.url})
	thread.join(fixture.worker)

	testing.expectf(t, fixture.failure == "", "HTTP fixture failed during %s: %v", fixture.failure, fixture.network_error)
	testing.expect(t, run_err == nil && state.exit_code != 0, "an HTTP error status must fail even when its body is valid OpenAPI JSON")
	testing.expect(t, strings.contains(string(stderr), "Failed to fetch specification"), "HTTP status failure should be explained")
	testing.expect(t, strings.contains(string(stderr), "HTTP 404"), "diagnostic should include the HTTP status")
	total_ms, measured := read_total_time_ms(string(stdout))
	testing.expectf(t, measured && total_ms >= 100, "elapsed time should include waiting for a failed HTTP response: %s", string(stdout))
	testing.expectf(t, strings.contains(string(stdout), "Generated files (0)\n  None."), "a failed HTTP request should not report preserved files as generated: %s", string(stdout))

	for name in ([2]string{"spec.ts", "spec.dart"}) {
		content, output_err := os.read_entire_file(fmt.aprintf("%s/%s", output_dir, name), context.allocator)
		if testing.expectf(t, output_err == nil, "%s should remain readable", name) {
			testing.expect_value(t, string(content), "previous output")
		}
	}
}

@(test)
http_refused_connection_preserves_previous_output :: proc(t: ^testing.T) {
	arena: virtual.Arena
	err := virtual.arena_init_growing(&arena)
	if !testing.expect(t, err == nil, "test arena should initialize") { return }
	defer virtual.arena_destroy(&arena)
	context.allocator = virtual.arena_allocator(&arena)

	work, ready := make_test_workspace(t)
	if !ready { return }
	defer os.remove_all(work.dir)

	output_dir, output_err := write_previous_http_output(work, "previous output")
	if !testing.expectf(t, output_err == nil, "previous output should be written: %v", output_err) { return }

	// Reserve a port without listening so no other process can acquire it during the check.
	socket, socket_err := net.create_socket(.IP4, .TCP)
	if !testing.expectf(t, socket_err == nil, "test socket should be created: %v", socket_err) { return }
	defer net.close(socket)

	if bind_err := net.bind(socket, {net.IP4_Loopback, 0}); !testing.expectf(t, bind_err == nil, "test port should be reserved: %v", bind_err) { return }
	endpoint, endpoint_err := net.bound_endpoint(socket)
	if !testing.expect(t, endpoint_err == nil, "reserved port should be available") { return }

	url := fmt.aprintf("http://127.0.0.1:%d/spec.json", endpoint.port)
	state, _, stderr, run_err := run_cli(work, {"-l", "ts,dart", "-i", url})

	testing.expect(t, run_err == nil && state.exit_code != 0, "refused connection should fail the CLI")
	testing.expect(t, strings.contains(string(stderr), "Failed to fetch specification"), "connection failure should be explained")

	for name in ([2]string{"spec.ts", "spec.dart"}) {
		content, output_err := os.read_entire_file(fmt.aprintf("%s/%s", output_dir, name), context.allocator)
		if testing.expectf(t, output_err == nil, "%s should remain readable", name) {
			testing.expect_value(t, string(content), "previous output")
		}
	}
}
