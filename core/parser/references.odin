package parser

import "../openapi"
import "../diagnostics"

@(private)
resolve_parameter :: proc(parameter: openapi.Parameter, components: openapi.Components, issues: ^diagnostics.Manager = nil, path := "#") -> (openapi.Parameter, bool, string) {
	source_path := path

	current := parameter
	seen := make(map[string]bool)

	for ref, ok := current.ref.?; ok; ref, ok = current.ref.? {
		name, valid := openapi.component_name(ref, "parameters").?
		if !valid {
			diagnostics.add(issues, "Invalid parameter reference", ref, diagnostics.child_path(source_path, "$ref"), code = "invalid-component-reference")
			return {}, false, source_path
		}

		if seen[name] {
			diagnostics.add(issues, "Cyclic parameter reference", ref, diagnostics.child_path(source_path, "$ref"), code = "cyclic-component-reference")
			return {}, false, source_path
		}

		seen[name] = true
		values, has_values := components.parameters.?
		if !has_values {
			diagnostics.add(issues, "Parameter reference target not found", ref, diagnostics.child_path(source_path, "$ref"), code = "missing-component-reference")
			return {}, false, source_path
		}

		value, found := values[name]
		if !found {
			diagnostics.add(issues, "Parameter reference target not found", ref, diagnostics.child_path(source_path, "$ref"), code = "missing-component-reference")
			return {}, false, source_path
		}

		// Subsequent errors belong to the referenced component, not its caller.
		source_path = diagnostics.child_path("#/components/parameters", name)
		current = value
	}

	return current, true, source_path
}

@(private)
resolve_body :: proc(body: openapi.RequestBody, components: openapi.Components, issues: ^diagnostics.Manager = nil, path := "#") -> (openapi.RequestBody, bool, string) {
	source_path := path

	current := body
	seen := make(map[string]bool)

	for ref, ok := current.ref.?; ok; ref, ok = current.ref.? {
		name, valid := openapi.component_name(ref, "requestBodies").?
		if !valid {
			diagnostics.add(issues, "Invalid request body reference", ref, diagnostics.child_path(source_path, "$ref"), code = "invalid-component-reference")
			return {}, false, source_path
		}

		if seen[name] {
			diagnostics.add(issues, "Cyclic request body reference", ref, diagnostics.child_path(source_path, "$ref"), code = "cyclic-component-reference")
			return {}, false, source_path
		}

		seen[name] = true
		values, has_values := components.request_bodies.?
		if !has_values {
			diagnostics.add(issues, "Request body reference target not found", ref, diagnostics.child_path(source_path, "$ref"), code = "missing-component-reference")
			return {}, false, source_path
		}

		value, found := values[name]
		if !found {
			diagnostics.add(issues, "Request body reference target not found", ref, diagnostics.child_path(source_path, "$ref"), code = "missing-component-reference")
			return {}, false, source_path
		}
		source_path = diagnostics.child_path("#/components/requestBodies", name)
		current = value
	}

	return current, true, source_path
}

@(private)
resolve_response :: proc(response: openapi.Response, components: openapi.Components, issues: ^diagnostics.Manager = nil, path := "#") -> (openapi.Response, bool, string) {
	source_path := path

	current := response
	seen := make(map[string]bool)

	for ref, ok := current.ref.?; ok; ref, ok = current.ref.? {
		name, valid := openapi.component_name(ref, "responses").?
		if !valid {
			diagnostics.add(issues, "Invalid response reference", ref, diagnostics.child_path(source_path, "$ref"), code = "invalid-component-reference")
			return {}, false, source_path
		}

		if seen[name] {
			diagnostics.add(issues, "Cyclic response reference", ref, diagnostics.child_path(source_path, "$ref"), code = "cyclic-component-reference")
			return {}, false, source_path
		}

		seen[name] = true
		values, has_values := components.responses.?
		if !has_values {
			diagnostics.add(issues, "Response reference target not found", ref, diagnostics.child_path(source_path, "$ref"), code = "missing-component-reference")
			return {}, false, source_path
		}

		value, found := values[name]
		if !found {
			diagnostics.add(issues, "Response reference target not found", ref, diagnostics.child_path(source_path, "$ref"), code = "missing-component-reference")
			return {}, false, source_path
		}
		source_path = diagnostics.child_path("#/components/responses", name)
		current = value
	}

	return current, true, source_path
}
