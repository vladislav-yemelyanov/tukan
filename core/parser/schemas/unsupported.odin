package schemas

import "core:strings"
import "../../diagnostics"

@(private)
warn_schema_keyword :: proc(name: string, issues: ^diagnostics.Manager, path: string) {
	if strings.has_prefix(name, "x-") { return }

	// Descriptive metadata does not affect generated types and needs no warning.
	switch name {
	case "title", "description", "example", "examples", "deprecated", "externalDocs", "xml", "$comment": return
	}
	diagnostics.add(issues, "Unsupported schema keyword is ignored", name, diagnostics.child_path(path, name), .warning, "unsupported-schema-keyword")
}
