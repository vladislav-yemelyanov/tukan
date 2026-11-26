package generators

import "core:encoding/json"
import "core:fmt"
import "core:os"
import "core:slice"
import "core:strings"
import ir "../ir"
import "../diagnostics"

dart_nullable_type :: proc(name: string, nullable: bool) -> string {
	if nullable && name != "dynamic" && !strings.has_suffix(name, "?") {
		return fmt.aprintf("%s?", name)
	}

	return name
}

enum_type :: proc(value: ir.Enumeration) -> string {
	base_type := "Object?"
	if len(value.values) > 0 {
		first := value.values[0]
		switch first in first {
		case json.String: base_type = "String"
		case json.Integer: base_type = "int"
		case json.Float: base_type = "num"
		case json.Boolean: base_type = "bool"
		case json.Null, json.Array, json.Object:
		}
	}

	// Mixed integer/float enums share num; unrelated value types require Object?.
	for item in value.values {
		switch item in item {
		case json.String: if base_type != "String" { base_type = "Object?" }
		case json.Integer: if base_type != "int" && base_type != "num" { base_type = "Object?" }
		case json.Float:
			if base_type == "int" {
				base_type = "num"
			} else if base_type != "num" {
				base_type = "Object?"
			}
		case json.Boolean: if base_type != "bool" { base_type = "Object?" }
		case json.Null, json.Array, json.Object: base_type = "Object?"
		}
	}

	base_type = dart_nullable_type(base_type, value.nullable)
	return base_type
}

model_type :: proc(model: ir.Model, path: string, names: ^GeneratorNames, schemas: map[string]ir.Model) -> string {
	switch value in model {
	case ir.Primitive:
		name := "dynamic"
		switch value.type {
		case .string:
			name = "String"
			if format, ok := value.format.?; ok && format == "binary" {
				name = "List<int>"
			}
		case .number: name = "num"
		case .integer: name = "int"
		case .boolean: name = "bool"
		}

		return dart_nullable_type(name, value.nullable)

	case ir.Enumeration:
		return dart_nullable_type(names.types[path], value.nullable)

	case ir.Reference:
		return dart_nullable_type(names.types[child_path("schema", value.name)], value.nullable)

	case ir.ArrayModel:
		return dart_nullable_type(fmt.aprintf("List<%s>", model_type(value.items^, child_path(path, "items"), names, schemas)), value.nullable)

	case ir.ObjectModel:
		if len(value.fields) == 0 {
			if additional, ok := value.additional_properties.?; ok {
				return dart_nullable_type(fmt.aprintf("Map<String, %s>", model_type(additional^, child_path(path, "additionalProperties"), names, schemas)), value.nullable)
			}

			return dart_nullable_type("Map<String, dynamic>", value.nullable)
		}

		fields := make([dynamic]string)
		for field in value.fields { append(&fields, field) }
		slice.sort(fields[:])

		parts := make([dynamic]string)
		has_comments := false
		for field in fields {
			entry := value.fields[field]
			field_type := model_type(entry.model, child_path(child_path(path, "fields"), field), names, schemas)
			if !entry.required && !model_nullable(entry.model, schemas) {
				field_type = dart_nullable_type(field_type, true)
			}

			comment := annotation_comment(entry.model, .dart)
			if comment != "" { has_comments = true }
			append(&parts, fmt.aprintf("%s%s %s", comment, field_type, names.fields[child_path(child_path(path, "fields"), field)]))
		}

		if additional, ok := value.additional_properties.?; ok {
			additional_type := model_type(additional^, child_path(path, "additionalProperties"), names, schemas)
			append(&parts, fmt.aprintf("Map<String, %s> %s", additional_type, names.additional_fields[path]))
		}

		if has_comments {
			for part, index in parts {
				indented, _ := strings.replace_all(part, "\n", "\n  ")
				parts[index] = fmt.aprintf("  %s", indented)
			}
			field_types, _ := strings.join(parts[:], ",\n")
			return dart_nullable_type(fmt.aprintf("({{\n%s\n}})", field_types), value.nullable)
		}
		field_types, _ := strings.join(parts[:], ", ")
		return dart_nullable_type(fmt.aprintf("({{%s}})", field_types), value.nullable)

	case ir.UnknownModel:
		return "dynamic"
	}

	return "dynamic"
}

