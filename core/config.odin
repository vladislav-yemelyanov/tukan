package main

import "core:encoding/json"
import "core:fmt"
import "core:os"
import "core:strings"
import "diagnostics"

OutputTarget :: struct {
	language: OutputLanguage,
	output_dir: string,
}

SpecOptions :: struct {
	name: string,
	input: string,
	output_dir: string,
	languages: OutputLanguages,
	targets: [dynamic]OutputTarget,
	explicit_outputs: bool,
}

Config :: struct {
	specs: [dynamic]SpecOptions,
	concurrency: int,
}

config_template :: `{
  // Maximum concurrent downloads, parsing tasks, and language generators.
  concurrency: 4,

  // Each specification inherits these settings and can override them.
  defaults: {
    languages: ["ts"],
    output: "./src/generated",
  },

  specs: [
    {
      // Output: src/generated/api.ts. Change this name to identify your API.
      name: "api",
      // A local OpenAPI JSON file or an http:// or https:// URL.
      // Relative paths are resolved from this configuration file's directory.
      input: "./openapi.json",
      // languages: ["ts", "dart"],
      // output: "./another/output",
      // Or target different directories per language with outputs:
      // outputs: [
      //   { language: "ts", path: "./web/src/generated" },
      //   { language: "dart", path: "./mobile/lib/generated" },
      // ],
    },
    // Add more specification objects here. Each is processed independently.
  ],
}
`

create_config :: proc(issues: ^diagnostics.Manager) -> bool {
	file, err := os.open("tukan.json5", os.O_WRONLY | os.O_CREATE | os.O_EXCL)
	if err != nil {
		diagnostics.add(issues, "Could not create tukan.json5; existing files are never overwritten", fmt.aprint(err))
		return false
	}
	defer os.close(file)

	written, write_err := os.write(file, transmute([]byte)string(config_template))
	if write_err != nil || written != len(config_template) {
		diagnostics.add(issues, "Failed to write configuration", fmt.aprint(write_err))
		return false
	}
	fmt.println("Created tukan.json5. Set your specification paths or URLs, then run tukan.")
	return true
}

check_config_keys :: proc(source: json.Object, allowed: []string, issues: ^diagnostics.Manager, path: string) {
	for name in source {
		found := false
		for key in allowed {
			if name == key { found = true; break }
		}
		if !found { diagnostics.add(issues, "Unknown configuration field", name, diagnostics.child_path(path, name)) }
	}
}

append_language_targets :: proc(targets: ^[dynamic]OutputTarget, languages: OutputLanguages, output_dir: string) {
	for language in languages {
		append(targets, OutputTarget{language = language, output_dir = output_dir})
	}
}

clone_targets :: proc(source: [dynamic]OutputTarget) -> (cloned: [dynamic]OutputTarget) {
	for target in source {
		append(&cloned, target)
	}
	return
}

read_outputs_list :: proc(source: json.Value, issues: ^diagnostics.Manager, path: string) -> (targets: [dynamic]OutputTarget) {
	entries, is_array := source.(json.Array)
	if !is_array || len(entries) == 0 {
		diagnostics.add(issues, "Expected a non-empty outputs array", "Provide { language, path } entries", path)
		return
	}

	for item, index in entries {
		item_path := fmt.aprintf("%s/%d", path, index)
		entry, is_object := item.(json.Object)
		if !is_object {
			diagnostics.add(issues, "Output target must be an object", "", item_path)
			continue
		}
		check_config_keys(entry, {"language", "path"}, issues, item_path)

		language_value, has_language := entry["language"]
		language_text, is_lang_string := language_value.(json.String)
		language, known := parse_language(string(language_text))
		if !has_language || !is_lang_string {
			diagnostics.add(issues, "Expected a language string (ts or dart)", "", diagnostics.child_path(item_path, "language"))
		} else if !known {
			diagnostics.add(issues, "Unsupported output language", "Choose ts or dart", diagnostics.child_path(item_path, "language"))
		}

		dir_value, has_dir := entry["path"]
		dir_text, is_dir_string := dir_value.(json.String)
		trimmed_dir := strings.trim_space(string(dir_text))
		if !has_dir || !is_dir_string || len(trimmed_dir) == 0 {
			diagnostics.add(issues, "Expected a non-empty output path", "", diagnostics.child_path(item_path, "path"))
			continue
		}

		if has_language && is_lang_string && known {
			append(&targets, OutputTarget{language = language, output_dir = string(dir_text)})
		}
	}
	return
}

