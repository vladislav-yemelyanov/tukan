package tests

import "core:fmt"
import "core:os"
import "core:strconv"
import "core:strings"
import "core:testing"

TestWorkspace :: struct {
	root: string,
	dir: string,
	binary: string,
}

// The caller owns the temporary directory and removes it after its assertions.
make_test_workspace :: proc(t: ^testing.T) -> (work: TestWorkspace, valid: bool) {
	root, root_err := os.get_working_directory(context.allocator)
	if !testing.expect(t, root_err == nil, "project directory should be available") { return }

	dir, dir_err := os.make_directory_temp("", "tukan-cli-*", context.allocator)
	if !testing.expect(t, dir_err == nil, "temporary directory should be created") { return }

	work = TestWorkspace{root = root, dir = dir}

	// The suite supplies a shared binary; standalone tests build their own copy.
	if binary := os.get_env("TUKAN_TEST_BINARY", context.allocator); len(binary) > 0 {
		work.binary = binary
		return work, true
	}

	work.binary = fmt.aprintf("%s/tukan", dir)
	args := [4]string{"odin", "build", "core", fmt.aprintf("-out:%s", work.binary)}
	build, stdout, stderr, err := os.process_exec({working_dir = root, command = args[:]}, context.allocator)
	if !testing.expectf(t, err == nil && build.exit_code == 0, "CLI build failed: %s%s", string(stdout), string(stderr)) {
		os.remove_all(dir)
		return
	}

	return work, true
}

run_cli :: proc(work: TestWorkspace, arguments: []string) -> (os.Process_State, []byte, []byte, os.Error) {
	command := make([dynamic]string)
	append(&command, work.binary)
	for argument in arguments { append(&command, argument) }

	return os.process_exec({working_dir = work.dir, command = command[:]}, context.allocator)
}

read_total_time_ms :: proc(output: string) -> (f64, bool) {
	label := "Total time: "
	for line in strings.split_lines(output) {
		if !strings.has_prefix(line, label) { continue }
		value := strings.trim_suffix(line[len(label):], " ms")
		return strconv.parse_f64(value)
	}
	return 0, false
}
