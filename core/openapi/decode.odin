package openapi

import "core:encoding/json"
import "core:fmt"
import "../diagnostics"

// Decoded strings and collections use context.allocator, independently of the input buffer.
decode :: proc(source: []byte, issues: ^diagnostics.Manager = nil) -> (OpenApiSpec, bool) {
	spec: OpenApiSpec
	if err := json.unmarshal(source, &spec, .JSON); err != nil {
		diagnostics.add(issues, "Failed to parse specification JSON", fmt.aprint(err), code = "invalid-specification-json")
		return {}, false
	}

	return spec, true
}
