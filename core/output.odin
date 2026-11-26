package main

import "core:fmt"
import "core:net"
import "core:os"
import "core:strings"
import "generators"
import "diagnostics"
import "ir"

OutputLanguage :: enum { typescript, dart }
OutputLanguages :: bit_set[OutputLanguage]

OutputFormat :: struct {
	name: string,
	extension: string,
	generate: proc(document: ^ir.Document, output_path: string, issues: ^diagnostics.Manager) -> os.Error,
}

output_format :: proc(language: OutputLanguage) -> OutputFormat {
	formats := [OutputLanguage]OutputFormat{
		.typescript = {"TypeScript", "ts", generators.generate_typescript},
		.dart = {"Dart", "dart", generators.generate_dart},
	}
	return formats[language]
}

parse_language :: proc(value: string) -> (OutputLanguage, bool) {
	switch value {
	case "ts", "typescript": return .typescript, true
	case "dart": return .dart, true
	}
	return {}, false
}

output_name :: proc(input: string) -> string {
	path := input
	if strings.has_prefix(input, "http://") || strings.has_prefix(input, "https://") {
		// Query parameters and fragments are not part of the specification's file name.
		_, _, url_path, _, _ := net.split_url(input)
		path = url_path
	}
	name := os.stem(path)
	if len(name) == 0 { return "spec" }
	return name
}

write_output :: proc(document: ^ir.Document, issues: ^diagnostics.Manager, language: OutputLanguage, output_dir, name: string) -> string {
	directory_error := os.make_directory_all(output_dir)
	// Linux mkdir_all can report Exist for a parent created by another generator.
	for directory_error == .Exist && !os.exists(output_dir) {
		directory_error = os.make_directory_all(output_dir)
	}
	if directory_error != nil && (directory_error != .Exist || !os.is_directory(output_dir)) {
		diagnostics.add(issues, "Failed to create output directory", fmt.aprintf("%s: %v", output_dir, directory_error))
		return ""
	}

	format := output_format(language)
	path, err := os.join_path([]string{output_dir, fmt.aprintf("%s.%s", name, format.extension)}, context.allocator)
	if err != nil {
		diagnostics.add(issues, fmt.aprintf("Failed to construct %s output path", format.name), fmt.aprint(err))
		return ""
	}
	if write_err := format.generate(document, path, issues); write_err != nil {
		if diagnostics.has_errors(issues) { return "" }
		diagnostics.add(issues, fmt.aprintf("Failed to write %s output", format.name), fmt.aprintf("%s: %v", path, write_err))
		return ""
	}
	return path
}
