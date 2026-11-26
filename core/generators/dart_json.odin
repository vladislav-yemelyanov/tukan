package generators

import "core:encoding/json"
import "core:fmt"
import "core:strings"
import ir "../ir"

dart_json_key :: proc(key: string) -> string {
	literal, _ := json.marshal(json.String(key))
	escaped, _ := strings.replace_all(string(literal), "$", "\\$")
	return escaped
}

@(private)
is_dart_unknown :: proc(model: ir.Model, schemas: map[string]ir.Model) -> bool {
	current := model
	for _ in 0..=len(schemas) {
		switch value in current {
		case ir.UnknownModel:
			return true
		case ir.Reference:
			target, found := schemas[value.name]
			if !found { return false }
			current = target
		case ir.Primitive, ir.Enumeration, ir.ArrayModel, ir.ObjectModel:
			return false
		}
	}
	return false
}

@(private)
is_dart_passthrough_encode :: proc(model: ir.Model, schemas: map[string]ir.Model) -> bool {
	current := model
	for _ in 0..=len(schemas) {
		switch value in current {
		case ir.Primitive, ir.UnknownModel:
			return true
		case ir.ObjectModel:
			return len(value.fields) == 0 && value.additional_properties == nil
		case ir.Reference:
			target, found := schemas[value.name]
			if !found { return false }
			if _, is_obj := target.(ir.ObjectModel); is_obj { return false }
			current = target
		case ir.Enumeration, ir.ArrayModel:
			return false
		}
	}
	return false
}

@(private)
dart_json_decode :: proc(model: ir.Model, path, expression: string, nullable: bool, names: ^GeneratorNames, schemas: map[string]ir.Model) -> string {
	if is_dart_unknown(model, schemas) { return expression }
	if primitive, ok := model.(ir.Primitive); ok {
		is_binary := primitive.type == .string && primitive.format == "binary"
		if !is_binary {
			type_name := "String"
			switch primitive.type {
			case .string: type_name = "String"
			case .integer: type_name = "int"
			case .number: type_name = "num"
			case .boolean: type_name = "bool"
			}
			if nullable { return fmt.aprintf("%s as %s?", expression, type_name) }
			return fmt.aprintf("%s as %s", expression, type_name)
		}
	}
	if ref, ok := model.(ir.Reference); ok {
		target, found := schemas[ref.name]
		if !found { return expression }
		if _, is_obj := target.(ir.ObjectModel); !is_obj {
			target_path := child_path("schema", ref.name)
			return dart_json_decode(target, target_path, expression, nullable || model_nullable(model, schemas), names, schemas)
		}
	}
	if nullable {
		if strings.has_prefix(expression, "_requiredJson(") {
			return fmt.aprintf("switch (%s) {{ null => null, final value => %s }}", expression, dart_json_decode_nonnull(model, path, "value", names, schemas))
		}
		return fmt.aprintf("(%s == null ? null : %s)", expression, dart_json_decode_nonnull(model, path, expression, names, schemas))
	}
	return dart_json_decode_nonnull(model, path, expression, names, schemas)
}

@(private)
dart_json_decode_nonnull :: proc(model: ir.Model, path, expression: string, names: ^GeneratorNames, schemas: map[string]ir.Model) -> string {
	switch value in model {
	case ir.Primitive:
		if value.type == .string {
			if format, ok := value.format.?; ok && format == "binary" { return fmt.aprintf("(%s as List).cast<int>()", expression) }
			return fmt.aprintf("%s as String", expression)
		}
		switch value.type {
		case .string: return fmt.aprintf("%s as String", expression)
		case .integer: return fmt.aprintf("%s as int", expression)
		case .number: return fmt.aprintf("%s as num", expression)
		case .boolean: return fmt.aprintf("%s as bool", expression)
		}
	case ir.UnknownModel:
		return expression
	case ir.Enumeration:
		name := names.types[path]
		if backing, ok := names.types[child_path(path, "nullable")]; ok { name = backing }
		return fmt.aprintf("%s.fromJson(%s)", name, expression)
	case ir.Reference:
		target, found := schemas[value.name]
		if !found { return expression }
		target_path := child_path("schema", value.name)
		if _, is_obj := target.(ir.ObjectModel); is_obj {
			name := names.types[target_path]
			if backing, ok := names.types[child_path(target_path, "nullable")]; ok { name = backing }
			return fmt.aprintf("%s.fromJson(Map<String, dynamic>.from(%s as Map))", name, expression)
		}
		return dart_json_decode_nonnull(target, target_path, expression, names, schemas)
	case ir.ArrayModel:
		item_path := child_path(path, "items")
		item := dart_json_decode(value.items^, item_path, "item", model_nullable(value.items^, schemas), names, schemas)
		return fmt.aprintf("(%s as List).map((item) => %s).toList()", expression, item)
	case ir.ObjectModel:
		if len(value.fields) == 0 {
			if additional, ok := value.additional_properties.?; ok {
				item := dart_json_decode(additional^, child_path(path, "additionalProperties"), "value", model_nullable(additional^, schemas), names, schemas)
				return fmt.aprintf("(%s as Map).map((key, value) => MapEntry(key as String, %s))", expression, item)
			}
			return fmt.aprintf("Map<String, dynamic>.from(%s as Map)", expression)
		}
		fields := sorted_keys(value.fields)
		parts := make([dynamic]string)
		for field in fields {
			entry := value.fields[field]
			field_path := child_path(child_path(path, "fields"), field)
			field_name := names.fields[field_path]
			input := fmt.aprintf("_requiredJson(json, %s)", dart_json_key(field))
			if !entry.required { input = fmt.aprintf("json[%s]", dart_json_key(field)) }
			item := dart_json_decode(entry.model, field_path, input, !entry.required || model_nullable(entry.model, schemas), names, schemas)
			append(&parts, fmt.aprintf("%s: %s", field_name, item))
		}
		if additional, ok := value.additional_properties.?; ok {
			additional_name := names.additional_fields[path]
			keys := make([dynamic]string)
			for field in fields { append(&keys, dart_json_key(field)) }
			joined, _ := strings.join(keys[:], ", ")
			item := dart_json_decode(additional^, child_path(path, "additionalProperties"), "entry.value", model_nullable(additional^, schemas), names, schemas)
			append(&parts, fmt.aprintf("%s: {{for (final entry in json.entries) if (!<String>{{%s}}.contains(entry.key)) entry.key: %s}}", additional_name, joined, item))
		}
		joined, _ := strings.join(parts[:], ", ")
		return fmt.aprintf("((Map<String, dynamic> json) => (%s,))(Map<String, dynamic>.from(%s as Map))", joined, expression)
	}
	return expression
}

