package schemas

import "core:encoding/json"
import "../../openapi"
import "../../diagnostics"
import ir "../../ir"

@(private)
Schema_Type :: enum {
	string,
	number,
	integer,
	boolean,
	array,
	object,
}

@(private)
SchemaFields :: struct {
	schema_ref:            Maybe(string),
	required:              Maybe([]string),
	schema_type:           Maybe(Schema_Type),
	items:                 Maybe(json.Value),
	properties:            Maybe(json.Object),
	nullable:              Maybe(bool),
	format:                Maybe(string),
	enum_values:           Maybe([]json.Value),
	additional_properties: Maybe(json.Value),
	min_length:            Maybe(json.Integer),
	max_length:            Maybe(json.Integer),
	minimum:               Maybe(json.Value),
	maximum:               Maybe(json.Value),
	default_value:         Maybe(json.Value),
	read_only:             Maybe(bool),
	write_only:            Maybe(bool),
}

// Read supported fields directly from the JSON tree without serializing nested schemas again.
@(private)
read_schema :: proc(source: openapi.Schema, issues: ^diagnostics.Manager, path: string) -> (schema: SchemaFields, valid: bool) {
	valid = true

	for name, value in source {
		field_valid := true
		switch name {
		case "$ref", "format":
			text, ok := value.(json.String)
			field_valid = ok
			if ok {
				if name == "$ref" {
					schema.schema_ref = string(text)
				} else {
					schema.format = string(text)
				}
			}

		case "nullable":
			flag, ok := value.(json.Boolean)
			field_valid = ok
			if ok { schema.nullable = bool(flag) }

		case "readOnly", "writeOnly":
			flag, ok := value.(json.Boolean)
			field_valid = ok
			if ok {
				if name == "readOnly" { schema.read_only = bool(flag) }
				if name == "writeOnly" { schema.write_only = bool(flag) }
			}

		case "minLength", "maxLength":
			length, ok := value.(json.Integer)
			field_valid = ok && length >= 0
			if field_valid {
				if name == "minLength" { schema.min_length = length }
				if name == "maxLength" { schema.max_length = length }
			}

		case "minimum", "maximum":
			#partial switch _ in value {
			case json.Integer, json.Float:
				if name == "minimum" { schema.minimum = value }
				if name == "maximum" { schema.maximum = value }
			case: field_valid = false
			}

		case "default":
			schema.default_value = value
			// The value is checked against the declared type after all fields are read.

		case "pattern", "description":
			_, field_valid = value.(json.String)

		case "type":
			text, ok := value.(json.String)
			field_valid = ok
			if ok {
				switch text {
				case "string": schema.schema_type = .string
				case "number": schema.schema_type = .number
				case "integer": schema.schema_type = .integer
				case "boolean": schema.schema_type = .boolean
				case "array": schema.schema_type = .array
				case "object": schema.schema_type = .object
				case: field_valid = false
				}
			}

		case "required":
			values, ok := value.(json.Array)
			field_valid = ok
			if ok {
				names := make([]string, len(values))
				for item, index in values {
					text, is_string := item.(json.String)
					if !is_string {
						field_valid = false
						continue
					}

					names[index] = string(text)
				}

				schema.required = names
			}

		case "properties":
			properties, ok := value.(json.Object)
			field_valid = ok
			if ok { schema.properties = properties }

		case "enum":
			values, ok := value.(json.Array)
			field_valid = ok
			if ok { schema.enum_values = values[:] }

		case "items": schema.items = value
		case "additionalProperties": schema.additional_properties = value
		case: warn_schema_keyword(name, issues, path)
		}

		if !field_valid {
			diagnostics.add(issues, "Invalid schema field type or value", name, diagnostics.child_path(path, name), code = "invalid-schema-field")
			valid = false
		}
	}
	if minimum, has_minimum := schema.min_length.?; has_minimum {
		if maximum, has_maximum := schema.max_length.?; has_maximum && minimum > maximum {
			diagnostics.add(issues, "minLength exceeds maxLength", "", diagnostics.child_path(path, "maxLength"), code = "invalid-length-range")
			valid = false
		}
	}
	if minimum, has_minimum := schema.minimum.?; has_minimum {
		if maximum, has_maximum := schema.maximum.?; has_maximum && number_greater(minimum, maximum) {
			diagnostics.add(issues, "minimum exceeds maximum", "", diagnostics.child_path(path, "maximum"), code = "invalid-number-range")
			valid = false
		}
	}
	if read_only, present := schema.read_only.?; present && read_only {
		if write_only, has_write_only := schema.write_only.?; has_write_only && write_only {
			diagnostics.add(issues, "readOnly and writeOnly cannot both be true", "", diagnostics.child_path(path, "writeOnly"), code = "conflicting-property-direction")
			valid = false
		}
	}
	if default_value, has_default := schema.default_value.?; has_default {
		if schema_type, has_type := schema.schema_type.?; has_type {
			nullable := false
			if flag, ok := schema.nullable.?; ok { nullable = flag }
			if !enum_value_matches_type(default_value, schema_type, nullable) {
				diagnostics.add(issues, "Default value does not match the declared type", "", diagnostics.child_path(path, "default"), code = "default-type-mismatch")
				valid = false
			}
		}
	}

	return
}

@(private)
number_greater :: proc(minimum, maximum: json.Value) -> bool {
	if lower, lower_integer := minimum.(json.Integer); lower_integer {
		if upper, upper_integer := maximum.(json.Integer); upper_integer { return lower > upper }
		return f64(lower) > f64(maximum.(json.Float))
	}
	if upper, upper_integer := maximum.(json.Integer); upper_integer {
		return f64(minimum.(json.Float)) > f64(upper)
	}
	return minimum.(json.Float) > maximum.(json.Float)
}

@(private)
parse_json_schema :: proc(value: json.Value, schemas: map[string]openapi.Schema, issues: ^diagnostics.Manager, path: string) -> (ir.Model, bool) {
	object, ok := value.(json.Object)
	if !ok {
		diagnostics.add(issues, "Expected a schema object", "", path, code = "expected-schema-object")
		return {}, false
	}

	return parse(openapi.Schema(object), schemas, issues, path)
}
