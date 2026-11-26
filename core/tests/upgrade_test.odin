package tests

import "core:crypto/hash"
import "core:encoding/hex"
import "core:fmt"
import virtual "core:mem/virtual"
import "core:net"
import "core:os"
import "core:strings"
import "core:sync"
import "core:testing"
import "core:thread"
import "core:time"

@(private)
UpgradeHttpFixture :: struct {
	listener: net.TCP_Socket,
	worker: ^thread.Thread,
	url: string,
	responses: map[string]string,
	stop: bool,
	failure: string,
}

@(private)
test_upgrade_binary_name :: proc() -> (string, bool) {
	platform: string
	when ODIN_OS == .Darwin {
		platform = "macos"
	} else when ODIN_OS == .Linux {
		platform = "linux"
	} else {
		return "", false
	}

	arch: string
	when ODIN_ARCH == .arm64 {
		arch = "arm64"
	} else when ODIN_ARCH == .amd64 {
		arch = "amd64"
	} else {
		return "", false
	}

	return fmt.aprintf("tukan-%s-%s", platform, arch), true
}

@(private)
build_http_response :: proc(status: string, body: []byte) -> string {
	return fmt.aprintf("HTTP/1.1 %s\r\nContent-Type: application/octet-stream\r\nContent-Length: %d\r\nConnection: close\r\n\r\n%s", status, len(body), string(body))
}

@(private)
start_upgrade_http_fixture :: proc(t: ^testing.T, fixture: ^UpgradeHttpFixture, routes: map[string]struct{status: string, body: []byte}) -> bool {
	listener, err := net.listen_tcp({net.IP4_Loopback, 0})
	if !testing.expectf(t, err == nil, "upgrade HTTP fixture should listen: %v", err) { return false }

	endpoint, endpoint_err := net.bound_endpoint(listener)
	if !testing.expectf(t, endpoint_err == nil, "upgrade HTTP fixture should expose port: %v", endpoint_err) {
		net.close(listener)
		return false
	}

	if blocking_err := net.set_blocking(listener, false); !testing.expectf(t, blocking_err == nil, "upgrade HTTP fixture should allow non-blocking accept: %v", blocking_err) {
		net.close(listener)
		return false
	}

	fixture.listener = listener
	fixture.url = fmt.aprintf("http://127.0.0.1:%d", endpoint.port)
	fixture.responses = make(map[string]string)
	for path, route in routes {
		fixture.responses[path] = build_http_response(route.status, route.body)
	}
	fixture.stop = false
	fixture.failure = ""

	fixture.worker = thread.create(serve_upgrade_http_fixture)
	if !testing.expect(t, fixture.worker != nil, "upgrade HTTP fixture worker should be created") {
		net.close(listener)
		return false
	}

	fixture.worker.data = fixture
	thread.start(fixture.worker)
	return true
}

@(private)
stop_upgrade_http_fixture :: proc(fixture: ^UpgradeHttpFixture) {
	sync.atomic_store(&fixture.stop, true)
	if fixture.worker != nil {
		thread.join(fixture.worker)
		thread.destroy(fixture.worker)
		fixture.worker = nil
	}
}

@(private)
handle_upgrade_http_client :: proc(conn: net.TCP_Socket, fixture: ^UpgradeHttpFixture, not_found: string) {
	defer net.close(conn)
	if err := net.set_blocking(conn, true); err != nil { return }
	for option in ([2]net.Socket_Option{.Receive_Timeout, .Send_Timeout}) {
		_ = net.set_option(conn, option, http_fixture_timeout)
	}

	request: [max_http_request_header_bytes]byte
	used := 0
	for !strings.contains(string(request[:used]), "\r\n\r\n") {
		if used == len(request) { return }
		count, recv_err := net.recv_tcp(conn, request[used:])
		if recv_err != nil || count == 0 { return }
		used += count
	}

	header := string(request[:used])
	line_end := strings.index(header, "\r\n")
	if line_end <= 0 { return }
	first_line := header[:line_end]
	parts := strings.split(first_line, " ")
	defer delete(parts)
	if len(parts) < 2 { return }

	response := not_found
	if mapped, ok := fixture.responses[parts[1]]; ok {
		response = mapped
	}
	_, _ = net.send_tcp(conn, transmute([]byte)response)
}