@(private)
dart_json_encode :: proc(model: ir.Model, path, expression: string, nullable_expr: bool, names: ^GeneratorNames, schemas: map[string]ir.Model, depth := 0) -> string {
	if is_dart_passthrough_encode(model, schemas) { return expression }
	if !nullable_expr { return dart_json_encode_nonnull(model, path, expression, names, schemas, depth) }

	switch value in model {
	case ir.Primitive, ir.UnknownModel:
		return expression
	case ir.Enumeration:
		return fmt.aprintf("%s?.value", expression)
	case ir.Reference:
		target, found := schemas[value.name]
		if !found { return expression }
		target_path := child_path("schema", value.name)
		if _, is_obj := target.(ir.ObjectModel); is_obj {
			return fmt.aprintf("%s?.toJson()", expression)
		}
		return dart_json_encode(target, target_path, expression, true, names, schemas, depth)
	case ir.ArrayModel:
		item_path := child_path(path, "items")
		item := dart_json_encode(value.items^, item_path, "item", model_nullable(value.items^, schemas), names, schemas, depth)
		return fmt.aprintf("%s?.map((item) => %s).toList()", expression, item)
	case ir.ObjectModel:
		if len(value.fields) == 0 {
			if additional, ok := value.additional_properties.?; ok {
				item := dart_json_encode(additional^, child_path(path, "additionalProperties"), "value", model_nullable(additional^, schemas), names, schemas, depth)
				return fmt.aprintf("%s?.map((key, value) => MapEntry(key, %s))", expression, item)
			}
			return expression
		}
		local := fmt.aprintf("_v%d", depth)
		return fmt.aprintf("switch (%s) {{ null => null, final %s => %s }}", expression, local, dart_json_encode_nonnull(model, path, local, names, schemas, depth + 1))
	}
	return expression
}

