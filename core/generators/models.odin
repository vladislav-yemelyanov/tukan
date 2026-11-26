package generators

import ir "../ir"

@(private)
model_nullable :: proc(model: ir.Model, schemas: map[string]ir.Model) -> bool {
	current := model
	// Reference cycles are legal; stop after every possible schema has been visited.
	for _ in 0..=len(schemas) {
		switch value in current {
		case ir.Reference:
			if value.nullable { return true }
			target, found := schemas[value.name]
			if !found { return false }
			current = target
		case ir.Primitive: return value.nullable
		case ir.Enumeration: return value.nullable
		case ir.ArrayModel: return value.nullable
		case ir.ObjectModel: return value.nullable
		case ir.UnknownModel: return true
		}
	}
	return false
}