@(private)
dart_uses_deep_equality :: proc(model: ir.Model, schemas: map[string]ir.Model) -> bool {
	current := model
	for _ in 0..=len(schemas) {
		switch value in current {
		case ir.Reference:
			target, found := schemas[value.name]
			if !found { return false }
			if _, is_obj := target.(ir.ObjectModel); is_obj { return false }
			current = target
		case ir.ArrayModel, ir.UnknownModel, ir.ObjectModel:
			return true
		case ir.Primitive:
			if format, ok := value.format.?; ok && format == "binary" { return true }
			return false
		case ir.Enumeration:
			return false
		}
	}
	return false
}

generate_enum :: proc(builder: ^strings.Builder, name: string, value: ir.Enumeration) {
	if len(value.values) == 0 {
		fmt.sbprintf(builder, "abstract final class %s {{\n", name)
		fmt.sbprintf(builder, "  static %s fromJson(Object? json) => throw FormatException('No enum values');\n", name)
		fmt.sbprintln(builder, "  Object? get value;")
		fmt.sbprintln(builder, "}\n")
		return
	}

	fmt.sbprintf(builder, "enum %s {{\n", name)
	used := make(map[string]bool)
	used["value"] = true
	used["values"] = true
	used["name"] = true
	used["index"] = true
	used["fromJson"] = true
	used["toJson"] = true
	used["hashCode"] = true
	used["runtimeType"] = true
	used["toString"] = true
	used["noSuchMethod"] = true
	for item, index in value.values {
		literal, err := json.marshal(item)
		if err != nil { continue }

		// JSON strings do not escape Dart's interpolation marker.
		escaped, _ := strings.replace_all(string(literal), "$", "\\$")
		separator := ","
		if index == len(value.values) - 1 { separator = ";" }
		base := fmt.aprintf("value%d", index)
		if text, ok := item.(json.String); ok { base = readable_name(string(text), true) }
		if base == name { base = fmt.aprintf("%sValue", base) }
		member := allocate_name(&used, base)
		fmt.sbprintf(builder, "  %s(%s)%s\n", member, escaped, separator)
	}

	fmt.sbprintf(builder, "\n  final %s value;\n", enum_type(value))
	fmt.sbprintf(builder, "  const %s(this.value);\n", name)
	fmt.sbprintf(builder, "  static %s fromJson(Object? json) => values.firstWhere((item) => _deepEqual(item.value, json), orElse: () => throw FormatException('Invalid enum value: $json'));\n", name)
	fmt.sbprintln(builder, "  Object? toJson() => value;")
	fmt.sbprintln(builder, "}\n")
}

generate_inline_enums :: proc(builder: ^strings.Builder, model: ir.Model, path: string, names: ^GeneratorNames) {
	switch value in model {
	case ir.Enumeration:
		generate_enum(builder, names.types[path], value)
	case ir.ArrayModel:
		generate_inline_enums(builder, value.items^, child_path(path, "items"), names)
	case ir.ObjectModel:
		fields := make([dynamic]string)
		for field in value.fields { append(&fields, field) }
		slice.sort(fields[:])

		for field in fields {
			generate_inline_enums(builder, value.fields[field].model, child_path(child_path(path, "fields"), field), names)
		}

		if additional, ok := value.additional_properties.?; ok {
			generate_inline_enums(builder, additional^, child_path(path, "additionalProperties"), names)
		}
	case ir.Primitive, ir.Reference, ir.UnknownModel:
	}
}