@(private)
serve_upgrade_http_fixture :: proc(worker: ^thread.Thread) {
	fixture := cast(^UpgradeHttpFixture)worker.data
	defer net.close(fixture.listener)
	not_found_response := "HTTP/1.1 404 Not Found\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"

	for !sync.atomic_load(&fixture.stop) {
		client, _, accept_err := net.accept_tcp(fixture.listener)
		if accept_err != nil {
			if accept_err == .Would_Block {
				time.sleep(time.Millisecond)
				continue
			}
			fixture.failure = "accept"
			return
		}

		handle_upgrade_http_client(client, fixture, not_found_response)
	}
}

@(private)
copy_test_binary :: proc(t: ^testing.T, work: TestWorkspace) -> (path: string, original: []byte, ok: bool) {
	src, read_err := os.read_entire_file(work.binary, context.allocator)
	if !testing.expectf(t, read_err == nil, "test binary should be readable: %v", read_err) { return }

	path = fmt.aprintf("%s/tukan", work.dir)
	if !testing.expectf(t, os.write_entire_file(path, src) == nil, "copied test binary should be written") { return }

	exec_mode := os.Permissions_Read_All + {.Write_User} + os.Permissions_Execute_All
	if !testing.expectf(t, os.chmod(path, exec_mode) == nil, "copied test binary should be executable") { return }

	return path, src, true
}

@(private)
run_binary_with_env :: proc(binary, working_dir: string, arguments: []string, extra_env: []string) -> (os.Process_State, []byte, []byte, os.Error) {
	base_env, _ := os.environ(context.allocator)
	env := make([dynamic]string)
	for entry in base_env {
		if strings.has_prefix(entry, "TUKAN_RELEASE_URL=") || strings.has_prefix(entry, "TUKAN_REPO=") {
			continue
		}
		append(&env, entry)
	}
	for entry in extra_env {
		append(&env, entry)
	}

	command := make([dynamic]string)
	append(&command, binary)
	for argument in arguments {
		append(&command, argument)
	}

	return os.process_exec({working_dir = working_dir, command = command[:], env = env[:]}, context.allocator)
}

@(private)
has_leftover_temp_files :: proc(dir: string) -> bool {
	entries, err := os.read_all_directory_by_path(dir, context.allocator)
	if err != nil { return true }
	for entry in entries {
		if strings.has_prefix(entry.name, ".tukan-upgrade-") {
			return true
		}
	}
	return false
}

@(private)
sha256_hex :: proc(data: []byte) -> string {
	digest := hash.hash_bytes(.SHA256, data)
	return strings.to_lower(string(hex.encode(digest)))
}

@(test)
upgrade_replaces_binary_after_checksum_and_version_verification :: proc(t: ^testing.T) {
	arena: virtual.Arena
	if !testing.expect(t, virtual.arena_init_growing(&arena) == nil, "arena should initialize") { return }
	defer virtual.arena_destroy(&arena)
	context.allocator = virtual.arena_allocator(&arena)

	binary_name, supported := test_upgrade_binary_name()
	if !supported { return }

	work, ready := make_test_workspace(t)
	if !ready { return }
	defer os.remove_all(work.dir)

	installed_path, _, copied := copy_test_binary(t, work)
	if !copied { return }

	replacement_script := transmute([]byte)string("#!/bin/sh\necho 'Tukan 9.9.9'\n")
	checksum := sha256_hex(replacement_script)
	sums := transmute([]byte)fmt.aprintf("%s  %s\n", checksum, binary_name)
	version_body := transmute([]byte)string("9.9.9\n")

	routes := make(map[string]struct{status: string, body: []byte})
	routes["/VERSION"] = {"200 OK", version_body}
	routes["/SHA256SUMS"] = {"200 OK", sums}
	routes[fmt.aprintf("/%s", binary_name)] = {"200 OK", replacement_script}

	fixture: UpgradeHttpFixture
	if !start_upgrade_http_fixture(t, &fixture, routes) { return }
	defer stop_upgrade_http_fixture(&fixture)

	env := []string{fmt.aprintf("TUKAN_RELEASE_URL=%s", fixture.url)}
	state, stdout, stderr, run_err := run_binary_with_env(installed_path, work.dir, {"upgrade"}, env)
	testing.expectf(t, run_err == nil && state.exit_code == 0, "upgrade should succeed: %s", string(stderr))
	testing.expect_value(t, string(stderr), "")
	testing.expectf(t, strings.contains(string(stdout), "Updated Tukan") && strings.contains(string(stdout), "9.9.9"), "stdout should report updated version: %s", string(stdout))
	testing.expect(t, !strings.contains(string(stdout), "Total time:"), "upgrade should not print Total time")
	testing.expect(t, !has_leftover_temp_files(work.dir), "upgrade must not leave temporary files behind")

	ver_state, ver_stdout, ver_stderr, ver_err := os.process_exec({working_dir = work.dir, command = []string{installed_path, "--version"}}, context.allocator)
	testing.expectf(t, ver_err == nil && ver_state.exit_code == 0, "upgraded binary should run: %s", string(ver_stderr))
	testing.expect_value(t, strings.trim_space(string(ver_stdout)), "Tukan 9.9.9")
}

