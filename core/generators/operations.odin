package generators

import "core:encoding/json"
import "core:fmt"
import "core:slice"
import "core:strings"
import ir "../ir"

// Convert operation identifiers and path segments into readable type names.
type_name :: proc(text: string) -> string {
	ascii_case_offset :: 'a' - 'A'

	builder := strings.builder_make()
	capitalize := true

	for byte in transmute([]byte)text {
		is_letter := (byte >= 'a' && byte <= 'z') || (byte >= 'A' && byte <= 'Z')
		is_digit := byte >= '0' && byte <= '9'
		if !is_letter && !is_digit {
			capitalize = true
			continue
		}

		letter := byte
		if capitalize && letter >= 'a' && letter <= 'z' { letter -= ascii_case_offset }
		strings.write_byte(&builder, letter)
		capitalize = false
	}

	result := strings.to_string(builder)
	if len(result) == 0 { return "Operation" }
	if result[0] >= '0' && result[0] <= '9' { return fmt.aprintf("Operation%s", result) }

	return result
}

add_operation_type :: proc(schemas: ^map[string]ir.Model, base: string, model: ir.Model) -> string {
	name := base
	index := 2

	for _, exists := schemas^[name]; exists; _, exists = schemas^[name] {
		name = fmt.aprintf("%s%d", base, index)
		index += 1
	}
	schemas^[name] = model
	return name
}

sorted_keys :: proc(values: map[string]$T) -> [dynamic]string {
	result := make([dynamic]string)
	for name in values { append(&result, name) }
	slice.sort(result[:])

	return result
}

// Compare payload schemas without their source pointers, which differ between media entries.
@(private)
same_payload :: proc(left, right: ir.Model) -> bool {
	left_annotations, left_err := json.marshal(model_annotations(left), {sort_maps_by_key = true})
	right_annotations, right_err := json.marshal(model_annotations(right), {sort_maps_by_key = true})
	if left_err != nil || right_err != nil || string(left_annotations) != string(right_annotations) { return false }
	switch value in left {
	case ir.Primitive:
		other, ok := right.(ir.Primitive)
		return ok && value.type == other.type && value.format == other.format && value.nullable == other.nullable
	case ir.Reference:
		other, ok := right.(ir.Reference)
		return ok && value.name == other.name && value.nullable == other.nullable
	case ir.UnknownModel:
		other, ok := right.(ir.UnknownModel)
		return ok && value.nullable == other.nullable
	case ir.Enumeration:
		other, ok := right.(ir.Enumeration)
		if !ok || value.nullable != other.nullable { return false }
		left_values, _ := json.marshal(value.values, {sort_maps_by_key = true})
		right_values, _ := json.marshal(other.values, {sort_maps_by_key = true})
		return string(left_values) == string(right_values)
	case ir.ArrayModel:
		other, ok := right.(ir.ArrayModel)
		return ok && value.nullable == other.nullable && same_payload(value.items^, other.items^)
	case ir.ObjectModel:
		other, ok := right.(ir.ObjectModel)
		if !ok || value.nullable != other.nullable || value.closed != other.closed || len(value.fields) != len(other.fields) { return false }
		for name, field in value.fields {
			other_field, found := other.fields[name]
			if !found { return false }
			if field.required != other_field.required || field.read_only != other_field.read_only || field.write_only != other_field.write_only { return false }
			if !same_payload(field.model, other_field.model) { return false }
		}
		additional, has_additional := value.additional_properties.?
		other_additional, other_has_additional := other.additional_properties.?
		if has_additional != other_has_additional { return false }
		return !has_additional || same_payload(additional^, other_additional^)
	}
	return false
}

@(private)
contains_payload :: proc(payloads: []ir.Model, model: ir.Model) -> bool {
	for previous in payloads {
		if same_payload(previous, model) { return true }
	}
	return false
}

