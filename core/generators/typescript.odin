package generators

import "core:encoding/json"
import "core:fmt"
import "core:os"
import "core:slice"
import "core:strings"
import ir "../ir"
import "../diagnostics"

nullable_type :: proc(value: string, nullable: bool) -> string {
	if nullable && value != "unknown" {
		return fmt.aprintf("%s | null", value)
	}

	return value
}

model_to_ts :: proc(model: ir.Model, indent := 0) -> string {
	switch value in model {
	case ir.Primitive:
		result := "unknown"
		switch value.type {
		case .string:
			result = "string"
			if format, ok := value.format.?; ok && format == "binary" {
				result = "Blob"
			}
		case .number, .integer:
			result = "number"
		case .boolean:
			result = "boolean"
		}

		return nullable_type(result, value.nullable)

	case ir.Enumeration:
		if len(value.values) == 0 {
			return nullable_type("never", value.nullable)
		}

		parts := make([dynamic]string)
		for item in value.values {
			switch item in item {
			case json.String:
				append(&parts, fmt.aprintf("%q", string(item)))
			case json.Integer, json.Float, json.Boolean, json.Null, json.Array, json.Object:
				literal, err := json.marshal(item)
				if err != nil {
					return nullable_type("unknown", value.nullable)
				}

				append(&parts, string(literal))
			}
		}

		result, _ := strings.join(parts[:], " | ")
		return nullable_type(result, value.nullable)

	case ir.Reference:
		return nullable_type(fmt.aprintf("Schemas[%q]", value.name), value.nullable)

	case ir.ArrayModel:
		item := model_to_ts(value.items^, indent)
		if ts_array_item_needs_parens(value.items^) {
			return nullable_type(fmt.aprintf("(%s)[]", item), value.nullable)
		}
		return nullable_type(fmt.aprintf("%s[]", item), value.nullable)

	case ir.ObjectModel:
		if len(value.fields) == 0 && value.additional_properties == nil {
			return nullable_type("{}", value.nullable)
		}

		indentation := strings.repeat("  ", indent)
		field_indentation := strings.repeat("  ", indent + 1)
		parts := make([dynamic]string)
		properties := make([dynamic]string)
		for property in value.fields {
			append(&properties, property)
		}
		slice.sort(properties[:])

		for property in properties {
			field := value.fields[property]
			optional := "?"
			if field.required {
				optional = ""
			}

			comment := annotation_comment(field.model, .typescript, field_indentation)
			if comment != "" { append(&parts, strings.trim_suffix(comment, "\n")) }

			append(
				&parts,
				fmt.aprintf(
					"%s%q%s: %s;",
					field_indentation,
					property,
					optional,
					model_to_ts(field.model, indent + 1),
				),
			)
		}

		if additional_properties, ok := value.additional_properties.?; ok {
			// TypeScript requires every named property to fit the index signature too.
			// Optional properties add undefined to the permitted values.
			index_types := make([dynamic]string)
			index_base := model_to_ts(additional_properties^, indent + 1)
			append(&index_types, index_base)
			for property in properties {
				if index_base == "unknown" { break }
				field := value.fields[property]
				field_type := model_to_ts(field.model, indent + 1)
				if !slice.contains(index_types[:], field_type) { append(&index_types, field_type) }
				if !field.required && !slice.contains(index_types[:], "undefined") { append(&index_types, "undefined") }
			}

			index_type, _ := strings.join(index_types[:], " | ")
			append(
				&parts,
				fmt.aprintf(
					"%s[key: string]: %s;",
					field_indentation,
					index_type,
				),
			)
		}

		fields, _ := strings.join(parts[:], "\n")
		return nullable_type(fmt.aprintf("{{\n%s\n%s}}", fields, indentation), value.nullable)

	case ir.UnknownModel:
		return nullable_type("unknown", value.nullable)
	}

	return "unknown"
}