@(test)
upgrade_skips_download_when_already_up_to_date :: proc(t: ^testing.T) {
	arena: virtual.Arena
	if !testing.expect(t, virtual.arena_init_growing(&arena) == nil, "arena should initialize") { return }
	defer virtual.arena_destroy(&arena)
	context.allocator = virtual.arena_allocator(&arena)

	work, ready := make_test_workspace(t)
	if !ready { return }
	defer os.remove_all(work.dir)

	installed_path, original_bytes, copied := copy_test_binary(t, work)
	if !copied { return }

	ver_state, ver_stdout, _, ver_err := os.process_exec({working_dir = work.dir, command = []string{installed_path, "--version"}}, context.allocator)
	if !testing.expect(t, ver_err == nil && ver_state.exit_code == 0, "current version should be readable") { return }
	current_version := strings.trim_space(strings.trim_prefix(strings.trim_space(string(ver_stdout)), "Tukan "))

	routes := make(map[string]struct{status: string, body: []byte})
	routes["/VERSION"] = {"200 OK", transmute([]byte)fmt.aprintf("%s\n", current_version)}

	fixture: UpgradeHttpFixture
	if !start_upgrade_http_fixture(t, &fixture, routes) { return }
	defer stop_upgrade_http_fixture(&fixture)

	env := []string{fmt.aprintf("TUKAN_RELEASE_URL=%s", fixture.url)}
	state, stdout, stderr, run_err := run_binary_with_env(installed_path, work.dir, {"upgrade"}, env)
	testing.expectf(t, run_err == nil && state.exit_code == 0, "up-to-date upgrade should succeed: %s", string(stderr))
	testing.expect_value(t, string(stderr), "")
	testing.expectf(t, strings.contains(string(stdout), "already up to date"), "stdout should state already up to date: %s", string(stdout))

	after_bytes, read_err := os.read_entire_file(installed_path, context.allocator)
	if testing.expect(t, read_err == nil, "installed binary should remain readable") {
		testing.expect_value(t, string(after_bytes), string(original_bytes))
	}
}

