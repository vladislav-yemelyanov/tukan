package main

import "base:runtime"
import "core:c"
import "core:fmt"
import virtual "core:mem/virtual"
import "core:os"
import "core:strings"
import "core:time"
import "diagnostics"
import curl "vendor:curl"

@(private)
CurlResponseBuffer :: struct {
	ctx: runtime.Context,
	body: [dynamic]byte,
	alloc_failed: bool,
}

is_http_url :: proc(input: string) -> bool {
	return strings.has_prefix(input, "http://") || strings.has_prefix(input, "https://")
}

@(private)
config_has_http_input :: proc(config: ^Config) -> bool {
	for spec in config.specs {
		if is_http_url(spec.input) { return true }
	}
	return false
}

@(private)
curl_write_body :: proc "c" (buffer: [^]byte, size: c.size_t, nitems: c.size_t, userdata: rawptr) -> c.size_t {
	state := cast(^CurlResponseBuffer)userdata
	context = state.ctx

	if size == 0 || nitems == 0 { return 0 }
	if nitems > max(c.size_t) / size {
		state.alloc_failed = true
		return 0
	}

	total := size * nitems
	if uint(total) > uint(max(int)) {
		state.alloc_failed = true
		return 0
	}

	if _, err := append(&state.body, ..buffer[:int(total)]); err != nil {
		state.alloc_failed = true
		return 0
	}
	return total
}

@(private)
curl_error_detail :: proc(err: curl.code, error_buffer: []u8) -> string {
	if len(error_buffer) > 0 && error_buffer[0] != 0 {
		trimmed := strings.trim_space(string(cstring(raw_data(error_buffer))))
		if len(trimmed) > 0 { return trimmed }
	}
	return string(curl.easy_strerror(err))
}

@(private)
set_curl_option :: proc(handle: ^curl.CURL, option: curl.option, value: $T, url: string, error_title: string, issues: ^diagnostics.Manager) -> bool {
	if err := curl.easy_setopt(handle, option, value); err != .E_OK {
		diagnostics.add(issues, error_title, fmt.aprintf("%s: %s", url, curl.easy_strerror(err)))
		return false
	}
	return true
}

@(private)
fetch_http_bytes :: proc(
	url: string,
	error_title: string,
	issues: ^diagnostics.Manager,
	severity := diagnostics.Severity.error,
	timeout_seconds: c.long = 60,
) -> ([]byte, bool) {
	// The HTTP client does not strip fragments, which must never reach the server.
	request_url := url
	if index := strings.index_byte(request_url, '#'); index >= 0 {
		request_url = request_url[:index]
	}

	handle := curl.easy_init()
	if handle == nil {
		diagnostics.add(issues, error_title, fmt.aprintf("%s: failed to initialize HTTP handle", url))
		return nil, false
	}
	defer curl.easy_cleanup(handle)

	request_url_cstr := strings.clone_to_cstring(request_url)
	defer delete(request_url_cstr)

	response := CurlResponseBuffer{ctx = context}
	error_buffer: [curl.ERROR_SIZE]u8

	write_fn: curl.write_callback = curl_write_body
	if !set_curl_option(handle, .URL, request_url_cstr, url, error_title, issues) ||
	   !set_curl_option(handle, .WRITEFUNCTION, write_fn, url, error_title, issues) ||
	   !set_curl_option(handle, .WRITEDATA, &response, url, error_title, issues) ||
	   !set_curl_option(handle, .ERRORBUFFER, raw_data(error_buffer[:]), url, error_title, issues) ||
	   !set_curl_option(handle, .FOLLOWLOCATION, c.long(1), url, error_title, issues) ||
	   !set_curl_option(handle, .MAXREDIRS, c.long(10), url, error_title, issues) ||
	   !set_curl_option(handle, .NOSIGNAL, c.long(1), url, error_title, issues) ||
	   !set_curl_option(handle, .CONNECTTIMEOUT, c.long(15), url, error_title, issues) ||
	   !set_curl_option(handle, .TIMEOUT, timeout_seconds, url, error_title, issues) ||
	   !set_curl_option(handle, .ACCEPT_ENCODING, cstring(""), url, error_title, issues) {
		delete(response.body)
		return nil, false
	}

	if perform_err := curl.easy_perform(handle); perform_err != .E_OK {
		delete(response.body)
		if response.alloc_failed {
			diagnostics.add(issues, "Failed to read response body", fmt.aprintf("%s: out of memory", url))
		} else {
			diagnostics.add(issues, error_title, fmt.aprintf("%s: %s", url, curl_error_detail(perform_err, error_buffer[:])), severity = severity)
		}
		return nil, false
	}

	status_code: c.long
	if info_err := curl.easy_getinfo(handle, .RESPONSE_CODE, &status_code); info_err != .E_OK {
		delete(response.body)
		diagnostics.add(issues, error_title, fmt.aprintf("%s: %s", url, curl.easy_strerror(info_err)), severity = severity)
		return nil, false
	}

	if status_code < 200 || status_code >= 300 {
		delete(response.body)
		diagnostics.add(issues, error_title, fmt.aprintf("%s: HTTP %d", url, status_code), severity = severity)
		return nil, false
	}

	return response.body[:], true
}