@(private)
generate_dart_class_helpers :: proc(builder: ^strings.Builder, class_name: string, value: ir.ObjectModel, path: string, fields: []string, names: ^GeneratorNames, schemas: map[string]ir.Model) {
	if len(fields) > 0 || value.additional_properties != nil {
		fmt.sbprintf(builder, "\n  %s copyWith({{\n", class_name)
		for field in fields {
			entry := value.fields[field]
			field_path := child_path(child_path(path, "fields"), field)
			field_name := names.fields[field_path]
			field_type := model_type(entry.model, field_path, names, schemas)
			if !entry.required && !model_nullable(entry.model, schemas) {
				field_type = dart_nullable_type(field_type, true)
			}
			is_nullable := !entry.required || model_nullable(entry.model, schemas)
			if is_nullable {
				fmt.sbprintf(builder, "    Object? %s = _unset,\n", field_name)
			} else {
				fmt.sbprintf(builder, "    %s %s,\n", dart_nullable_type(field_type, true), field_name)
			}
		}
		if additional, ok := value.additional_properties.?; ok {
			additional_type := model_type(additional^, child_path(path, "additionalProperties"), names, schemas)
			fmt.sbprintf(builder, "    Map<String, %s>? %s,\n", additional_type, names.additional_fields[path])
		}
		fmt.sbprintf(builder, "  }}) => %s(\n", class_name)
		for field in fields {
			entry := value.fields[field]
			field_path := child_path(child_path(path, "fields"), field)
			field_name := names.fields[field_path]
			field_type := model_type(entry.model, field_path, names, schemas)
			if !entry.required && !model_nullable(entry.model, schemas) {
				field_type = dart_nullable_type(field_type, true)
			}
			is_nullable := !entry.required || model_nullable(entry.model, schemas)
			if is_nullable {
				if field_type == "dynamic" {
					fmt.sbprintf(builder, "    %s: identical(%s, _unset) ? this.%s : %s,\n", field_name, field_name, field_name, field_name)
				} else {
					fmt.sbprintf(builder, "    %s: identical(%s, _unset) ? this.%s : %s as %s,\n", field_name, field_name, field_name, field_name, field_type)
				}
			} else {
				fmt.sbprintf(builder, "    %s: %s ?? this.%s,\n", field_name, field_name, field_name)
			}
		}
		if _, ok := value.additional_properties.?; ok {
			additional_name := names.additional_fields[path]
			fmt.sbprintf(builder, "    %s: %s ?? this.%s,\n", additional_name, additional_name, additional_name)
		}
		fmt.sbprintln(builder, "  );")
	}

	comparisons := make([dynamic]string)
	append(&comparisons, fmt.aprintf("other is %s", class_name))
	append(&comparisons, "other.runtimeType == runtimeType")
	hash_items := make([dynamic]string)
	append(&hash_items, "runtimeType")

	for field in fields {
		entry := value.fields[field]
		field_path := child_path(child_path(path, "fields"), field)
		field_name := names.fields[field_path]
		if dart_uses_deep_equality(entry.model, schemas) {
			append(&comparisons, fmt.aprintf("_deepEqual(this.%s, other.%s)", field_name, field_name))
			append(&hash_items, fmt.aprintf("_deepHash(this.%s)", field_name))
		} else {
			append(&comparisons, fmt.aprintf("this.%s == other.%s", field_name, field_name))
			append(&hash_items, fmt.aprintf("this.%s", field_name))
		}
	}
	if _, ok := value.additional_properties.?; ok {
		additional_name := names.additional_fields[path]
		append(&comparisons, fmt.aprintf("_deepEqual(this.%s, other.%s)", additional_name, additional_name))
		append(&hash_items, fmt.aprintf("_deepHash(this.%s)", additional_name))
	}

	joined_comparisons, _ := strings.join(comparisons[:], " && ")
	fmt.sbprintln(builder)
	fmt.sbprintln(builder, "  @override")
	fmt.sbprintf(builder, "  bool operator ==(Object other) => identical(this, other) || %s;\n", joined_comparisons)
	fmt.sbprintln(builder)
	fmt.sbprintln(builder, "  @override")
	if len(hash_items) == 1 {
		fmt.sbprintln(builder, "  int get hashCode => runtimeType.hashCode;")
	} else if len(hash_items) <= 20 {
		joined_hash, _ := strings.join(hash_items[:], ", ")
		fmt.sbprintf(builder, "  int get hashCode => Object.hash(%s);\n", joined_hash)
	} else {
		joined_hash, _ := strings.join(hash_items[:], ", ")
		fmt.sbprintf(builder, "  int get hashCode => Object.hashAll([%s]);\n", joined_hash)
	}
}

