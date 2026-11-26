package generators

import "core:encoding/json"
import virtual "core:mem/virtual"
import "core:strings"
import "core:testing"
import ir "../ir"

@(test)
annotation_comments_are_safe_and_preserve_original_values :: proc(t: ^testing.T) {
	arena: virtual.Arena
	if !testing.expect(t, virtual.arena_init_growing(&arena) == nil, "arena should initialize") { return }
	defer virtual.arena_destroy(&arena)
	context.allocator = virtual.arena_allocator(&arena)

	annotations := make(json.Object)
	annotations["default"] = json.String("*/ /* <tag> & $value\nnext\u2028line")
	annotations["minLength"] = json.Integer(0)
	model: ir.Model = ir.Primitive{type = .string, annotations = annotations}
	for language in GenerationLanguage {
		comment := annotation_comment(model, language)
		testing.expect(t, strings.contains(comment, "defaults not applied"), "documentation must not promise default insertion")
		testing.expect(t, !strings.contains(comment, "*/ /*"), "source comment delimiters must be neutralized")
		testing.expect(t, !strings.contains(comment, "\u2028"), "line separators must not create source lines")
	}
	testing.expect_value(t, string(annotations["default"].(json.String)), "*/ /* <tag> & $value\nnext\u2028line")
	testing.expect_value(t, len(annotations), 2)
	_, added := annotations["sourcePath"]
	testing.expect(t, !added, "documentation generation must preserve source annotations")
}

@(test)
operation_documentation_uses_owned_annotations :: proc(t: ^testing.T) {
	arena: virtual.Arena
	if !testing.expect(t, virtual.arena_init_growing(&arena) == nil, "arena should initialize") { return }
	defer virtual.arena_destroy(&arena)
	context.allocator = virtual.arena_allocator(&arena)
	annotations := make(json.Object)
	annotations["description"] = json.String("Original description.")
	model: ir.Model = ir.Reference{name = "Input", annotations = annotations}
	documented := with_documentation(model, "POST /upload")

	testing.expect_value(t, string(annotations["description"].(json.String)), "Original description.")
	comment := annotation_comment(documented, .dart)
	testing.expect(t, strings.contains(comment, "/// Original description.\n/// POST /upload"), "operation documentation should retain the payload description")
	testing.expect(t, !strings.contains(comment, "constraints"), "plain descriptions must not be labelled as validation rules")
}