read_spec_settings :: proc(source: json.Object, inherited: SpecOptions, issues: ^diagnostics.Manager, path: string) -> (settings: SpecOptions) {
	settings = inherited
	outputs_value, has_outputs := source["outputs"]
	_, has_output := source["output"]
	_, has_languages := source["languages"]

	if has_outputs && (has_output || has_languages) {
		diagnostics.add(issues, "Cannot combine outputs with output or languages", "", diagnostics.child_path(path, "outputs"))
	} else if has_outputs {
		settings.explicit_outputs = true
		settings.targets = read_outputs_list(outputs_value, issues, diagnostics.child_path(path, "outputs"))
	} else if has_output || has_languages {
		if inherited.explicit_outputs {
			settings.explicit_outputs = false
			settings.targets = {}
			settings.languages = {.typescript}
			settings.output_dir = "./src/generated"
		}
	} else if inherited.explicit_outputs {
		settings.targets = clone_targets(inherited.targets)
	}

	for name, value in source {
		field_path := diagnostics.child_path(path, name)
		switch name {
		case "name", "input", "output":
			if has_outputs && name == "output" { continue }
			text, ok := value.(json.String)
			if !ok || len(strings.trim_space(string(text))) == 0 {
				diagnostics.add(issues, "Expected a non-empty string", name, field_path)
				continue
			}
			switch name {
			case "name": settings.name = string(text)
			case "input": settings.input = string(text)
			case "output": settings.output_dir = string(text)
			}
		case "languages":
			if has_outputs { continue }
			values, ok := value.(json.Array)
			if !ok || len(values) == 0 {
				diagnostics.add(issues, "Expected a non-empty language array", "Use ts or dart", field_path)
				continue
			}
			// An explicit list replaces the inherited languages instead of merging them.
			settings.languages = {}
			for item, index in values {
				text, is_string := item.(json.String)
				language, known := parse_language(string(text))
				if !is_string || !known {
					diagnostics.add(issues, "Unsupported output language", "Choose ts or dart", fmt.aprintf("%s/%d", field_path, index))
					continue
				}
				settings.languages += {language}
			}
		}
	}
	return
}

resolve_config_path :: proc(base, path: string, issues: ^diagnostics.Manager) -> string {
	joined := path
	if !os.is_absolute_path(path) {
		value, err := os.join_path([]string{base, path}, context.allocator)
		if err != nil {
			diagnostics.add(issues, "Failed to resolve path", path)
			return ""
		}
		joined = value
	}
	if !os.is_absolute_path(joined) {
		cwd, err := os.get_working_directory(context.allocator)
		if err != nil {
			diagnostics.add(issues, "Failed to read working directory", fmt.aprint(err))
			return ""
		}
		joined, _ = os.join_path([]string{cwd, joined}, context.allocator)
	}
	absolute, err := os.clean_path(joined, context.allocator)
	if err != nil {
		diagnostics.add(issues, "Failed to resolve path", joined)
		return ""
	}
	return absolute
}