read_spec_from_swagger :: proc(url: string, issues: ^diagnostics.Manager, severity := diagnostics.Severity.error) -> ([]byte, bool) {
	return fetch_http_bytes(url, "Failed to fetch specification", issues, severity)
}

read_spec_from_file :: proc(path: string, issues: ^diagnostics.Manager, severity := diagnostics.Severity.error) -> ([]byte, bool) {
	file, err := os.read_entire_file(path, context.allocator)

	if err != nil {
		diagnostics.add(issues, "Failed to read specification", fmt.aprintf("%s: %v", path, err), severity = severity)
		return nil, false
	}

	return file, true
}

run :: proc() -> int {
	started := time.tick_now()
	arena: virtual.Arena
	if err := virtual.arena_init_growing(&arena); err != nil {
		fmt.eprintln("error: Failed to initialize memory arena:", err)
		return 1
	}
	defer virtual.arena_destroy(&arena)
	context.allocator = virtual.arena_allocator(&arena)
	issues: diagnostics.Manager

	args := os.args[1:]
	if len(args) == 1 && (args[0] == "-v" || args[0] == "--version") {
		fmt.printf("Tukan %s\n", strings.trim_space(BUILD_VERSION))
		return 0
	}
	if len(args) == 1 && (args[0] == "-h" || args[0] == "--help") {
		print_help()
		return 0
	}
	if len(args) == 1 && args[0] == "init" {
		if create_config(&issues) { return 0 }
		fmt.eprintf("Diagnostics\n\n%s", diagnostics.format(&issues))
		return 1
	}
	if len(args) >= 1 && args[0] == "upgrade" {
		if run_upgrade(args[1:], &issues) { return 0 }
		fmt.eprintf("Diagnostics\n\n%s", diagnostics.format(&issues))
		return 1
	}

	defer {
		fmt.printf("\nTotal time: %.3f ms\n", time.duration_milliseconds(time.tick_since(started)))
	}

	options, valid := parse_args(args, &issues)
	if valid {
		config, ready := prepare_config(options, &issues)
		if ready && validate_output_paths(&config, &issues) {
			http_ready := false
			if config_has_http_input(&config) {
				if err := curl.global_init(curl.GLOBAL_DEFAULT); err != .E_OK {
					diagnostics.add(&issues, "Failed to initialize HTTP client", string(curl.easy_strerror(err)))
					fmt.eprintf("Diagnostics\n\n%s", diagnostics.format(&issues))
					return 1
				}
				http_ready = true
			}
			defer if http_ready { curl.global_cleanup() }

			if !process_specs(&config) { return 1 }
		}
	}

	if len(issues.issues) > 0 { fmt.eprintf("Diagnostics\n\n%s", diagnostics.format(&issues)) }
	if diagnostics.has_errors(&issues) { return 1 }
	return 0
}

main :: proc() {
	code := run()
	if code != 0 { os.exit(code) }
}