@(test)
upgrade_preserves_existing_binary_on_checksum_version_or_exec_failure :: proc(t: ^testing.T) {
	arena: virtual.Arena
	if !testing.expect(t, virtual.arena_init_growing(&arena) == nil, "arena should initialize") { return }
	defer virtual.arena_destroy(&arena)
	context.allocator = virtual.arena_allocator(&arena)

	binary_name, supported := test_upgrade_binary_name()
	if !supported { return }

	work, ready := make_test_workspace(t)
	if !ready { return }
	defer os.remove_all(work.dir)

	installed_path, original_bytes, copied := copy_test_binary(t, work)
	if !copied { return }

	bad_binary := transmute([]byte)string("#!/bin/sh\necho 'Tukan 9.9.8'\n")
	bad_checksum := strings.repeat("0", 64)
	valid_checksum_of_bad_binary := sha256_hex(bad_binary)

	// (a) Checksum mismatch
	routes_a := make(map[string]struct{status: string, body: []byte})
	routes_a["/VERSION"] = {"200 OK", transmute([]byte)string("9.9.9\n")}
	routes_a["/SHA256SUMS"] = {"200 OK", transmute([]byte)fmt.aprintf("%s  %s\n", bad_checksum, binary_name)}
	routes_a[fmt.aprintf("/%s", binary_name)] = {"200 OK", bad_binary}

	fixture_a: UpgradeHttpFixture
	if !start_upgrade_http_fixture(t, &fixture_a, routes_a) { return }
	state_a, _, stderr_a, err_a := run_binary_with_env(installed_path, work.dir, {"upgrade"}, []string{fmt.aprintf("TUKAN_RELEASE_URL=%s", fixture_a.url)})
	stop_upgrade_http_fixture(&fixture_a)
	testing.expect(t, err_a == nil && state_a.exit_code == 1, "checksum mismatch must fail")
	testing.expectf(t, strings.contains(string(stderr_a), "Checksum verification failed"), "expected checksum error, got: %s", string(stderr_a))

	// (b) --version 9.9.9 vs VERSION 9.9.8
	routes_b := make(map[string]struct{status: string, body: []byte})
	routes_b["/VERSION"] = {"200 OK", transmute([]byte)string("9.9.8\n")}

	fixture_b: UpgradeHttpFixture
	if !start_upgrade_http_fixture(t, &fixture_b, routes_b) { return }
	state_b, _, stderr_b, err_b := run_binary_with_env(installed_path, work.dir, {"upgrade", "--version", "9.9.9"}, []string{fmt.aprintf("TUKAN_RELEASE_URL=%s", fixture_b.url)})
	stop_upgrade_http_fixture(&fixture_b)
	testing.expect(t, err_b == nil && state_b.exit_code == 1, "requested version mismatch must fail")
	testing.expectf(t, strings.contains(string(stderr_b), "Downloaded version does not match requested version"), "expected version mismatch error, got: %s", string(stderr_b))

	// (c) Valid checksum, but binary --version prints 9.9.8 instead of 9.9.9
	routes_c := make(map[string]struct{status: string, body: []byte})
	routes_c["/VERSION"] = {"200 OK", transmute([]byte)string("9.9.9\n")}
	routes_c["/SHA256SUMS"] = {"200 OK", transmute([]byte)fmt.aprintf("%s  %s\n", valid_checksum_of_bad_binary, binary_name)}
	routes_c[fmt.aprintf("/%s", binary_name)] = {"200 OK", bad_binary}

	fixture_c: UpgradeHttpFixture
	if !start_upgrade_http_fixture(t, &fixture_c, routes_c) { return }
	state_c, _, stderr_c, err_c := run_binary_with_env(installed_path, work.dir, {"upgrade"}, []string{fmt.aprintf("TUKAN_RELEASE_URL=%s", fixture_c.url)})
	stop_upgrade_http_fixture(&fixture_c)
	testing.expect(t, err_c == nil && state_c.exit_code == 1, "binary self-check version mismatch must fail")
	testing.expectf(t, strings.contains(string(stderr_c), "Binary version does not match release VERSION"), "expected binary version error, got: %s", string(stderr_c))

	// (d) HTTP 404 on /VERSION
	routes_d := make(map[string]struct{status: string, body: []byte})
	fixture_d: UpgradeHttpFixture
	if !start_upgrade_http_fixture(t, &fixture_d, routes_d) { return }
	state_d, _, stderr_d, err_d := run_binary_with_env(installed_path, work.dir, {"upgrade"}, []string{fmt.aprintf("TUKAN_RELEASE_URL=%s", fixture_d.url)})
	stop_upgrade_http_fixture(&fixture_d)
	testing.expect(t, err_d == nil && state_d.exit_code == 1, "HTTP 404 on VERSION must fail")
	testing.expectf(t, strings.contains(string(stderr_d), "Failed to download release VERSION"), "expected download VERSION error, got: %s", string(stderr_d))

	after_bytes, read_err := os.read_entire_file(installed_path, context.allocator)
	if testing.expect(t, read_err == nil, "existing binary should remain readable after failed upgrades") {
		testing.expect_value(t, string(after_bytes), string(original_bytes))
	}
	testing.expect(t, !has_leftover_temp_files(work.dir), "failed upgrades must clean up temporary files")
}

@(test)
upgrade_rejects_invalid_arguments :: proc(t: ^testing.T) {
	arena: virtual.Arena
	if !testing.expect(t, virtual.arena_init_growing(&arena) == nil, "arena should initialize") { return }
	defer virtual.arena_destroy(&arena)
	context.allocator = virtual.arena_allocator(&arena)

	work, ready := make_test_workspace(t)
	if !ready { return }
	defer os.remove_all(work.dir)

	cases := [?]struct { name: string, arguments: []string, expected: string }{
		{"missing version", {"upgrade", "--version"}, "Missing version for --version"},
		{"path traversal", {"upgrade", "--version", "../0.5.0"}, "Invalid version"},
		{"leading zero", {"upgrade", "--version", "01.0.0"}, "Invalid version"},
		{"repeated version", {"upgrade", "--version", "1.0.0", "--version", "2.0.0"}, "Option can only be specified once"},
		{"unknown option", {"upgrade", "--unknown"}, "Unknown option"},
		{"unexpected arg", {"upgrade", "extra"}, "Unexpected argument"},
	}

	for scenario in cases {
		state, _, stderr, run_err := run_cli(work, scenario.arguments)
		testing.expectf(t, run_err == nil && state.exit_code != 0, "%s: should fail", scenario.name)
		testing.expectf(t, strings.contains(string(stderr), scenario.expected), "%s: expected %q in stderr: %s", scenario.name, scenario.expected, string(stderr))
	}
}