read_config :: proc(path: string, issues: ^diagnostics.Manager) -> (config: Config, valid: bool) {
	data, err := os.read_entire_file(path, context.allocator)
	if err != nil {
		diagnostics.add(issues, "Failed to read configuration", fmt.aprintf("%s: %v. Run tukan init to create tukan.json5.", path, err))
		return
	}
	defer delete(data)

	value: json.Value
	if decode_err := json.unmarshal(data, &value, .JSON5); decode_err != nil {
		diagnostics.add(issues, "Failed to parse configuration JSON5", fmt.aprintf("%s: %v", path, decode_err))
		return
	}
	source, ok := value.(json.Object)
	if !ok {
		diagnostics.add(issues, "Configuration must be an object", path)
		return
	}
	check_config_keys(source, {"concurrency", "defaults", "specs"}, issues, "#")
	config.concurrency = 4
	if count_value, found := source["concurrency"]; found {
		count, is_integer := count_value.(json.Integer)
		if !is_integer || count < 1 || count > 64 {
			diagnostics.add(issues, "Concurrency must be an integer from 1 to 64", "", "#/concurrency")
		} else {
			config.concurrency = int(count)
		}
	}

	defaults := SpecOptions{languages = {.typescript}, output_dir = "./src/generated"}
	if defaults_value, found := source["defaults"]; found {
		settings, is_object := defaults_value.(json.Object)
		if !is_object {
			diagnostics.add(issues, "Defaults must be an object", "", "#/defaults")
		} else {
			check_config_keys(settings, {"languages", "output", "outputs"}, issues, "#/defaults")
			defaults = read_spec_settings(settings, defaults, issues, "#/defaults")
		}
	}

	entries, is_array := source["specs"].(json.Array)
	if !is_array || len(entries) == 0 {
		diagnostics.add(issues, "Configuration requires a non-empty specs array", "", "#/specs")
		return
	}
	base := os.dir(resolve_config_path(".", path, issues))
	for entry, index in entries {
		entry_path := fmt.aprintf("#/specs/%d", index)
		settings, is_object := entry.(json.Object)
		if !is_object {
			diagnostics.add(issues, "Specification settings must be an object", "", entry_path)
			continue
		}
		check_config_keys(settings, {"name", "input", "output", "languages", "outputs"}, issues, entry_path)
		spec := read_spec_settings(settings, defaults, issues, entry_path)
		if len(spec.input) == 0 {
			diagnostics.add(issues, "Specification input is required", "", diagnostics.child_path(entry_path, "input"))
			continue
		}
		if !strings.has_prefix(spec.input, "http://") && !strings.has_prefix(spec.input, "https://") {
			spec.input = resolve_config_path(base, spec.input, issues)
		}
		if spec.explicit_outputs {
			for &target in spec.targets {
				target.output_dir = resolve_config_path(base, target.output_dir, issues)
			}
		} else {
			spec.output_dir = resolve_config_path(base, spec.output_dir, issues)
			spec.targets = {}
			append_language_targets(&spec.targets, spec.languages, spec.output_dir)
		}
		if len(spec.name) == 0 { spec.name = output_name(spec.input) }
		append(&config.specs, spec)
	}
	return config, !diagnostics.has_errors(issues)
}

prepare_config :: proc(options: CliOptions, issues: ^diagnostics.Manager) -> (config: Config, valid: bool) {
	if !options.direct {
		path := options.config
		if len(path) == 0 { path = "tukan.json5" }
		config, valid = read_config(path, issues)
		if !valid { return }

		override_dir := ""
		if len(options.output_dir) > 0 {
			override_dir = resolve_config_path(".", options.output_dir, issues)
		}
		for &spec in config.specs {
			if options.languages != {} && len(override_dir) > 0 {
				clear(&spec.targets)
				append_language_targets(&spec.targets, options.languages, override_dir)
			} else if len(override_dir) > 0 {
				used: OutputLanguages
				for target in spec.targets { used += {target.language} }
				clear(&spec.targets)
				append_language_targets(&spec.targets, used, override_dir)
			} else if options.languages != {} {
				if spec.explicit_outputs {
					filtered: [dynamic]OutputTarget
					for target in spec.targets {
						if target.language in options.languages {
							append(&filtered, target)
						}
					}
					spec.targets = filtered
				} else {
					clear(&spec.targets)
					append_language_targets(&spec.targets, options.languages, spec.output_dir)
				}
			}
		}
	} else {
		config.concurrency = 4
		output := options.output_dir
		if len(output) == 0 { output = "tukan-output" }
		output = resolve_config_path(".", output, issues)
		inputs := make([dynamic]string)
		if len(options.input_list) > 0 {
			data, err := os.read_entire_file(options.input_list, context.allocator)
			if err != nil {
				diagnostics.add(issues, "Failed to read input list", fmt.aprintf("%s: %v", options.input_list, err))
				return
			}
			defer delete(data)
			base := os.dir(resolve_config_path(".", options.input_list, issues))
			for line in strings.split(strings.trim_prefix(string(data), "\xef\xbb\xbf"), "\n") {
				input := strings.trim_space(line)
				if len(input) == 0 { continue }
				if strings.has_prefix(input, "http://") || strings.has_prefix(input, "https://") {
					input = strings.clone(input)
				} else {
					input = resolve_config_path(base, input, issues)
				}
				append(&inputs, input)
			}
			if len(inputs) == 0 {
				diagnostics.add(issues, "Input list contains no specifications", options.input_list)
				return
			}
		} else {
			input := options.input
			if len(input) == 0 { input = "spec.json" }
			append(&inputs, input)
		}
		for input in inputs {
			spec := SpecOptions{input = input, name = output_name(input), output_dir = output, languages = options.languages}
			append_language_targets(&spec.targets, options.languages, output)
			append(&config.specs, spec)
		}
	}
	if options.concurrency > 0 { config.concurrency = options.concurrency }
	return config, !diagnostics.has_errors(issues)
}