generate_dart :: proc(document: ^ir.Document, output_path := "spec.dart", issues: ^diagnostics.Manager = nil) -> os.Error {
	projected := project_directions(document)
	document := &projected
	if !validate_generation(document, issues, .dart) { return os.General_Error.Invalid_File }

	builder := strings.builder_make()
	defer strings.builder_destroy(&builder)

	fmt.sbprintln(&builder, "// Generated from OpenAPI schemas; defaults not applied.")
	fmt.sbprintln(&builder)

	fmt.sbprintln(&builder, "// ignore: unused_element")
	fmt.sbprintln(&builder, "const Object _unset = Object();\n")
	fmt.sbprintln(&builder, "// ignore: unused_element")
	fmt.sbprintln(&builder, "bool _deepEqual(Object? a, Object? b) {")
	fmt.sbprintln(&builder, "  if (identical(a, b)) return true;")
	fmt.sbprintln(&builder, "  if (a is List && b is List) {")
	fmt.sbprintln(&builder, "    if (a.length != b.length) return false;")
	fmt.sbprintln(&builder, "    for (var i = 0; i < a.length; i++) {")
	fmt.sbprintln(&builder, "      if (!_deepEqual(a[i], b[i])) return false;")
	fmt.sbprintln(&builder, "    }")
	fmt.sbprintln(&builder, "    return true;")
	fmt.sbprintln(&builder, "  }")
	fmt.sbprintln(&builder, "  if (a is Map && b is Map) {")
	fmt.sbprintln(&builder, "    if (a.length != b.length) return false;")
	fmt.sbprintln(&builder, "    for (final key in a.keys) {")
	fmt.sbprintln(&builder, "      if (!b.containsKey(key) || !_deepEqual(a[key], b[key])) return false;")
	fmt.sbprintln(&builder, "    }")
	fmt.sbprintln(&builder, "    return true;")
	fmt.sbprintln(&builder, "  }")
	fmt.sbprintln(&builder, "  return a == b;")
	fmt.sbprintln(&builder, "}\n")
	fmt.sbprintln(&builder, "// ignore: unused_element")
	fmt.sbprintln(&builder, "int _deepHash(Object? value) {")
	fmt.sbprintln(&builder, "  if (value is List) return Object.hashAll(value.map(_deepHash));")
	fmt.sbprintln(&builder, "  if (value is Map) return Object.hashAllUnordered(value.entries.map((entry) => Object.hash(entry.key, _deepHash(entry.value))));")
	fmt.sbprintln(&builder, "  return value.hashCode;")
	fmt.sbprintln(&builder, "}\n")
	fmt.sbprintln(&builder, "// ignore: unused_element")
	fmt.sbprintln(&builder, "Object? _requiredJson(Map<String, dynamic> json, String key) {")
	fmt.sbprintln(&builder, "  if (!json.containsKey(key)) throw FormatException('Missing required property: $key');")
	fmt.sbprintln(&builder, "  return json[key];")
	fmt.sbprintln(&builder, "}\n")

	dart_schemas := make(map[string]ir.Model)
	for name, model in document.schemas { dart_schemas[name] = model }
	bindings := make(map[string]map[string]OperationBinding)
	generate_operation_types(&dart_schemas, document, &bindings)

	schema_names := make([dynamic]string)
	for name in dart_schemas { append(&schema_names, name) }
	slice.sort(schema_names[:])

	names := build_generator_names(dart_schemas)
	for name in schema_names {
		model := dart_schemas[name]
		path := child_path("schema", name)
		fmt.sbprint(&builder, annotation_comment(model, .dart))

		switch value in model {
		case ir.ObjectModel:
			class_name := names.types[path]
			if value.nullable {
				// Dart classes cannot be nullable declarations; expose a nullable alias instead.
				class_name = names.types[child_path(path, "nullable")]
				fmt.sbprintf(&builder, "typedef %s = %s?;\n", names.types[path], class_name)
			}

			fmt.sbprintf(&builder, "// Schema: %q\nclass %s {{\n", name, class_name)
			fields := sorted_keys(value.fields)

			for field in fields {
				entry := value.fields[field]
				field_path := child_path(child_path(path, "fields"), field)
				field_type := model_type(entry.model, field_path, &names, dart_schemas)
				if !entry.required && !model_nullable(entry.model, dart_schemas) {
					field_type = dart_nullable_type(field_type, true)
				}

				field_name := names.fields[field_path]
				if field_name != field { fmt.sbprintf(&builder, "  // Property: %s\n", dart_json_key(field)) }
				fmt.sbprintf(&builder, "%s  final %s %s;\n", annotation_comment(entry.model, .dart, "  "), field_type, field_name)
			}

			if additional, ok := value.additional_properties.?; ok {
				additional_type := model_type(additional^, child_path(path, "additionalProperties"), &names, dart_schemas)
				fmt.sbprintf(&builder, "  final Map<String, %s> %s;\n", additional_type, names.additional_fields[path])
			}

			if len(fields) == 0 && value.additional_properties == nil {
				fmt.sbprintf(&builder, "\n  const %s();\n", class_name)
				generate_dart_json(&builder, class_name, value, path, &names, dart_schemas)
				generate_dart_class_helpers(&builder, class_name, value, path, fields[:], &names, dart_schemas)
				fmt.sbprintln(&builder, "}\n")
				continue
			}
			fmt.sbprintf(&builder, "\n  const %s({{\n", class_name)
			for field in fields {
				field_name := names.fields[child_path(child_path(path, "fields"), field)]
				if value.fields[field].required {
					fmt.sbprintf(&builder, "    required this.%s,\n", field_name)
				} else {
					fmt.sbprintf(&builder, "    this.%s,\n", field_name)
				}
			}

			if _, ok := value.additional_properties.?; ok {
				fmt.sbprintf(&builder, "    this.%s = const {{}},\n", names.additional_fields[path])
			}
			fmt.sbprintln(&builder, "  });")
			generate_dart_json(&builder, class_name, value, path, &names, dart_schemas)
			generate_dart_class_helpers(&builder, class_name, value, path, fields[:], &names, dart_schemas)
			fmt.sbprintln(&builder, "}\n")

		case ir.Enumeration:
			fmt.sbprintf(&builder, "// Schema: %q\n", name)
			enum_name := names.types[path]
			if value.nullable {
				enum_name = names.types[child_path(path, "nullable")]
				fmt.sbprintf(&builder, "typedef %s = %s?;\n", names.types[path], enum_name)
			}

			generate_enum(&builder, enum_name, value)

		case ir.Primitive, ir.Reference, ir.ArrayModel, ir.UnknownModel:
			fmt.sbprintf(&builder, "// Schema: %q\ntypedef %s = %s;\n\n", name, names.types[path], model_type(model, path, &names, dart_schemas))
		}

		if _, is_enum := model.(ir.Enumeration); !is_enum {
			generate_inline_enums(&builder, model, path, &names)
		}
	}

	emit_dart_paths(&builder, document, dart_schemas, &names, bindings)

	return os.write_entire_file(output_path, strings.to_string(builder))
}
