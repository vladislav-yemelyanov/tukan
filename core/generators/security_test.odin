package generators

import "core:strings"
import virtual "core:mem/virtual"
import "core:testing"
import ir "../ir"

@(test)
security_comments_preserve_inheritance_and_alternatives :: proc(t: ^testing.T) {
	arena: virtual.Arena
	if !testing.expect(t, virtual.arena_init_growing(&arena) == nil, "arena should initialize") { return }
	defer virtual.arena_destroy(&arena)
	context.allocator = virtual.arena_allocator(&arena)
	bearer := make(ir.SecurityRequirement)
	bearer["Bearer"] = nil
	document := ir.Document{security = []ir.SecurityRequirement{bearer}}
	inherited := operation_documentation(&document, "/users", "get", {})
	testing.expect(t, strings.contains(inherited, "Authentication: Bearer."), "absent operation security must inherit document settings")
	public := operation_documentation(&document, "/users", "post", {security = make([]ir.SecurityRequirement, 0)})
	testing.expect(t, strings.contains(public, "Authentication: none required."), "explicit empty security must override document settings")
	combined := make(ir.SecurityRequirement)
	combined["Bearer"] = nil
	combined["Key"] = nil
	oauth := make(ir.SecurityRequirement)
	oauth["OAuth"] = []string{"read:user"}
	testing.expect_value(t, security_documentation([]ir.SecurityRequirement{combined, oauth}), "Authentication: (Bearer AND Key) OR OAuth (scopes: read:user).")
	testing.expect_value(t, security_documentation([]ir.SecurityRequirement{make(ir.SecurityRequirement), oauth}), "Authentication: anonymous access OR OAuth (scopes: read:user).")
	testing.expect(t, document.security != nil, "documentation must preserve the original settings")
}