// Resolve existing ancestors so aliases through directory symlinks cannot write the same file.
output_path_key :: proc(path: string, issues: ^diagnostics.Manager) -> string {
	ancestor := path
	suffix := ""
	for !os.exists(ancestor) {
		parent := os.dir(ancestor)
		if parent == ancestor { break }
		_, name := os.split_path(ancestor)
		if len(suffix) == 0 {
			suffix = name
		} else {
			suffix, _ = os.join_path([]string{name, suffix}, context.allocator)
		}
		ancestor = parent
	}
	canonical, err := os.get_absolute_path(ancestor, context.allocator)
	if err != nil {
		diagnostics.add(issues, "Failed to resolve output path", fmt.aprintf("%s: %v", path, err))
		return ""
	}
	if len(suffix) == 0 {
		info, stat_err := os.stat(canonical, context.allocator)
		if stat_err == nil && info.inode != 0 && info.type == .Regular {
			return fmt.aprintf("file:%d:%d", info.device, info.inode)
		}
	}
	key := canonical
	if len(suffix) > 0 { key, _ = os.join_path([]string{canonical, suffix}, context.allocator) }
	when ODIN_OS == .Darwin || ODIN_OS == .Windows { key = strings.to_lower(key) }
	return key
}

validate_output_paths :: proc(config: ^Config, issues: ^diagnostics.Manager) -> bool {
	paths := make(map[string]string)
	inputs := make(map[string]string)
	for spec in config.specs {
		if strings.has_prefix(spec.input, "http://") || strings.has_prefix(spec.input, "https://") { continue }
		path := resolve_config_path(".", spec.input, issues)
		key := output_path_key(path, issues)
		if len(key) > 0 { inputs[key] = spec.input }
	}
	for spec in config.specs {
		if len(spec.name) == 0 || spec.name == "." || spec.name == ".." || strings.contains_any(spec.name, "/\\\x00\r\n") {
			diagnostics.add(issues, "Specification name must be a file name without path separators", spec.name)
			continue
		}
		for target in spec.targets {
			path, err := os.join_path([]string{target.output_dir, fmt.aprintf("%s.%s", spec.name, output_format(target.language).extension)}, context.allocator)
			if err != nil {
				diagnostics.add(issues, "Failed to construct output path", spec.name)
				continue
			}
			key := output_path_key(path, issues)
			if len(key) == 0 { continue }
			if input, exists := inputs[key]; exists {
				diagnostics.add(issues, "Output would overwrite an input specification", fmt.aprintf("%s: %s", path, input))
			}
			if previous, exists := paths[key]; exists {
				diagnostics.add(issues, "Conflicting output path", fmt.aprintf("%s: %s and %s. Set distinct names or output directories.", path, previous, spec.input))
			} else {
				paths[key] = spec.input
			}
		}
	}
	return !diagnostics.has_errors(issues)
}