@(private)
dart_json_encode_nonnull :: proc(model: ir.Model, path, expression: string, names: ^GeneratorNames, schemas: map[string]ir.Model, depth := 0) -> string {
	switch value in model {
	case ir.Primitive, ir.UnknownModel:
		return expression
	case ir.Enumeration:
		return fmt.aprintf("%s.value", expression)
	case ir.Reference:
		target, found := schemas[value.name]
		if !found { return expression }
		target_path := child_path("schema", value.name)
		if _, is_obj := target.(ir.ObjectModel); is_obj {
			return fmt.aprintf("%s.toJson()", expression)
		}
		return dart_json_encode_nonnull(target, target_path, expression, names, schemas, depth)
	case ir.ArrayModel:
		item_path := child_path(path, "items")
		item := dart_json_encode(value.items^, item_path, "item", model_nullable(value.items^, schemas), names, schemas, depth)
		return fmt.aprintf("%s.map((item) => %s).toList()", expression, item)
	case ir.ObjectModel:
		if len(value.fields) == 0 {
			if additional, ok := value.additional_properties.?; ok {
				item := dart_json_encode(additional^, child_path(path, "additionalProperties"), "value", model_nullable(additional^, schemas), names, schemas, depth)
				return fmt.aprintf("%s.map((key, value) => MapEntry(key, %s))", expression, item)
			}
			return expression
		}
		fields := sorted_keys(value.fields)
		parts := make([dynamic]string)
		for field in fields {
			entry := value.fields[field]
			field_path := child_path(child_path(path, "fields"), field)
			field_name := names.fields[field_path]
			member := fmt.aprintf("%s.%s", expression, field_name)
			if !entry.required {
				if is_dart_passthrough_encode(entry.model, schemas) {
					append(&parts, fmt.aprintf("if (%s != null) %s: %s", member, dart_json_key(field), member))
				} else {
					local := fmt.aprintf("_v%d", depth)
					item := dart_json_encode_nonnull(entry.model, field_path, local, names, schemas, depth + 1)
					append(&parts, fmt.aprintf("if (%s case final %s?) %s: %s", member, local, dart_json_key(field), item))
				}
			} else {
				item := dart_json_encode(entry.model, field_path, member, model_nullable(entry.model, schemas), names, schemas, depth)
				append(&parts, fmt.aprintf("%s: %s", dart_json_key(field), item))
			}
		}
		if additional, ok := value.additional_properties.?; ok {
			additional_name := names.additional_fields[path]
			item := dart_json_encode(additional^, child_path(path, "additionalProperties"), "entry.value", model_nullable(additional^, schemas), names, schemas, depth)
			keys := make([dynamic]string)
			for field in fields { append(&keys, dart_json_key(field)) }
			joined, _ := strings.join(keys[:], ", ")
			append(&parts, fmt.aprintf("for (final entry in %s.%s.entries) if (!<String>{{%s}}.contains(entry.key)) entry.key: %s", expression, additional_name, joined, item))
		}
		joined, _ := strings.join(parts[:], ", ")
		return fmt.aprintf("{{%s}}", joined)
	}
	return expression
}

generate_dart_json :: proc(builder: ^strings.Builder, class_name: string, value: ir.ObjectModel, path: string, names: ^GeneratorNames, schemas: map[string]ir.Model) {
	fields := sorted_keys(value.fields)
	fmt.sbprintf(builder, "\n  factory %s.fromJson(Map<String, dynamic> json) => %s(\n", class_name, class_name)
	for field in fields {
		entry := value.fields[field]
		field_path := child_path(child_path(path, "fields"), field)
		input := fmt.aprintf("_requiredJson(json, %s)", dart_json_key(field))
		if !entry.required { input = fmt.aprintf("json[%s]", dart_json_key(field)) }
		item := dart_json_decode(entry.model, field_path, input, !entry.required || model_nullable(entry.model, schemas), names, schemas)
		fmt.sbprintf(builder, "    %s: %s,\n", names.fields[field_path], item)
	}
	if additional, ok := value.additional_properties.?; ok {
		keys := make([dynamic]string)
		for field in fields { append(&keys, dart_json_key(field)) }
		joined, _ := strings.join(keys[:], ", ")
		item := dart_json_decode(additional^, child_path(path, "additionalProperties"), "entry.value", model_nullable(additional^, schemas), names, schemas)
		fmt.sbprintf(builder, "    %s: {{for (final entry in json.entries) if (!<String>{{%s}}.contains(entry.key)) entry.key: %s}},\n", names.additional_fields[path], joined, item)
	}
	fmt.sbprintln(builder, "  );")
	fmt.sbprintln(builder, "\n  Map<String, dynamic> toJson() => {")
	if additional, ok := value.additional_properties.?; ok {
		item := dart_json_encode(additional^, child_path(path, "additionalProperties"), "entry.value", model_nullable(additional^, schemas), names, schemas)
		keys := make([dynamic]string)
		for field in fields { append(&keys, dart_json_key(field)) }
		joined, _ := strings.join(keys[:], ", ")
		fmt.sbprintf(builder, "    for (final entry in %s.entries) if (!<String>{{%s}}.contains(entry.key)) entry.key: %s,\n", names.additional_fields[path], joined, item)
	}
	for field in fields {
		entry := value.fields[field]
		field_path := child_path(child_path(path, "fields"), field)
		name := names.fields[field_path]
		if !entry.required {
			if is_dart_passthrough_encode(entry.model, schemas) {
				fmt.sbprintf(builder, "    if (this.%s != null) %s: this.%s,\n", name, dart_json_key(field), name)
			} else {
				item := dart_json_encode_nonnull(entry.model, field_path, "_v0", names, schemas, 1)
				fmt.sbprintf(builder, "    if (this.%s case final _v0?) %s: %s,\n", name, dart_json_key(field), item)
			}
		} else {
			item := dart_json_encode(entry.model, field_path, fmt.aprintf("this.%s", name), model_nullable(entry.model, schemas), names, schemas)
			fmt.sbprintf(builder, "    %s: %s,\n", dart_json_key(field), item)
		}
	}
	fmt.sbprintln(builder, "  };")
}
