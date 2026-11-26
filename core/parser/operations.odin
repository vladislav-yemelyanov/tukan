package parser

import "core:fmt"
import "core:encoding/json"
import "core:strings"
import ir "../ir"
import "../diagnostics"
import "../openapi"
import "schemas"

@(private)
content_model :: proc(content: Maybe(map[string]openapi.MediaType), component_schemas: map[string]openapi.Schema, issues: ^diagnostics.Manager, path: string) -> (ir.Content, bool) {
	result := make(ir.Content)
	valid := true

	if entries, ok := content.?; ok {
		for media_type, media in entries {
			model: ir.Model = ir.UnknownModel{}
			if schema, found := media.schema.?; found {
				schema_path := diagnostics.child_path(diagnostics.child_path(path, media_type), "schema")
				parsed, schema_valid := schemas.parse(schema, component_schemas, issues, schema_path)
				if !schema_valid {
					valid = false
					continue
				}

				model = parsed
			}

			result[media_type] = model
		}
	}

	return result, valid
}

@(private)
parameter_location :: proc(location: string) -> (ir.ParameterLocation, bool) {
	switch location {
	case "path": return .path, true
	case "query": return .query, true
	case "header": return .header, true
	case "cookie": return .cookie, true
	}

	return {}, false
}

@(private)
parameter_models :: proc(item: openapi.PathItem, operation: openapi.Operation, components: openapi.Components, component_schemas: map[string]openapi.Schema, issues: ^diagnostics.Manager, item_path, path, route: string) -> (map[ir.ParameterLocation]ir.ObjectModel, bool) {
	groups := make(map[ir.ParameterLocation]ir.ObjectModel)
	valid := true
	declared_paths := make(map[string]bool)

	// Visit path parameters first so operation parameters can override them below.
	parameter_lists := [2]Maybe([]openapi.Parameter){item.parameters, operation.parameters}
	parameter_paths := [2]string{diagnostics.child_path(item_path, "parameters"), diagnostics.child_path(path, "parameters")}

	for list, list_index in parameter_lists {
		parameters, present := list.?
		if !present { continue }
		seen := make(map[ir.ParameterLocation]map[string]string)

		for raw, index in parameters {
			parameter_path := diagnostics.child_path(parameter_paths[list_index], fmt.aprint(index))
			parameter, resolved, source_path := resolve_parameter(raw, components, issues, parameter_path)
			if !resolved {
				valid = false
				continue
			}

			location, supported := parameter_location(parameter.location)
			if !supported {
				diagnostics.add(issues, "Unsupported parameter location", parameter.location, diagnostics.child_path(source_path, "in"), code = "invalid-parameter-location")
				valid = false
				continue
			}

			if parameter.name == "" {
				diagnostics.add(issues, "Parameter name is required", "", diagnostics.child_path(source_path, "name"), code = "missing-parameter-name")
				valid = false
			}
			names, exists := seen[location]
			if !exists { names = make(map[string]string) }
			if first_path, duplicate := names[parameter.name]; duplicate {
				diagnostics.add(issues, "Duplicate parameter in the same list", fmt.aprintf("%s (%s); first declared at %s", parameter.name, location, first_path), parameter_path, code = "duplicate-parameter")
				valid = false
				continue
			}
			names[parameter.name] = parameter_path
			seen[location] = names

			if location == .path {
				declared_paths[parameter.name] = true
				if !strings.contains(route, fmt.aprintf("{{%s}}", parameter.name)) {
					diagnostics.add(issues, "Path parameter is absent from the path template", parameter.name, diagnostics.child_path(source_path, "name"), code = "unmatched-path-parameter")
					valid = false
				}
				flag, present := parameter.required.?
				if !present || !flag {
					diagnostics.add(issues, "Path parameter must declare required: true", parameter.name, diagnostics.child_path(source_path, "required"), code = "path-parameter-not-required")
					valid = false
				}
			}

			_, has_schema := parameter.schema.?
			content, has_content := parameter.content.?
			if has_schema == has_content {
				diagnostics.add(issues, "Parameter must contain exactly one of schema or content", parameter.name, source_path, code = "parameter-schema-or-content")
				valid = false
				continue
			}
			if has_content && len(content) != 1 {
				diagnostics.add(issues, "Parameter content must contain exactly one media type", parameter.name, diagnostics.child_path(source_path, "content"), code = "parameter-content-count")
				valid = false
				continue
			}

			model: ir.Model = ir.UnknownModel{}
			if schema, ok := parameter.schema.?; ok {
				parsed, schema_valid := schemas.parse(schema, component_schemas, issues, diagnostics.child_path(source_path, "schema"))
				if !schema_valid {
					valid = false
					continue
				}

				model = parsed
			} else if content, ok := parameter.content.?; ok {
				parsed, content_valid := content_model(content, component_schemas, issues, diagnostics.child_path(source_path, "content"))
				if !content_valid {
					valid = false
					continue
				}

				model = content_object(parsed)
			}

			// Valid path parameters always remain required in IR.
			required := location == .path
			if flag, ok := parameter.required.?; ok && flag { required = true }

			group, found := groups[location]
			if !found { group.fields = make(map[string]ir.Field) }

			group.fields[parameter.name] = ir.Field{model = model, required = required}
			groups[location] = group
		}
	}

	for start := 0; start < len(route); start += 1 {
		if route[start] != '{' { continue }
		end := start + 1
		for end < len(route) && route[end] != '}' { end += 1 }
		if end == len(route) { break }
		name := route[start + 1:end]
		if !declared_paths[name] {
			diagnostics.add(issues, "Path template has no matching path parameter", name, path, code = "missing-path-parameter")
			valid = false
		}
		start = end
	}
	return groups, valid
}

