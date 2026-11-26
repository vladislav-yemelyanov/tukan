package main

import "core:crypto/hash"
import "core:encoding/hex"
import "core:fmt"
import "core:os"
import "core:strings"
import "diagnostics"
import curl "vendor:curl"

UpgradeOptions :: struct {
	version: string,
}

@(private)
is_ascii_digit :: proc(b: u8) -> bool {
	return b >= '0' && b <= '9'
}

@(private)
is_semver_ident_char :: proc(b: u8) -> bool {
	return is_ascii_digit(b) || (b >= 'A' && b <= 'Z') || (b >= 'a' && b <= 'z') || b == '-'
}

@(private)
is_semver_numeric_ident :: proc(part: string) -> bool {
	if len(part) == 0 { return false }
	for i in 0 ..< len(part) {
		if !is_ascii_digit(part[i]) { return false }
	}
	return len(part) == 1 || part[0] != '0'
}

@(private)
is_valid_semver :: proc(version: string) -> bool {
	if len(version) == 0 { return false }

	rest := version
	if plus := strings.index_byte(rest, '+'); plus >= 0 {
		build := rest[plus + 1:]
		rest = rest[:plus]
		if len(build) == 0 { return false }
		for part in strings.split(build, ".") {
			if len(part) == 0 { return false }
			for i in 0 ..< len(part) {
				if !is_semver_ident_char(part[i]) { return false }
			}
		}
	}

	if dash := strings.index_byte(rest, '-'); dash >= 0 {
		prerelease := rest[dash + 1:]
		rest = rest[:dash]
		if len(prerelease) == 0 { return false }
		for part in strings.split(prerelease, ".") {
			if len(part) == 0 { return false }
			all_digits := true
			for i in 0 ..< len(part) {
				if !is_semver_ident_char(part[i]) { return false }
				if !is_ascii_digit(part[i]) { all_digits = false }
			}
			if all_digits && len(part) > 1 && part[0] == '0' { return false }
		}
	}

	parts := strings.split(rest, ".")
	if len(parts) != 3 { return false }
	for part in parts {
		if !is_semver_numeric_ident(part) { return false }
	}
	return true
}

@(private)
parse_upgrade_args :: proc(args: []string, issues: ^diagnostics.Manager) -> (options: UpgradeOptions, valid: bool) {
	seen_version := false
	index := 0
	for index < len(args) {
		argument := args[index]
		if argument != "--version" {
			if strings.has_prefix(argument, "-") {
				diagnostics.add(issues, "Unknown option", argument)
			} else {
				diagnostics.add(issues, "Unexpected argument", argument)
			}
			return
		}
		if seen_version {
			diagnostics.add(issues, "Option can only be specified once", argument)
			return
		}
		if index + 1 >= len(args) || len(args[index + 1]) == 0 || strings.has_prefix(args[index + 1], "-") {
			diagnostics.add(issues, "Missing version for --version", argument)
			return
		}
		raw_version := args[index + 1]
		trimmed := strings.trim_prefix(raw_version, "v")
		if !is_valid_semver(trimmed) {
			diagnostics.add(issues, "Invalid version", fmt.aprintf("%s. Use SemVer, for example 0.5.0 or v0.5.0.", raw_version))
			return
		}
		seen_version = true
		options.version = trimmed
		index += 2
	}
	return options, true
}

