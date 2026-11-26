package schemas

import "core:encoding/json"
import "core:fmt"
import "../../openapi"
import ir "../../ir"
import "../../diagnostics"

@(private)
property_is_required :: proc(required: Maybe([]string), property: string) -> bool {
	values, ok := required.?
	if !ok { return false }

	for value in values {
		if value == property { return true }
	}

	return false
}

@(private)
model_pointer :: proc(model: ir.Model) -> ^ir.Model {
	result := new(ir.Model)
	result^ = model

	return result
}

@(private)
property_direction :: proc(property: json.Object, schemas: map[string]openapi.Schema) -> (read_only, write_only: bool) {
	current := property
	// Direction annotations can live on a referenced property schema.
	for _ in 0..=len(schemas) {
		if flag, ok := current["readOnly"].(json.Boolean); ok { read_only = read_only || bool(flag) }
		if flag, ok := current["writeOnly"].(json.Boolean); ok { write_only = write_only || bool(flag) }
		ref, has_ref := current["$ref"].(json.String)
		if !has_ref { break }
		name, valid := openapi.component_name(string(ref), "schemas").?
		if !valid { break }
		target, found := schemas[name]
		if !found { break }
		current = json.Object(target)
	}
	return
}

// Conversion validates references as it visits each schema once; false never means an unconstrained schema.
parse :: proc(source: openapi.Schema, schemas: map[string]openapi.Schema, issues: ^diagnostics.Manager = nil, path := "#") -> (ir.Model, bool) {
	model, valid := parse_model(source, schemas, issues, path)
	if !valid { return model, false }
	annotations := make(json.Object)
	for name in ([9]string{"description", "minLength", "maxLength", "minimum", "maximum", "default", "pattern", "readOnly", "writeOnly"}) {
		if value, present := source[name]; present { annotations[name] = value }
	}
	switch &value in model {
	case ir.Primitive: value.annotations = annotations
	case ir.Enumeration: value.annotations = annotations
	case ir.Reference: value.annotations = annotations
	case ir.ArrayModel: value.annotations = annotations
	case ir.ObjectModel: value.annotations = annotations
	case ir.UnknownModel: value.annotations = annotations
	}
	return model, true
}