@(private)
operation_model :: proc(item: openapi.PathItem, operation: openapi.Operation, components: openapi.Components, component_schemas: map[string]openapi.Schema, issues: ^diagnostics.Manager, item_path, path, route: string) -> (ir.Operation, bool) {
	result := ir.Operation{
		operation_id = operation.operation_id,
		summary = operation.summary,
		description = operation.description,
		responses = make(map[string]ir.Content),
	}

	parameters, parameters_valid := parameter_models(item, operation, components, component_schemas, issues, item_path, path, route)
	result.parameters = parameters
	valid := parameters_valid

	scheme_metadata: Maybe(json.Object)
	if raw := components.security_schemes; raw != nil {
		if object, ok := raw.(json.Object); ok { scheme_metadata = object }
	}
	security, security_valid := parse_security(operation.security, scheme_metadata, issues, diagnostics.child_path(path, "security"))
	result.security = security
	if !security_valid { valid = false }

	if raw_body, ok := operation.request_body.?; ok {
		body_path := diagnostics.child_path(path, "requestBody")
		body, resolved, source_path := resolve_body(raw_body, components, issues, body_path)
		if resolved {
			content, content_valid := content_model(body.content, component_schemas, issues, diagnostics.child_path(source_path, "content"))
			if !content_valid { valid = false }

			required := false
			if flag, ok := body.required.?; ok { required = flag }

			encodings := make(map[string]json.Object)
			if media_types, present := body.content.?; present {
				for media, entry in media_types {
					if entry.encoding == nil { continue }
					encoding, is_object := entry.encoding.(json.Object)
					if !is_object {
						encoding_path := diagnostics.child_path(diagnostics.child_path(diagnostics.child_path(source_path, "content"), media), "encoding")
						diagnostics.add(issues, "Media encoding must be an object", "encoding", encoding_path, code = "invalid-media-encoding")
						valid = false
						continue
					}
					encodings[media] = encoding
				}
			}
			result.request_body = ir.RequestBody{required = required, content = content, source_path = source_path, encodings = encodings}
		} else {
			valid = false
		}
	}

	entries, has_responses := operation.responses.?
	response_count := 0
	for status in entries {
		if !strings.has_prefix(status, "x-") { response_count += 1 }
	}
	if !has_responses || response_count == 0 {
		diagnostics.add(issues, "Operation requires at least one response", "", diagnostics.child_path(path, "responses"), code = "missing-operation-responses")
		valid = false
	}
	if has_responses {
		for status, raw in entries {
			response_path := diagnostics.child_path(diagnostics.child_path(path, "responses"), status)
			if strings.has_prefix(status, "x-") { continue }
			if !valid_response_status(status) {
				diagnostics.add(issues, "Invalid response status", status, response_path, code = "invalid-response-status")
				valid = false
				continue
			}
			response, resolved, source_path := resolve_response(raw, components, issues, response_path)
			if !resolved {
				valid = false
				continue
			}

			content, content_valid := content_model(response.content, component_schemas, issues, diagnostics.child_path(source_path, "content"))
			if !content_valid {
				valid = false
				continue
			}

			result.responses[status] = content
		}
	}

	return result, valid
}

// A content-based parameter is itself a data object keyed by media type.
@(private)
content_object :: proc(content: ir.Content) -> ir.ObjectModel {
	fields := make(map[string]ir.Field)
	for media_type, model in content { fields[media_type] = ir.Field{model = model, required = true} }

	return ir.ObjectModel{fields = fields}
}

@(private)
parse_operations :: proc(spec: ^openapi.OpenApiSpec, component_schemas: map[string]openapi.Schema, issues: ^diagnostics.Manager = nil, stats: ^ParseStats = nil) -> (map[string]map[string]ir.Operation, bool) {
	paths := make(map[string]map[string]ir.Operation)
	valid_operations := true
	components: openapi.Components
	if value, ok := spec.components.?; ok { components = value }

	entries, present := spec.paths.?
	if !present { return paths, true }

	for path, item in entries {
		methods := make(map[string]ir.Operation)
		item_path := diagnostics.child_path("#/paths", path)
		if _, present := item.ref.?; present {
			diagnostics.add(issues, "Path item references are ignored", "", diagnostics.child_path(item_path, "$ref"), .warning, "unsupported-path-item-reference")
		}

		// These arrays share an order so each optional operation retains its HTTP method.
		operations := [8]Maybe(openapi.Operation){item.get, item.put, item.post, item.delete, item.options, item.head, item.patch, item.trace}
		method_names := [8]string{"get", "put", "post", "delete", "options", "head", "patch", "trace"}

		for operation, index in operations {
			value, present := operation.?
			if !present { continue }

			method := method_names[index]
			model, valid := operation_model(item, value, components, component_schemas, issues, item_path, diagnostics.child_path(item_path, method), path)
			if !valid {
				if stats != nil { stats.operations_failed += 1 }
				valid_operations = false
				continue
			}

			if stats != nil { stats.operations_parsed += 1 }
			methods[method] = model
		}

		paths[path] = methods
	}

	return paths, valid_operations
}

@(private)
valid_response_status :: proc(status: string) -> bool {
	if status == "default" { return true }
	if len(status) != 3 || status[0] < '1' || status[0] > '5' { return false }
	if status[1:] == "XX" { return true }
	return status[1] >= '0' && status[1] <= '9' && status[2] >= '0' && status[2] <= '9'
}
