package generators

import "core:fmt"
import "core:strings"
import ir "../ir"

@(private)
security_documentation :: proc(requirements: []ir.SecurityRequirement) -> string {
	if len(requirements) == 0 { return "Authentication: none required." }
	alternatives := make([dynamic]string)
	for requirement in requirements {
		schemes := make([dynamic]string)
		for name in sorted_keys(requirement) {
			text := name
			if len(requirement[name]) > 0 {
				scopes, _ := strings.join(requirement[name], ", ")
				text = fmt.aprintf("%s (scopes: %s)", name, scopes)
			}
			append(&schemes, text)
		}
		if len(schemes) == 0 { append(&alternatives, "anonymous access"); continue }
		text, _ := strings.join(schemes[:], " AND ")
		if len(schemes) > 1 { text = fmt.aprintf("(%s)", text) }
		append(&alternatives, text)
	}
	text, _ := strings.join(alternatives[:], " OR ")
	return fmt.aprintf("Authentication: %s.", text)
}

