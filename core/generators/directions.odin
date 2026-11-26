package generators

import "core:fmt"
import "core:strings"
import ir "../ir"

@(private)
ModelDirection :: enum { request, response }

@(private)
collect_reachable_schemas :: proc(model: ir.Model, direction: ModelDirection, source_schemas: map[string]ir.Model, reachable: ^map[string]bool) {
	switch value in model {
	case ir.Reference:
		if reachable^[value.name] { return }
		reachable^[value.name] = true
		if target, found := source_schemas[value.name]; found {
			collect_reachable_schemas(target, direction, source_schemas, reachable)
		}
	case ir.ArrayModel:
		collect_reachable_schemas(value.items^, direction, source_schemas, reachable)
	case ir.ObjectModel:
		for _, field in value.fields {
			if (direction == .request && field.read_only) || (direction == .response && field.write_only) { continue }
			collect_reachable_schemas(field.model, direction, source_schemas, reachable)
		}
		if additional, found := value.additional_properties.?; found {
			collect_reachable_schemas(additional^, direction, source_schemas, reachable)
		}
	case ir.Primitive, ir.Enumeration, ir.UnknownModel:
	}
}

// References are followed by a fixed-point pass, so recursive schemas stay finite.
@(private)
model_has_direction :: proc(model: ir.Model, direction: ModelDirection, affected: map[string]bool) -> bool {
	switch value in model {
	case ir.Reference: return affected[value.name]
	case ir.ArrayModel: return model_has_direction(value.items^, direction, affected)
	case ir.ObjectModel:
		for _, field in value.fields {
			if (direction == .request && field.read_only) || (direction == .response && field.write_only) || model_has_direction(field.model, direction, affected) { return true }
		}
		if additional, found := value.additional_properties.?; found {
			return model_has_direction(additional^, direction, affected)
		}
	case ir.Primitive, ir.Enumeration, ir.UnknownModel:
	}
	return false
}

@(private)
direction_model :: proc(model: ir.Model, direction: ModelDirection, names: map[string]string) -> ir.Model {
	switch original in model {
	case ir.Reference:
		value := original
		if name, found := names[value.name]; found { value.name = name }
		return value
	case ir.ArrayModel:
		value := original
		value.items = new(ir.Model)
		value.items^ = direction_model(original.items^, direction, names)
		return value
	case ir.ObjectModel:
		value := original
		fields := make(map[string]ir.Field)
		for name, original_field in value.fields {
			field := original_field
			if direction == .request && field.read_only { continue }
			if direction == .response && field.write_only { continue }
			field.model = direction_model(field.model, direction, names)
			fields[name] = field
		}
		value.fields = fields
		if additional, found := value.additional_properties.?; found {
			copy := new(ir.Model)
			copy^ = direction_model(additional^, direction, names)
			value.additional_properties = copy
		}
		return value
	case ir.Primitive, ir.Enumeration, ir.UnknownModel:
		return model
	}
	return model
}

@(private)
direction_content :: proc(content: ir.Content, direction: ModelDirection, names: map[string]string) -> ir.Content {
	result := make(ir.Content)
	for media, model in content { result[media] = direction_model(model, direction, names) }
	return result
}

// Avoid repeating Request or Response in names derived from existing schemas.
@(private)
direction_type_name :: proc(name: string, direction: ModelDirection) -> string {
	suffix := "Request"
	opposite := "Response"
	if direction == .response { suffix, opposite = opposite, suffix }
	if strings.has_suffix(name, suffix) { return fmt.aprintf("%sView", name) }
	if strings.has_suffix(name, opposite) && len(name) > len(opposite) {
		return fmt.aprintf("%s%s", strings.trim_suffix(name, opposite), suffix)
	}
	return fmt.aprintf("%s%s", name, suffix)
}

// Keep the caller's schemas and operations intact: generators may run concurrently.
@(private)
project_directions :: proc(source: ^ir.Document) -> ir.Document {
	schema_names := sorted_keys(source.schemas)
	result := ir.Document{schemas = make(map[string]ir.Model), paths = make(map[string]map[string]ir.Operation)}
	result.security = source.security
	result.security_schemes = source.security_schemes
	for name, model in source.schemas { result.schemas[name] = model }

	reachable: [ModelDirection]map[string]bool
	reachable[.request] = make(map[string]bool)
	reachable[.response] = make(map[string]bool)
	for _, methods in source.paths {
		for _, operation in methods {
			for _, group in operation.parameters {
				collect_reachable_schemas(group, .request, source.schemas, &reachable[.request])
			}
			if body, found := operation.request_body.?; found {
				for _, model in body.content {
					collect_reachable_schemas(model, .request, source.schemas, &reachable[.request])
				}
			}
			for _, content in operation.responses {
				for _, model in content {
					collect_reachable_schemas(model, .response, source.schemas, &reachable[.response])
				}
			}
		}
	}

	names: [ModelDirection]map[string]string
	for direction in ModelDirection {
		affected := make(map[string]bool)
		for {
			changed := false
			for name in schema_names {
				if affected[name] || !model_has_direction(source.schemas[name], direction, affected) { continue }
				affected[name] = true
				changed = true
			}
			if !changed { break }
		}
		names[direction] = make(map[string]string)
		for name in schema_names {
			if !affected[name] || !reachable[direction][name] { continue }
			variant := direction_type_name(name, direction)
			names[direction][name] = add_operation_type(&result.schemas, variant, ir.UnknownModel{})
		}
	}
	for direction in ModelDirection {
		for name, variant in names[direction] {
			result.schemas[variant] = direction_model(source.schemas[name], direction, names[direction])
		}
	}

	for path, methods in source.paths {
		projected := make(map[string]ir.Operation)
		for method, original_operation in methods {
			operation := original_operation
			parameters := make(map[ir.ParameterLocation]ir.ObjectModel)
			for location, group in operation.parameters {
				parameters[location] = direction_model(group, .request, names[.request]).(ir.ObjectModel)
			}
			operation.parameters = parameters
			if body, found := operation.request_body.?; found {
				body.content = direction_content(body.content, .request, names[.request])
				operation.request_body = body
			}
			responses := make(map[string]ir.Content)
			for status, content in operation.responses {
				responses[status] = direction_content(content, .response, names[.response])
			}
			operation.responses = responses
			projected[method] = operation
		}
		result.paths[path] = projected
	}
	return result
}
