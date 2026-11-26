package main

import "core:fmt"
import "core:strconv"
import "core:strings"
import "diagnostics"

CliOptions :: struct {
	input: string,
	input_list: string,
	config: string,
	output_dir: string,
	languages: OutputLanguages,
	concurrency: int,
	direct: bool,
}

parse_args :: proc(args: []string, issues: ^diagnostics.Manager) -> (options: CliOptions, valid: bool) {
	seen := make(map[string]bool)
	index := 0
	for index < len(args) {
		argument := args[index]
		key: string
		missing: string
		switch argument {
		case "-i", "--input": key, missing = "input", "Missing input file or URL"
		case "--input-list": key, missing = "input list", "Missing input list file"
		case "-c", "--config": key, missing = "config", "Missing configuration file"
		case "-l", "--lang": key, missing = "language", "Missing language list"
		case "-o", "--out", "--output": key, missing = "output directory", "Missing output directory"
		case "-j", "--concurrency": key, missing = "concurrency", "Missing concurrency value"
		case:
			if strings.has_prefix(argument, "-") {
				diagnostics.add(issues, "Unknown option", argument)
			} else {
				diagnostics.add(issues, "Unexpected argument", fmt.aprintf("%s (run tukan init, or use -i <file-or-url>)", argument))
			}
			return
		}

		if seen[key] {
			switch key {
			case "input": diagnostics.add(issues, "Input can only be specified once")
			case "language": diagnostics.add(issues, "Language option can only be specified once")
			case "output directory": diagnostics.add(issues, "Output directory can only be specified once")
			case: diagnostics.add(issues, "Option can only be specified once", argument)
			}
			return
		}
		if index + 1 >= len(args) || len(args[index + 1]) == 0 || strings.has_prefix(args[index + 1], "-") {
			if key == "language" && index + 1 < len(args) && args[index + 1] == "" {
				diagnostics.add(issues, "Unsupported output language", "Empty language list")
			} else {
				diagnostics.add(issues, missing, argument)
			}
			return
		}

		seen[key] = true
		value := args[index + 1]
		switch key {
		case "input": options.input = value
		case "input list": options.input_list = value
		case "config": options.config = value
		case "output directory": options.output_dir = value
		case "concurrency":
			count, ok := strconv.parse_int(value)
			if !ok || count < 1 || count > 64 {
				diagnostics.add(issues, "Concurrency must be an integer from 1 to 64", value)
				return
			}
			options.concurrency = count
		case "language":
			for name in strings.split(value, ",") {
				language, ok := parse_language(name)
				if !ok {
					diagnostics.add(issues, "Unsupported output language", fmt.aprintf("%q (choose ts or dart)", name))
					return
				}
				options.languages += {language}
			}
		}
		index += 2
	}

	if len(options.input) > 0 && len(options.input_list) > 0 {
		diagnostics.add(issues, "Choose either --input or --input-list")
		return
	}
	if len(options.config) > 0 && (len(options.input) > 0 || len(options.input_list) > 0) {
		diagnostics.add(issues, "Configuration cannot be combined with --input or --input-list")
		return
	}
	options.direct = len(options.config) == 0 && (seen["input"] || seen["input list"] || seen["language"] || seen["output directory"])
	if options.direct && options.languages == {} {
		diagnostics.add(issues, "Missing required language option", "Use -l ts,dart for direct input, or run tukan with a configuration file")
		return
	}
	return options, true
}

print_help :: proc() {
	fmt.println("Usage: tukan [--config file] | tukan init")
	fmt.println("  -v, --version  Show the build version; used alone.")
	fmt.println("  tukan init  Create tukan.json5 without replacing an existing file.")
	fmt.println("  tukan       Generate types using tukan.json5 in the current directory.")
	fmt.println("  -c, --config  Use another configuration file.")
	fmt.println("  -j, --concurrency  Maximum concurrent tasks, from 1 to 64. Default: 4.")
	fmt.println("Direct usage: tukan -l languages [-i file-or-url | --input-list file] [-o directory]")
	fmt.println("  -i, --input   Specification file or URL. Default for direct usage: spec.json.")
	fmt.println("  --input-list  Text file with one specification path or URL per non-empty line.")
	fmt.println("  -l, --lang    Required output languages for direct usage: ts (or typescript), dart. Separate multiple languages with commas.")
	fmt.println("  -o, --output  Output directory. Default for direct usage: tukan-output.")
	fmt.println("With --config, --lang and --output override every specification; --concurrency overrides the task limit.")
}
