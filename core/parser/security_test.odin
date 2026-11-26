package parser

import "core:fmt"
import virtual "core:mem/virtual"
import "core:testing"
import "../diagnostics"
import "../openapi"

@(test)
security_metadata_preserves_empty_overrides_and_ignores_tags :: proc(t: ^testing.T) {
	arena: virtual.Arena
	if !testing.expect(t, virtual.arena_init_growing(&arena) == nil, "arena should initialize") { return }
	defer virtual.arena_destroy(&arena)
	context.allocator = virtual.arena_allocator(&arena)

	source := `{"openapi":"3.0.3","tags":[{"name":"Users"}],"security":[{"Bearer":[]}],"components":{"securitySchemes":{"Bearer":{"type":"http","scheme":"bearer","x-owner":"team"}}},"paths":{
		"/private":{"get":{"tags":["Users"],"responses":{"204":{}}}},
		"/public":{"get":{"security":[],"responses":{"204":{}}}},
		"/optional":{"get":{"security":[{},{"Bearer":[]}],"responses":{"204":{}}}}
	}}`
	spec, decoded := openapi.decode(transmute([]byte)source)
	if !testing.expect(t, decoded, "security metadata should decode") { return }
	issues: diagnostics.Manager
	result := parse(&spec, &issues)
	if !testing.expect(t, result.valid, "security metadata should permit generation") { return }
	testing.expect_value(t, len(issues.issues), 0)
	defaults, has_defaults := result.document.security.?
	testing.expect(t, has_defaults && len(defaults) == 1, "document requirements must be retained")
	testing.expect(t, result.document.paths["/private"]["get"].security == nil, "absent operation security must remain absent for inheritance")
	public, has_public := result.document.paths["/public"]["get"].security.?
	testing.expect(t, has_public && len(public) == 0, "an explicit empty override must remain present")
	optional, _ := result.document.paths["/optional"]["get"].security.?
	testing.expect(t, len(optional) == 2 && len(optional[0]) == 0, "anonymous alternatives must retain their position")
	schemes, found := result.document.security_schemes.?
	testing.expect(t, found && len(schemes) == 1, "scheme definitions must be retained")
	testing.expect(t, spec.security != nil, "parsing must preserve source metadata")
}

@(test)
security_metadata_reports_malformed_shapes_and_missing_schemes :: proc(t: ^testing.T) {
	arena: virtual.Arena
	if !testing.expect(t, virtual.arena_init_growing(&arena) == nil, "arena should initialize") { return }
	defer virtual.arena_destroy(&arena)
	context.allocator = virtual.arena_allocator(&arena)

	cases := [?]struct { security, schemes, code, path: string }{
		{`null`, `{}`, "invalid-security-requirement", "#/security"},
		{`{}`, `{}`, "invalid-security-requirement", "#/security"},
		{`[true]`, `{}`, "invalid-security-requirement", "#/security/0"},
		{`[{"Key":"read"}]`, `{"Key":{}}`, "invalid-security-requirement", "#/security/0/Key"},
		{`[{"Key":[1]}]`, `{"Key":{}}`, "invalid-security-requirement", "#/security/0/Key/0"},
		{`[{"A/B~C":[]}]`, `{}`, "missing-security-scheme", "#/security/0/A~1B~0C"},
		{`[]`, `[]`, "invalid-security-schemes", "#/components/securitySchemes"},
		{`[]`, `{"Key":false}`, "invalid-security-scheme", "#/components/securitySchemes/Key"},
	}
	for scenario in cases {
		source := fmt.aprintf(`{{"openapi":"3.0.3","security":%s,"components":{{"securitySchemes":%s}}}}`, scenario.security, scenario.schemes)
		spec, decoded := openapi.decode(transmute([]byte)source)
		if !testing.expect(t, decoded, "raw metadata should reach semantic validation") { continue }
		issues: diagnostics.Manager
		result := parse(&spec, &issues)
		testing.expectf(t, !result.valid, "invalid metadata must fail: %s", source)
		if !testing.expect_value(t, len(issues.issues), 1) { continue }
		testing.expect_value(t, issues.issues[0].code, scenario.code)
		testing.expect_value(t, issues.issues[0].path, scenario.path)
		testing.expect_value(t, issues.issues[0].severity, diagnostics.Severity.error)
	}
}

@(test)
operation_security_errors_keep_operation_paths :: proc(t: ^testing.T) {
	arena: virtual.Arena
	if !testing.expect(t, virtual.arena_init_growing(&arena) == nil, "arena should initialize") { return }
	defer virtual.arena_destroy(&arena)
	context.allocator = virtual.arena_allocator(&arena)

	source := `{"openapi":"3.0.3","paths":{"/users":{"get":{"security":[{"Missing":[]}],"responses":{"204":{}}}}}}`
	spec, decoded := openapi.decode(transmute([]byte)source)
	if !testing.expect(t, decoded, "operation security should decode") { return }
	issues: diagnostics.Manager
	result := parse(&spec, &issues)
	testing.expect(t, !result.valid, "missing operation schemes must fail generation")
	testing.expect_value(t, result.stats.operations_failed, 1)
	if !testing.expect_value(t, len(issues.issues), 1) { return }
	testing.expect_value(t, issues.issues[0].code, "missing-security-scheme")
	testing.expect_value(t, issues.issues[0].path, "#/paths/~1users/get/security/0/Missing")
}
