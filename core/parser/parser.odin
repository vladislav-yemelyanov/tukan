package parser

import "core:strings"
import ir "../ir"
import "../diagnostics"
import "../openapi"
import "schemas"

ParseStats :: struct {
	schemas_parsed: int,
	schemas_failed: int,

	operations_parsed: int,
	operations_failed: int,
}

ParseResult :: struct {
	document: ir.Document,
	stats: ParseStats,
	valid: bool,
}

// All returned data uses context.allocator. Callers must keep it alive while using the document.
// A document with valid == false is partial and must not be passed to a generator.
parse :: proc(spec: ^openapi.OpenApiSpec, issues: ^diagnostics.Manager = nil) -> (result: ParseResult) {
	if spec == nil {
		diagnostics.add(issues, "Specification is missing")
		return
	}

	if spec.openapi == "" {
		diagnostics.add(issues, "OpenAPI version is required", "", "#/openapi", code = "missing-openapi-version")
		return
	}
	if !strings.has_prefix(spec.openapi, "3.0.") {
		diagnostics.add(issues, "Unsupported OpenAPI version; interpreting supported fields as OpenAPI 3.0", spec.openapi, "#/openapi", .warning, "unsupported-openapi-version")
	}

	result.document.schemas = make(map[string]ir.Model)
	component_schemas := make(map[string]openapi.Schema)
	security_valid := true
	if components, ok := spec.components.?; ok {
		result.document.security_schemes, security_valid = parse_security_schemes(components.security_schemes, issues)
		if values, found := components.schemas.?; found { component_schemas = values }
	}
	security, requirements_valid := parse_security(spec.security, result.document.security_schemes, issues, "#/security")
	result.document.security = security

	for name, schema in component_schemas {
		path := diagnostics.child_path("#/components/schemas", name)
		model, valid := schemas.parse(schema, component_schemas, issues, path)
		if !valid {
			result.stats.schemas_failed += 1
			continue
		}

		result.document.schemas[name] = model
		result.stats.schemas_parsed += 1
	}

	paths, valid := parse_operations(spec, component_schemas, issues, &result.stats)
	result.document.paths = paths
	result.valid = valid && result.stats.schemas_failed == 0 && security_valid && requirements_valid

	return
}
