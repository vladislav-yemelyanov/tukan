package generators

import "core:fmt"
import "core:strings"
import "core:unicode"
import ir "../ir"

@(private)
GeneratorNames :: struct {
	types: map[string]string,
	fields: map[string]string,
	additional_fields: map[string]string,
}

@(private)
dart_keywords :: "|abstract|as|assert|async|await|base|bool|break|case|catch|class|const|continue|covariant|default|deferred|do|double|dynamic|else|enum|export|extends|extension|external|factory|false|final|finally|for|Function|get|hide|if|implements|import|in|int|interface|is|late|library|mixin|new|null|num|on|operator|part|required|rethrow|return|sealed|set|show|static|String|super|switch|sync|this|throw|true|try|typedef|var|void|while|with|yield|"

@(private)
name_letter :: proc(letter: rune) -> bool {
	return (letter >= 'a' && letter <= 'z') || (letter >= 'A' && letter <= 'Z')
}

@(private)
safe_name :: proc(name: string) -> bool {
	if len(name) == 0 { return false }
	if strings.contains(dart_keywords, fmt.aprintf("|%s|", name)) { return false }

	for letter, index in name {
		if name_letter(letter) { continue }
		if letter == '_' && index > 0 { continue }
		if index > 0 && letter >= '0' && letter <= '9' { continue }
		return false
	}
	return true
}

@(private)
readable_name :: proc(name: string, field := false) -> string {
	builder := strings.builder_make()
	defer strings.builder_destroy(&builder)
	pascal_case := !field
	capitalize := pascal_case
	for character in name {
		letter := character
		is_digit := letter >= '0' && letter <= '9'
		if !name_letter(letter) && !is_digit {
			capitalize = true
			continue
		}
		if strings.builder_len(builder) == 0 {
			if is_digit {
				if pascal_case { fmt.sbprint(&builder, "Type") } else { fmt.sbprint(&builder, "field") }
			} else if !pascal_case {
				letter = unicode.to_lower(letter)
				capitalize = false
			}
		}
		if capitalize { letter = unicode.to_upper(letter) }
		strings.write_rune(&builder, letter)
		capitalize = false
	}
	if strings.builder_len(builder) == 0 {
		if field {
			fmt.sbprint(&builder, "field")
		} else {
			fmt.sbprint(&builder, "Schema")
		}
	}
	result := strings.clone(strings.to_string(builder))
	if !safe_name(result) { result = fmt.aprintf("%sValue", result) }
	return result
}

@(private)
allocate_name :: proc(used: ^map[string]bool, base: string) -> string {
	name := base
	for suffix := 2; used^[name]; suffix += 1 { name = fmt.aprintf("%s%d", base, suffix) }
	used^[name] = true
	return name
}

@(private)
collect_model_names :: proc(names: ^GeneratorNames, used_types: ^map[string]bool, model: ir.Model, path, base: string) {
	switch value in model {
	case ir.ArrayModel:
		collect_inline_names(names, used_types, value.items^, child_path(path, "items"), fmt.aprintf("%sItem", base))
	case ir.ObjectModel:
		used_fields := make(map[string]bool)
		for member in ([8]string{"fromJson", "toJson", "copyWith", "identical", "hashCode", "runtimeType", "toString", "noSuchMethod"}) { used_fields[member] = true }
		class_name := names.types[path]
		if backing, ok := names.types[child_path(path, "nullable")]; ok { class_name = backing }
		if len(class_name) > 0 { used_fields[class_name] = true }
		reserved_fields := make(map[string]bool)
		for name in used_fields { reserved_fields[name] = true }
		fields := sorted_keys(value.fields)
		// Prefer names that already match, then normalized names.
		for preserve in ([2]bool{true, false}) {
			for field in fields {
				valid := safe_name(field) && !reserved_fields[field]
				if len(field) > 0 && field[0] >= 'A' && field[0] <= 'Z' { valid = false }
				if valid != preserve { continue }
				candidate := field
				if !valid { candidate = readable_name(field, true) }
				field_path := child_path(child_path(path, "fields"), field)
				names.fields[field_path] = allocate_name(&used_fields, candidate)
			}
		}
		if _, ok := value.additional_properties.?; ok {
			names.additional_fields[path] = allocate_name(&used_fields, "additionalProperties")
		}
		for field in fields {
			field_path := child_path(child_path(path, "fields"), field)
			collect_inline_names(names, used_types, value.fields[field].model, field_path, fmt.aprintf("%s%s", base, readable_name(field)))
		}
		if additional, ok := value.additional_properties.?; ok {
			collect_inline_names(names, used_types, additional^, child_path(path, "additionalProperties"), fmt.aprintf("%sAdditionalProperty", base))
		}
	case ir.Primitive, ir.Reference, ir.Enumeration, ir.UnknownModel:
	}
}

@(private)
collect_inline_names :: proc(names: ^GeneratorNames, used_types: ^map[string]bool, model: ir.Model, path, base: string) {
	if _, is_enum := model.(ir.Enumeration); is_enum {
		names.types[path] = allocate_name(used_types, enum_type_name(base, model))
	}
	collect_model_names(names, used_types, model, path, base)
}

@(private)
build_generator_names :: proc(schemas: map[string]ir.Model) -> GeneratorNames {
	names := GeneratorNames{types = make(map[string]string), fields = make(map[string]string), additional_fields = make(map[string]string)}
	used_types := make(map[string]bool)
	for name in ([5]string{"List", "Map", "Object", "Set", "Iterable"}) { used_types[name] = true }
	reserved_types := make(map[string]bool)
	for name in used_types { reserved_types[name] = true }
	keys := sorted_keys(schemas)
	for preserve in ([2]bool{true, false}) {
		for name in keys {
			valid := safe_name(name) && !reserved_types[name] && enum_type_name(name, schemas[name]) == name
			if valid != preserve { continue }
			candidate := name
			if !valid { candidate = readable_name(name) }
			candidate = enum_type_name(candidate, schemas[name])
			names.types[child_path("schema", name)] = allocate_name(&used_types, candidate)
		}
	}
	// Backing classes for nullable Dart declarations share the same namespace as all other types.
	for name in keys {
		needs_backing := false
		switch value in schemas[name] {
		case ir.ObjectModel: needs_backing = value.nullable
		case ir.Enumeration: needs_backing = value.nullable
		case ir.Primitive, ir.Reference, ir.ArrayModel, ir.UnknownModel:
		}
		if !needs_backing { continue }
		path := child_path("schema", name)
		base := fmt.aprintf("%sValue", names.types[path])
		names.types[child_path(path, "nullable")] = allocate_name(&used_types, base)
	}
	for name in keys {
		collect_model_names(&names, &used_types, schemas[name], child_path("schema", name), readable_name(name))
	}
	return names
}

@(private)
enum_type_name :: proc(base: string, model: ir.Model) -> string {
	value, is_enum := model.(ir.Enumeration)
	if !is_enum { return base }
	if base == "value" { return "valueEnum" }
	for _, index in value.values {
		if base == fmt.aprintf("value%d", index) { return fmt.aprintf("%sEnum", base) }
	}
	return base
}

child_path :: proc(path, field: string) -> string {
	// Length prefixes distinguish field names containing path separators.
	return fmt.aprintf("%s/%d:%s", path, len(field), field)
}