@(private)
payload_has_inline_type :: proc(model: ir.Model) -> bool {
	switch value in model {
	case ir.ObjectModel:
		if len(value.fields) > 0 { return true }
		if additional, present := value.additional_properties.?; present { return payload_has_inline_type(additional^) }
	case ir.Enumeration: return true
	case ir.ArrayModel: return payload_has_inline_type(value.items^)
	case ir.Primitive, ir.Reference, ir.UnknownModel:
	}
	return false
}

// Reference existing schemas directly; name only inline objects and enums.
@(private)
add_payload_type :: proc(schemas: ^map[string]ir.Model, base: string, model: ir.Model, documentation: string) -> ir.Model {
	switch original in model {
	case ir.ObjectModel:
		if len(original.fields) > 0 {
			name := add_operation_type(schemas, base, with_documentation(model, documentation))
			return ir.Reference{name = name}
		}
		if additional, present := original.additional_properties.?; present {
			copy := original
			copy.additional_properties = new(ir.Model)
			copy.additional_properties.?^ = add_payload_type(schemas, fmt.aprintf("%sValue", base), additional^, documentation)
			return copy
		}
	case ir.Enumeration:
		name := add_operation_type(schemas, base, with_documentation(model, documentation))
		return ir.Reference{name = name}
	case ir.ArrayModel:
		copy := original
		copy.items = new(ir.Model)
		copy.items^ = add_payload_type(schemas, fmt.aprintf("%sItem", base), original.items^, documentation)
		return copy
	case ir.Primitive, ir.Reference, ir.UnknownModel:
	}
	return model
}

// Find the named declaration produced for an inline payload inside containers.
@(private)
inline_payload_name :: proc(model: ir.Model) -> string {
	switch value in model {
	case ir.Reference: return value.name
	case ir.ArrayModel: return inline_payload_name(value.items^)
	case ir.ObjectModel:
		if additional, present := value.additional_properties.?; present { return inline_payload_name(additional^) }
	case ir.Primitive, ir.Enumeration, ir.UnknownModel:
	}
	return ""
}

// Use the last resource and optional path parameter when operationId is absent.
@(private)
operation_name :: proc(method, path: string) -> string {
	resource := ""
	parameter := ""
	for segment in strings.split(path, "/") {
		if segment == "" { continue }
		if strings.has_prefix(segment, "{") && strings.has_suffix(segment, "}") {
			parameter = strings.trim(segment, "{}")
		} else {
			resource = segment
			parameter = ""
		}
	}
	if parameter != "" { return type_name(fmt.aprintf("%s %s by %s", method, resource, parameter)) }
	return type_name(fmt.aprintf("%s %s", method, resource))
}

OperationBinding :: struct {
	base_name:     string,
	parameters:    map[ir.ParameterLocation]string,
	request_media: map[string]ir.Model,
	responses:     map[string]map[string]ir.Model,
}

