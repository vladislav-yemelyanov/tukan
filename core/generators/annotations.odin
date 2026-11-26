package generators

import "core:encoding/json"
import "core:fmt"
import "core:strings"
import ir "../ir"

@(private)
model_annotations :: proc(model: ir.Model) -> json.Object {
	switch value in model {
	case ir.Primitive: return value.annotations
	case ir.Enumeration: return value.annotations
	case ir.Reference: return value.annotations
	case ir.ArrayModel: return value.annotations
	case ir.ObjectModel: return value.annotations
	case ir.UnknownModel: return value.annotations
	}
	return nil
}

// Generated operation documentation belongs to the output copy, never the input model.
@(private)
with_documentation :: proc(model: ir.Model, source: string) -> ir.Model {
	text := source
	annotations := make(json.Object)
	for key, value in model_annotations(model) { annotations[key] = value }
	if description, present := annotations["description"].(json.String); present {
		text = fmt.aprintf("%s\n%s", string(description), text)
	}
	annotations["description"] = json.String(text)
	result := model
	switch &value in result {
	case ir.Primitive: value.annotations = annotations
	case ir.Enumeration: value.annotations = annotations
	case ir.Reference: value.annotations = annotations
	case ir.ArrayModel: value.annotations = annotations
	case ir.ObjectModel: value.annotations = annotations
	case ir.UnknownModel: value.annotations = annotations
	}
	return result
}

@(private)
collect_annotation_comments :: proc(model: ir.Model, prefix: string, parts: ^[dynamic]string) {
	annotations := model_annotations(model)
	for name in sorted_keys(cast(map[string]json.Value)annotations) {
		if name == "description" { continue }
		encoded, _ := json.marshal(annotations[name], {sort_maps_by_key = true})
		note := ""
		if name == "default" { note = " (defaults not applied)" }
		append(parts, fmt.aprintf("%s%s: %s%s", prefix, name, string(encoded), note))
	}

	switch value in model {
	case ir.ArrayModel: collect_annotation_comments(value.items^, fmt.aprintf("%sitems.", prefix), parts)
	case ir.ObjectModel:
		if additional, present := value.additional_properties.?; present { collect_annotation_comments(additional^, fmt.aprintf("%sadditionalProperties.", prefix), parts) }
	case ir.Primitive, ir.Reference, ir.Enumeration, ir.UnknownModel:
	}
}

// Source text must never close a comment or create an unexpected line.
@(private)
documentation_comment :: proc(source: string, language: GenerationLanguage, indent := "") -> string {
	text := source
	if text == "" { return "" }
	for pair in ([6][2]string{{"/*", "/ *"}, {"*/", "* /"}, {"\r", ""}, {"\u0085", "\\u0085"}, {"\u2028", "\\u2028"}, {"\u2029", "\\u2029"}}) {
		text, _ = strings.replace_all(text, pair[0], pair[1])
	}
	builder := strings.builder_make()
	if language == .dart {
		for line in strings.split_lines(text) { fmt.sbprintf(&builder, "%s/// %s\n", indent, line) }
	} else {
		fmt.sbprintf(&builder, "%s/**\n", indent)
		for line in strings.split_lines(text) { fmt.sbprintf(&builder, "%s * %s\n", indent, line) }
		fmt.sbprintf(&builder, "%s */\n", indent)
	}
	return strings.to_string(builder)
}

@(private)
annotation_comment :: proc(model: ir.Model, language: GenerationLanguage, indent := "") -> string {
	parts := make([dynamic]string)
	if description, present := model_annotations(model)["description"].(json.String); present { append(&parts, string(description)) }
	rules := make([dynamic]string)
	collect_annotation_comments(model, "", &rules)
	for rule in rules { append(&parts, rule) }
	text, _ := strings.join(parts[:], "\n")
	return documentation_comment(text, language, indent)
}

// Flatten descriptive settings into readable comment lines, including extension fields.
@(private)
collect_setting_comments :: proc(value: json.Value, prefix: string, parts: ^[dynamic]string) {
	if object, is_object := value.(json.Object); is_object {
		for key in sorted_keys(cast(map[string]json.Value)object) {
			collect_setting_comments(object[key], fmt.aprintf("%s.%s", prefix, key), parts)
		}
		return
	}
	text := ""
	if string_value, is_string := value.(json.String); is_string {
		text = string(string_value)
	} else {
		encoded, _ := json.marshal(value, {sort_maps_by_key = true})
		text = string(encoded)
	}
	append(parts, fmt.aprintf("%s: %s", prefix, text))
}

