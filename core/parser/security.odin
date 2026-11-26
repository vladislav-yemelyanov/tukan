package parser

import "core:encoding/json"
import "core:fmt"
import "../diagnostics"
import ir "../ir"

@(private)
parse_security_schemes :: proc(source: json.Value, issues: ^diagnostics.Manager) -> (Maybe(json.Object), bool) {
	if source == nil { return nil, true }
	schemes, ok := source.(json.Object)
	if !ok {
		diagnostics.add(issues, "Security schemes must be an object", "", "#/components/securitySchemes", code = "invalid-security-schemes")
		return nil, false
	}
	valid := true
	for name, value in schemes {
		if _, object := value.(json.Object); object { continue }
		diagnostics.add(issues, "Security scheme must be an object", name, diagnostics.child_path("#/components/securitySchemes", name), code = "invalid-security-scheme")
		valid = false
	}
	return schemes, valid
}

@(private)
parse_security :: proc(source: json.Value, scheme_metadata: Maybe(json.Object), issues: ^diagnostics.Manager, path: string) -> (Maybe([]ir.SecurityRequirement), bool) {
	if source == nil { return nil, true }
	entries, ok := source.(json.Array)
	if !ok {
		diagnostics.add(issues, "Security requirements must be an array", "", path, code = "invalid-security-requirement")
		return nil, false
	}
	valid := true
	requirements := make([]ir.SecurityRequirement, len(entries))
	schemes, _ := scheme_metadata.?
	for entry, index in entries {
		entry_path := diagnostics.child_path(path, fmt.aprint(index))
		object, is_object := entry.(json.Object)
		if !is_object {
			diagnostics.add(issues, "Security requirement must be an object", "", entry_path, code = "invalid-security-requirement")
			valid = false
			continue
		}
		requirement := make(ir.SecurityRequirement)
		for name, raw_scopes in object {
			scope_path := diagnostics.child_path(entry_path, name)
			if _, found := schemes[name]; !found {
				diagnostics.add(issues, "Security scheme not found", name, scope_path, code = "missing-security-scheme")
				valid = false
			}
			values, is_array := raw_scopes.(json.Array)
			if !is_array {
				diagnostics.add(issues, "Security scopes must be an array of strings", name, scope_path, code = "invalid-security-requirement")
				valid = false
				continue
			}
			scopes := make([]string, len(values))
			for value, scope_index in values {
				text, is_string := value.(json.String)
				if !is_string {
					diagnostics.add(issues, "Security scope must be a string", name, diagnostics.child_path(scope_path, fmt.aprint(scope_index)), code = "invalid-security-requirement")
					valid = false
					continue
				}
				scopes[scope_index] = string(text)
			}
			requirement[name] = scopes
		}
		requirements[index] = requirement
	}
	return requirements, valid
}