generate_operation_types :: proc(
	schemas: ^map[string]ir.Model,
	document: ^ir.Document,
	bindings: ^map[string]map[string]OperationBinding = nil,
) {
	paths := document.paths
	counts := make(map[string]int)
	for path, methods in paths {
		for method, operation in methods { counts[operation_base(method, path, operation)] += 1 }
	}
	// Stable traversal also makes numeric collision suffixes deterministic.
	for path in sorted_keys(paths) {
		methods := paths[path]
		path_bindings := make(map[string]OperationBinding)
		for method in sorted_keys(methods) {
			operation := methods[method]
			binding := OperationBinding{
				parameters    = make(map[ir.ParameterLocation]string),
				request_media = make(map[string]ir.Model),
				responses     = make(map[string]map[string]ir.Model),
			}
			documentation := operation_documentation(document, path, method, operation)
			base := operation_base(method, path, operation)
			if counts[base] > 1 {
				resource := path
				if index := strings.index(path, "/api/"); index >= 0 { resource = path[index + len("/api/"):] }
				base = type_name(fmt.aprintf("%s %s", method, resource))
			}
			binding.base_name = base

			for location in ir.ParameterLocation {
				if group, found := operation.parameters[location]; found {
					param_name := add_operation_type(schemas, fmt.aprintf("%s%sParameters", base, type_name(fmt.aprint(location))), with_documentation(group, documentation))
					binding.parameters[location] = param_name
				}
			}

			if body, found := operation.request_body.?; found {
				request_models := make([dynamic]struct { model: ir.Model, projected: ir.Model })
				for media in sorted_keys(body.content) {
					original := body.content[media]
					duplicate := false
					for previous in request_models {
						if !same_payload(previous.model, original) { continue }
						binding.request_media[media] = previous.projected
						duplicate = true
						break
					}
					if duplicate { continue }
					text := fmt.aprintf("%s\n%s", documentation, request_documentation(body, media))
					projected := add_payload_type(schemas, fmt.aprintf("%sRequest", base), original, text)
					append(&request_models, {original, projected})
					binding.request_media[media] = projected
				}
			}

			inline_payloads := make([dynamic]ir.Model)
			inline_statuses := 0
			for status in sorted_keys(operation.responses) {
				new_status := false
				for media in sorted_keys(operation.responses[status]) {
					model := operation.responses[status][media]
					if !payload_has_inline_type(model) { continue }
					if contains_payload(inline_payloads[:], model) { continue }
					append(&inline_payloads, model)
					new_status = true
				}
				if new_status { inline_statuses += 1 }
			}
			response_models := make([dynamic]struct { model: ir.Model, name: string, projected: ir.Model })
			for status in sorted_keys(operation.responses) {
				content := operation.responses[status]
				status_media := make(map[string]ir.Model)
				for media in sorted_keys(content) {
					model := content[media]
					text := fmt.aprintf("%s\nResponse status: %s. Content type: %s.", documentation, status, media)
					duplicate := false
					for previous in response_models {
						if !same_payload(previous.model, model) { continue }
						if previous.name != "" { schemas^[previous.name] = with_documentation(schemas^[previous.name], text) }
						status_media[media] = previous.projected
						duplicate = true
						break
					}
					if duplicate { continue }
					response_name := fmt.aprintf("%sResponse", base)
					if inline_statuses > 1 { response_name = fmt.aprintf("%s%s", response_name, status) }
					projected := add_payload_type(schemas, response_name, model, text)
					name := ""
					if payload_has_inline_type(model) { name = inline_payload_name(projected) }
					append(&response_models, {model, name, projected})
					status_media[media] = projected
				}
				binding.responses[status] = status_media
			}

			if bindings != nil {
				path_bindings[method] = binding
			}
		}
		if bindings != nil {
			bindings^[path] = path_bindings
		}
	}
}

@(private)
operation_base :: proc(method, path: string, operation: ir.Operation) -> string {
	if id, found := operation.operation_id.?; found && len(id) > 0 { return type_name(id) }
	return operation_name(method, path)
}

@(private)
operation_documentation :: proc(document: ^ir.Document, path, method: string, operation: ir.Operation) -> string {
	parts := make([dynamic]string)
	append(&parts, fmt.aprintf("%s %s", strings.to_upper(method), path))
	if summary, present := operation.summary.?; present { append(&parts, summary) }
	if description, present := operation.description.?; present { append(&parts, description) }
	requirements, specified := operation.security.?
	if !specified { requirements, specified = document.security.? }
	if specified { append(&parts, security_documentation(requirements)) }
	text, _ := strings.join(parts[:], "\n")
	return text
}

@(private)
request_documentation :: proc(body: ir.RequestBody, media: string) -> string {
	parts := make([dynamic]string)
	presence := "optional"
	if body.required { presence = "required" }
	append(&parts, fmt.aprintf("Request body: %s. Content type: %s.", presence, media))
	if encoding, present := body.encodings[media]; present { collect_setting_comments(encoding, "Encoding", &parts) }
	text, _ := strings.join(parts[:], "\n")
	return text
}