@(private)
parse_model :: proc(source: openapi.Schema, schemas: map[string]openapi.Schema, issues: ^diagnostics.Manager = nil, path := "#") -> (ir.Model, bool) {
	schema, decoded := read_schema(source, issues, path)
	if !decoded { return {}, false }

	nullable := false
	if flag, ok := schema.nullable.?; ok { nullable = flag }

	if ref, ok := schema.schema_ref.?; ok {
		name, valid := openapi.component_name(ref, "schemas").?
		if !valid {
			diagnostics.add(issues, "Unsupported or invalid schema reference", ref, diagnostics.child_path(path, "$ref"), code = "invalid-schema-reference")
			return {}, false
		}

		if _, found := schemas[name]; !found {
			diagnostics.add(issues, "Schema reference target not found", ref, diagnostics.child_path(path, "$ref"), code = "missing-schema-reference")
			return {}, false
		}

		// Keep a named reference instead of expanding it so recursive schemas remain finite.
		return ir.Reference{name = name, nullable = nullable, source_path = path}, true
	}

	valid := true
	schema_type, has_type := schema.schema_type.?
	_, has_items := schema.items.?
	if has_type && schema_type == .array && !has_items {
		diagnostics.add(issues, "Array schema requires items", "", diagnostics.child_path(path, "items"), code = "missing-array-items")
		valid = false
	}
	if has_type && schema_type != .object {
		for keyword in ([3]string{"properties", "required", "additionalProperties"}) {
			if _, present := source[keyword]; present {
				diagnostics.add(issues, "Object keyword does not apply to the declared type and is ignored", keyword, diagnostics.child_path(path, keyword), .warning, "inapplicable-schema-keyword")
			}
		}
	}

	fields: map[string]ir.Field
	if properties, ok := schema.properties.?; ok {
		fields = make(map[string]ir.Field)
		for name, property in properties {
			model, property_valid := parse_json_schema(property, schemas, issues, diagnostics.child_path(diagnostics.child_path(path, "properties"), name))
			if !property_valid {
				valid = false
				continue
			}

			// The recursive conversion has already validated these property annotations.
			property_schema := property.(json.Object)
			read_only, write_only := property_direction(property_schema, schemas)
			fields[name] = ir.Field{
				model = model, required = property_is_required(schema.required, name),
				read_only = read_only, write_only = write_only,
			}
		}
	}

	item_model: ir.Model = ir.UnknownModel{}
	if items, ok := schema.items.?; ok {
		model, item_valid := parse_json_schema(items, schemas, issues, diagnostics.child_path(path, "items"))
		item_model = model
		if !item_valid { valid = false }
	}

	closed := false
	additional_properties: Maybe(^ir.Model)
	if additional, ok := schema.additional_properties.?; ok {
		switch value in additional {
		case json.Boolean:
			// true allows arbitrary values; false contributes no additional-property model.
			closed = !bool(value)
			if value { additional_properties = model_pointer(ir.UnknownModel{}) }

		case json.Object:
			model, additional_valid := parse_json_schema(value, schemas, issues, diagnostics.child_path(path, "additionalProperties"))
			if !additional_valid { valid = false }
			additional_properties = model_pointer(model)

		case json.Null, json.Integer, json.Float, json.String, json.Array:
			diagnostics.add(issues, "Expected a boolean or schema object", "additionalProperties", diagnostics.child_path(path, "additionalProperties"), code = "invalid-additional-properties")
			valid = false
		}
	}

	if !valid { return {}, false }

	if !has_type || schema_type == .object {
		if required, present := schema.required.?; present {
			for name, index in required {
				if _, found := fields[name]; !found {
					diagnostics.add(issues, "Required property has no declared schema; its presence is not represented", name, diagnostics.child_path(diagnostics.child_path(path, "required"), fmt.aprint(index)), .warning, "unrepresented-required-property")
				}
			}
		}
	}

	if values, ok := schema.enum_values.?; ok {
		if has_type {
			for value, index in values {
				if !enum_value_matches_type(value, schema_type, nullable) {
					diagnostics.add(issues, "Enum value does not match the declared type", fmt.aprint(schema_type), diagnostics.child_path(diagnostics.child_path(path, "enum"), fmt.aprint(index)), code = "enum-type-mismatch")
					valid = false
				}
			}
		}
		if !valid { return {}, false }
		return ir.Enumeration{values = values, nullable = nullable, source_path = path}, true
	}

	_, has_properties := schema.properties.?
	_, has_additional := schema.additional_properties.?

	// Object keywords can identify an object even when the type keyword is absent.
	if (has_type && schema_type == .object) || (!has_type && (has_properties || has_additional)) {
		return ir.ObjectModel{fields = fields, nullable = nullable, additional_properties = additional_properties, closed = closed, source_path = path}, true
	}

	if !has_type { return ir.UnknownModel{nullable = nullable, source_path = path}, true }

	switch schema_type {
	case .string: return ir.Primitive{type = .string, format = schema.format, nullable = nullable, source_path = path}, true
	case .number: return ir.Primitive{type = .number, format = schema.format, nullable = nullable, source_path = path}, true
	case .integer: return ir.Primitive{type = .integer, format = schema.format, nullable = nullable, source_path = path}, true
	case .boolean: return ir.Primitive{type = .boolean, format = schema.format, nullable = nullable, source_path = path}, true
	case .array: return ir.ArrayModel{items = model_pointer(item_model), nullable = nullable, source_path = path}, true
	case .object: return ir.ObjectModel{fields = fields, nullable = nullable, additional_properties = additional_properties, closed = closed, source_path = path}, true
	}

	return ir.UnknownModel{nullable = nullable, source_path = path}, true
}

@(private)
enum_value_matches_type :: proc(value: json.Value, schema_type: Schema_Type, nullable: bool) -> bool {
	switch item in value {
	case json.String: return schema_type == .string
	case json.Boolean: return schema_type == .boolean
	case json.Integer: return schema_type == .integer || schema_type == .number
	case json.Float: return schema_type == .number
	case json.Array: return schema_type == .array
	case json.Object: return schema_type == .object
	case json.Null: return nullable
	}
	return false
}