@(private)
upgrade_binary_name :: proc() -> (string, bool) {
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
is_hex_sha256 :: proc(value: string) -> bool {
	if len(value) != 64 { return false }
	for i in 0 ..< len(value) {
		ch := value[i]
		if !((ch >= '0' && ch <= '9') || (ch >= 'a' && ch <= 'f') || (ch >= 'A' && ch <= 'F')) {
			return false
		}
	}
	return true
}

@(private)
find_expected_checksum :: proc(checksums_text, binary_name: string) -> (string, bool) {
	for raw_line in strings.split_lines(checksums_text) {
		line := strings.trim_space(raw_line)
		if len(line) == 0 { continue }

		split_at := -1
		for i in 0 ..< len(line) {
			if line[i] == ' ' || line[i] == '\t' {
				split_at = i
				break
			}
		}
		if split_at <= 0 { continue }

		digest := line[:split_at]
		if !is_hex_sha256(digest) { continue }

		name := strings.trim_left(line[split_at:], " \t")
		name = strings.trim_prefix(name, "*")
		if name == binary_name {
			return strings.to_lower(digest), true
		}
	}
	return "", false
}

@(private)
resolve_release_base_url :: proc(requested_version: string) -> string {
	if release_url := os.get_env("TUKAN_RELEASE_URL", context.allocator); len(release_url) > 0 {
		return strings.trim_right(release_url, "/")
	}
	repo := os.get_env("TUKAN_REPO", context.allocator)
	if len(repo) == 0 { repo = "vladislav-yemelyanov/tukan" }
	if len(requested_version) > 0 {
		return fmt.aprintf("https://github.com/%s/releases/download/v%s", repo, requested_version)
	}
	return fmt.aprintf("https://github.com/%s/releases/latest/download", repo)
}

@(private)
write_all :: proc(file: ^os.File, data: []byte) -> os.Error {
	written_total := 0
	for written_total < len(data) {
		n, err := os.write(file, data[written_total:])
		if err != nil { return err }
		if n == 0 { return .Unexpected_EOF }
		written_total += n
	}
	return nil
}

run_upgrade :: proc(args: []string, issues: ^diagnostics.Manager) -> bool {
	options, valid := parse_upgrade_args(args, issues)
	if !valid { return false }

	binary_name, supported := upgrade_binary_name()
	if !supported {
		diagnostics.add(issues, "Unsupported platform for upgrade", "Tukan release binaries support macOS and Linux (arm64, amd64).")
		return false
	}

	exe_path, exe_err := os.get_executable_path(context.allocator)
	if exe_err != nil || len(exe_path) == 0 {
		diagnostics.add(issues, "Failed to locate current Tukan executable", fmt.aprint(exe_err))
		return false
	}

	if err := curl.global_init(curl.GLOBAL_DEFAULT); err != .E_OK {
		diagnostics.add(issues, "Failed to initialize HTTP client", string(curl.easy_strerror(err)))
		return false
	}
	defer curl.global_cleanup()

	base_url := resolve_release_base_url(options.version)

	version_bytes, version_ok := fetch_http_bytes(fmt.aprintf("%s/VERSION", base_url), "Failed to download release VERSION", issues)
	if !version_ok { return false }
	defer delete(version_bytes)

	target_version := strings.trim_space(string(version_bytes))
	if !is_valid_semver(target_version) {
		diagnostics.add(issues, "Invalid release version", fmt.aprintf("%q", target_version))
		return false
	}
	if len(options.version) > 0 && target_version != options.version {
		diagnostics.add(issues, "Downloaded version does not match requested version", fmt.aprintf("expected %s, got %s; existing installation was kept", options.version, target_version))
		return false
	}

	current_version := strings.trim_space(BUILD_VERSION)
	if target_version == current_version {
		fmt.printf("Tukan %s is already up to date.\n", current_version)
		return true
	}

	sums_bytes, sums_ok := fetch_http_bytes(fmt.aprintf("%s/SHA256SUMS", base_url), "Failed to download release checksums", issues)
	if !sums_ok { return false }
	defer delete(sums_bytes)

	expected_checksum, found_checksum := find_expected_checksum(string(sums_bytes), binary_name)
	if !found_checksum {
		diagnostics.add(issues, "Missing checksum for platform binary", binary_name)
		return false
	}

	binary_bytes, binary_ok := fetch_http_bytes(fmt.aprintf("%s/%s", base_url, binary_name), "Failed to download release binary", issues, timeout_seconds = 120)
	if !binary_ok { return false }
	defer delete(binary_bytes)

	actual_digest := hash.hash_bytes(.SHA256, binary_bytes)
	actual_hex := strings.to_lower(string(hex.encode(actual_digest)))
	if actual_hex != expected_checksum {
		diagnostics.add(issues, "Checksum verification failed", fmt.aprintf("%s: existing installation was kept", binary_name))
		return false
	}

	exe_dir := os.dir(exe_path)
	temp_file, create_err := os.create_temp_file(exe_dir, ".tukan-upgrade-*")
	if create_err != nil {
		diagnostics.add(issues, "Failed to stage upgraded binary", fmt.aprintf("%s: %v", exe_dir, create_err))
		return false
	}
	temp_path := strings.clone(os.name(temp_file))
	staged := true
	defer if staged { os.remove(temp_path) }

	write_err := write_all(temp_file, binary_bytes)
	close_err := os.close(temp_file)
	if write_err != nil || close_err != nil {
		err_detail := write_err if write_err != nil else close_err
		diagnostics.add(issues, "Failed to write upgraded binary", fmt.aprintf("%s: %v", temp_path, err_detail))
		return false
	}

	exec_mode := os.Permissions_Read_All + {.Write_User} + os.Permissions_Execute_All
	if chmod_err := os.chmod(temp_path, exec_mode); chmod_err != nil {
		diagnostics.add(issues, "Failed to set executable permissions", fmt.aprintf("%s: %v", temp_path, chmod_err))
		return false
	}

	state, stdout, stderr, exec_err := os.process_exec({command = []string{temp_path, "--version"}}, context.allocator)
	if exec_err != nil || state.exit_code != 0 {
		diagnostics.add(issues, "Downloaded binary failed to run", fmt.aprintf("%s: %v %s", binary_name, exec_err, strings.trim_space(string(stderr))))
		return false
	}

	expected_banner := fmt.aprintf("Tukan %s", target_version)
	if strings.trim_space(string(stdout)) != expected_banner {
		diagnostics.add(issues, "Binary version does not match release VERSION", fmt.aprintf("expected %q, got %q; existing installation was kept", expected_banner, strings.trim_space(string(stdout))))
		return false
	}

	if rename_err := os.rename(temp_path, exe_path); rename_err != nil {
		diagnostics.add(issues, "Failed to replace existing executable", fmt.aprintf("%s: %v", exe_path, rename_err))
		return false
	}
	staged = false

	fmt.printf("Updated Tukan %s -> %s (%s)\n", current_version, target_version, exe_path)
	return true
}