@(private)
ts_array_item_needs_parens :: proc(model: ir.Model) -> bool {
	switch value in model {
	case ir.Primitive: return value.nullable
	case ir.Reference: return value.nullable
	case ir.ArrayModel: return value.nullable
	case ir.ObjectModel: return value.nullable
	case ir.Enumeration: return value.nullable || len(value.values) > 1
	case ir.UnknownModel: return false
	}
	return false
}

sorted_model_keys :: proc(values: map[string]ir.Model) -> [dynamic]string {
	keys := make([dynamic]string)
	for key in values {
		append(&keys, key)
	}
	slice.sort(keys[:])

	return keys
}

generate_schemas :: proc(builder: ^strings.Builder, schemas: ^map[string]ir.Model, operation_name: string, operations: ir.Model) {
	fmt.sbprintln(builder, "export interface Schemas {")

	names := sorted_model_keys(schemas^)

	for name in names {
		fmt.sbprint(builder, annotation_comment(schemas^[name], .typescript, "  "))
		fmt.sbprintf(builder, "  %q: %s;\n", name, model_to_ts(schemas^[name], 1))
	}

	fmt.sbprint(builder, annotation_comment(operations, .typescript, "  "))
	fmt.sbprintf(builder, "  %q: %s;\n", operation_name, model_to_ts(operations, 1))
	fmt.sbprintln(builder, "}")
}

generate_typescript :: proc(
	document: ^ir.Document,
	output_path := "spec.ts",
	issues: ^diagnostics.Manager = nil,
) -> os.Error {
	projected := project_directions(document)
	document := &projected
	if !validate_generation(document, issues, .typescript) { return os.General_Error.Invalid_File }

	builder := strings.builder_make()
	defer strings.builder_destroy(&builder)
	fmt.sbprintln(&builder, "// Generated from OpenAPI schemas; defaults not applied.")

	schemas := make(map[string]ir.Model)
	for name, model in document.schemas { schemas[name] = model }

	// Reserve a separate export when the API already defines a schema named Operations.
	operation_name := "Operations"
	for _, exists := schemas[operation_name]; exists; _, exists = schemas[operation_name] {
		operation_name = fmt.aprintf("%s_", operation_name)
	}
	generate_schemas(&builder, &schemas, operation_name, operations_object(document))

	return os.write_entire_file(output_path, strings.to_string(builder))
}

// Project the typed operation model into the public TypeScript Operations shape.
@(private)
operations_object :: proc(document: ^ir.Document) -> ir.ObjectModel {
	paths := document.paths
	path_fields := make(map[string]ir.Field)
	for path, methods in paths {
		method_fields := make(map[string]ir.Field)
		for method, operation in methods {
			fields := make(map[string]ir.Field)
			parameter_fields := make(map[string]ir.Field)

			for location, group in operation.parameters {
				required := false
				for _, field in group.fields {
					if field.required { required = true }
				}

				parameter_fields[fmt.aprint(location)] = ir.Field{model = group, required = required}
			}
			fields["parameters"] = ir.Field{model = ir.ObjectModel{fields = parameter_fields}, required = true}

			if body, ok := operation.request_body.?; ok {
				body_model := media_object(body.content)
				for media, &field in body_model.fields {
					field.model = with_documentation(field.model, request_documentation(body, media))
				}
				fields["requestBody"] = ir.Field{model = body_model, required = body.required}
			}

			responses := make(map[string]ir.Field)
			for status, content in operation.responses {
				responses[status] = ir.Field{model = media_object(content), required = true}
			}

			fields["responses"] = ir.Field{model = ir.ObjectModel{fields = responses}, required = true}
			method_fields[method] = ir.Field{model = with_documentation(ir.ObjectModel{fields = fields}, operation_documentation(document, path, method, operation)), required = true}
		}

		path_fields[path] = ir.Field{model = ir.ObjectModel{fields = method_fields}, required = true}
	}

	return ir.ObjectModel{fields = path_fields}
}

@(private)
media_object :: proc(content: ir.Content) -> ir.ObjectModel {
	fields := make(map[string]ir.Field)
	for media, model in content { fields[media] = ir.Field{model = model, required = true} }

	return ir.ObjectModel{fields = fields}
}
