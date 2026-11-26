package generators

import "core:encoding/json"
import "core:fmt"
import "core:strings"
import "../diagnostics"
import ir "../ir"

@(private)
GenerationLanguage :: enum { typescript, dart }

@(private)
generation_language_name :: proc(language: GenerationLanguage) -> string {
	switch language {
	case .typescript: return "TypeScript"
	case .dart: return "Dart"
	}
	return ""
}

@(private)
source_path :: proc(model: ir.Model, fallback: string) -> string {
	path := ""
	switch value in model {
	case ir.Primitive: path = value.source_path
	case ir.Reference: path = value.source_path
	case ir.Enumeration: path = value.source_path
	case ir.ArrayModel: path = value.source_path
	case ir.ObjectModel: path = value.source_path
	case ir.UnknownModel: path = value.source_path
	}
	if path != "" { return path }
	return fallback
}

@(private)
integer_loses_precision :: proc(value: json.Value) -> bool {
	integer, ok := value.(json.Integer)
	return ok && i128(f64(integer)) != i128(integer)
}

// Each alias has at most one next alias. Object declarations terminate the chain.
@(private)
validate_aliases :: proc(document: ^ir.Document, issues: ^diagnostics.Manager, language: GenerationLanguage) -> bool {
	finished := make(map[string]bool)
	valid := true
	for name in sorted_keys(document.schemas) {
		chain := make([dynamic]string)
		positions := make(map[string]int)
		current := name
		for {
			if finished[current] { break }
			if start, seen := positions[current]; seen {
				cycle, _ := strings.join(chain[start:], " -> ")
				model := document.schemas[current]
				path := source_path(model, diagnostics.child_path("#/components/schemas", current))
				diagnostics.add(issues, "Reference cycle cannot be represented by this language", cycle, path, .error, "unsupported-alias-cycle", generation_language_name(language))
				valid = false
				break
			}
			model, found := document.schemas[current]
			if !found { break }
			positions[current] = len(chain)
			append(&chain, current)
			// Dart typedefs cannot recurse through collections either.
			if language == .dart {
				for array, ok := model.(ir.ArrayModel); ok; array, ok = model.(ir.ArrayModel) { model = array.items^ }
			}
			ref, is_reference := model.(ir.Reference)
			if !is_reference { break }
			current = ref.name
		}
		for visited in chain { finished[visited] = true }
	}
	return valid
}

@(private)
typescript_index_widens :: proc(value: ir.ObjectModel) -> bool {
	additional, present := value.additional_properties.?
	if !present { return false }
	if _, unknown := additional^.(ir.UnknownModel); unknown { return false }
	additional_type := model_to_ts(additional^)
	allows_null := strings.has_suffix(additional_type, " | null")
	base_type := strings.trim_suffix(additional_type, " | null")
	for _, field in value.fields {
		if !field.required { return true }
		field_type := model_to_ts(field.model)
		if field_type == additional_type { continue }
		if allows_null && strings.trim_suffix(field_type, " | null") == base_type { continue }
		// Scalar enum literals already fit the corresponding primitive index type.
		if values, is_enum := field.model.(ir.Enumeration); is_enum {
			if values.nullable && !allows_null { return true }
			fits := true
			for item in values.values {
				switch item in item {
				case json.String: fits = fits && base_type == "string"
				case json.Integer, json.Float: fits = fits && base_type == "number"
				case json.Boolean: fits = fits && base_type == "boolean"
				case json.Null: fits = fits && allows_null
				case json.Array, json.Object: fits = false
				}
			}
			if fits { continue }
		}
		return true
	}
	return false
}

@(private)
check_model_diagnostics :: proc(model: ir.Model, fallback: string, language: GenerationLanguage, issues: ^diagnostics.Manager) {
	path := source_path(model, fallback)
	language_name := generation_language_name(language)
	switch value in model {
	case ir.Enumeration:
		if language != .typescript { return }
		for item, index in value.values {
			if !integer_loses_precision(item) { continue }
			diagnostics.add(issues, "Enum integer cannot be represented exactly by TypeScript number", fmt.aprint(item), diagnostics.child_path(diagnostics.child_path(path, "enum"), fmt.aprint(index)), .warning, "enum-integer-precision-loss", language_name)
		}
	case ir.ArrayModel:
		check_model_diagnostics(value.items^, diagnostics.child_path(path, "items"), language, issues)
	case ir.ObjectModel:
		if language == .typescript && typescript_index_widens(value) {
			diagnostics.add(issues, "Additional property index signature may admit named field values or optional undefined beyond the declared value type", "", diagnostics.child_path(path, "additionalProperties"), .warning, "widened-additional-properties", language_name)
		}
		for name in sorted_keys(value.fields) {
			check_model_diagnostics(value.fields[name].model, diagnostics.child_path(diagnostics.child_path(path, "properties"), name), language, issues)
		}
		if additional, present := value.additional_properties.?; present {
			check_model_diagnostics(additional^, diagnostics.child_path(path, "additionalProperties"), language, issues)
		}
	case ir.Primitive, ir.Reference, ir.UnknownModel:
	}
}

@(private)
validate_generation :: proc(document: ^ir.Document, issues: ^diagnostics.Manager, language: GenerationLanguage) -> bool {
	valid := validate_aliases(document, issues, language)
	if language != .typescript { return valid }

	for name in sorted_keys(document.schemas) {
		check_model_diagnostics(document.schemas[name], diagnostics.child_path("#/components/schemas", name), language, issues)
	}
	for path in sorted_keys(document.paths) {
		for method in sorted_keys(document.paths[path]) {
			operation := document.paths[path][method]
			operation_path := diagnostics.child_path(diagnostics.child_path("#/paths", path), method)
			for _, group in operation.parameters { check_model_diagnostics(group, diagnostics.child_path(operation_path, "parameters"), language, issues) }
			if body, present := operation.request_body.?; present {
				body_path := body.source_path
				if body_path == "" { body_path = diagnostics.child_path(operation_path, "requestBody") }

				for media, model in body.content { check_model_diagnostics(model, diagnostics.child_path(diagnostics.child_path(body_path, "content"), media), language, issues) }
			}
			for status, content in operation.responses {
				for media, model in content {
					check_model_diagnostics(model, diagnostics.child_path(diagnostics.child_path(diagnostics.child_path(diagnostics.child_path(operation_path, "responses"), status), "content"), media), language, issues)
				}
			}
		}
	}
	return valid
}
