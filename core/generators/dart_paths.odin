package generators

import "core:fmt"
import "core:slice"
import "core:strconv"
import "core:strings"
import ir "../ir"

@(private)
CapturedParam :: struct {
	raw_name:   string,
	dart_name:  string,
	field_name: string,
	dart_type:  string,
	model:      ir.Model,
	model_path: string,
	nullable:   bool,
}

@(private)
DartOpSlot :: struct {
	method_name:    string,
	with_name:      string,
	ctor_param:     string,
	field_name:     string,
	field_type:     string,
	required:       bool,
	encode_to_json: bool,
	is_named_obj:   bool,
	schema_key:     string,
	obj_model:      ir.ObjectModel,
	type_name:      string,
}

@(private)
DartErrorVariant :: struct {
	model:        ir.Model,
	dart_type:    string,
	first_status: string,
	getter_name:  string,
	class_name:   string,
}

@(private)
DartErrorEntry :: struct {
	code:        int,
	expr:        string,
	variant_idx: int,
}

@(private)
DartOpPlan :: struct {
	full_path:                 string,
	method:                    string,
	operation:                 ir.Operation,
	binding:                   OperationBinding,
	bound_params:              []CapturedParam,
	has_path_binding:          bool,
	all_path_bound:            bool,
	path_slot_idx:             int,
	query_slot_idx:            int,
	header_slot_idx:           int,
	cookie_slot_idx:           int,
	body_slot_idx:             int,
	slots:                     [dynamic]DartOpSlot,
	req_indices:               [dynamic]int,
	opt_indices:               [dynamic]int,
	has_content_type_selector: bool,
	has_fixed_content_type:    bool,
	fixed_content_type:        string,
	default_content_type:      string,
	res_type:                  string,
	decode_expr:               string,
	error_type:                string,
	error_union_name:          string,
	error_variants:            [dynamic]DartErrorVariant,
	error_entries:             [dynamic]DartErrorEntry,
	default_error_expr:        string,
	default_error_variant_idx: int,
}

@(private)
DartPathNode :: struct {
	segment:          string,
	is_param:         bool,
	full_path:        string,
	has_ops:          bool,
	operations:       map[string]ir.Operation,
	class_name:       string,
	bound_class_name: string,
	member_name:      string,
	op_state_classes: map[string][dynamic]string,
	op_plans:         map[string]DartOpPlan,
	bind_param:       bool,
	own_param:        CapturedParam,
	captured_params:  [dynamic]CapturedParam,
	bound_params:     [dynamic]CapturedParam,
	children:         map[string]^DartPathNode,
	child_keys:       [dynamic]string,
}

@(private)
SubtreeOperation :: struct {
	full_path: string,
	method:    string,
	operation: ir.Operation,
	binding:   OperationBinding,
}

@(private)
emit_dart_paths :: proc(
	builder: ^strings.Builder,
	document: ^ir.Document,
	dart_schemas: map[string]ir.Model,
	names: ^GeneratorNames,
	bindings: map[string]map[string]OperationBinding,
) {
	if len(document.paths) == 0 { return }

	used_types := make(map[string]bool)
	for builtin in ([11]string{"List", "Map", "Object", "Set", "Iterable", "String", "int", "num", "bool", "dynamic", "void"}) {
		used_types[builtin] = true
	}
	for _, type_id in names.types { used_types[type_id] = true }

	operation_request_name := "OperationRequest"
	for used_types[operation_request_name] {
		operation_request_name = fmt.aprintf("%s_", operation_request_name)
	}
	used_types[operation_request_name] = true

	paths_name := "Paths"
	for used_types[paths_name] {
		paths_name = fmt.aprintf("%s_", paths_name)
	}
	used_types[paths_name] = true

	fmt.sbprintf(builder, "typedef %s<T, E> = ({{\n", operation_request_name)
	fmt.sbprintln(builder, "  String method,")
	fmt.sbprintln(builder, "  String path,")
	fmt.sbprintln(builder, "  Map<String, dynamic>? pathParams,")
	fmt.sbprintln(builder, "  Map<String, dynamic>? query,")
	fmt.sbprintln(builder, "  Map<String, dynamic>? headers,")
	fmt.sbprintln(builder, "  Map<String, dynamic>? cookie,")
	fmt.sbprintln(builder, "  Object? body,")
	fmt.sbprintln(builder, "  String? contentType,")
	fmt.sbprintln(builder, "  T Function(Object? data) decodeResponse,")
	fmt.sbprintln(builder, "  Map<int, E Function(Object? data)?> errorDecoders,")
	fmt.sbprintln(builder, "  E Function(Object? data)? defaultErrorDecoder,")
	fmt.sbprintln(builder, "});\n")

	root := build_dart_path_tree(document.paths, paths_name)
	analyze_dart_path_bindings(root, nil, bindings, dart_schemas, names)
	build_dart_operation_plans(root, bindings, dart_schemas, names)
	assign_dart_path_names(root, &used_types, "Path", names)

	fmt.sbprintf(builder, "abstract final class %s {{\n", paths_name)
	if root.has_ops {
		fmt.sbprintf(builder, "  static String get path => %s;\n", dart_json_key(root.full_path))
	}
	for key in root.child_keys {
		child := root.children[key]
		fmt.sbprintf(builder, "  static const %s %s = %s._();\n", child.class_name, child.member_name, child.class_name)
	}
	if root.has_ops {
		for method in sorted_keys(root.operations) {
			entry_class := root.op_state_classes[method][0]
			doc := documentation_comment(operation_documentation(document, root.full_path, method, root.operations[method]), .dart, "  ")
			if doc != "" { fmt.sbprint(builder, doc) }
			fmt.sbprintf(builder, "  static const %s %s = %s._();\n", entry_class, method, entry_class)
		}
	}
	fmt.sbprintln(builder, "}\n")

	if root.has_ops {
		for method in sorted_keys(root.operations) {
			emit_dart_operation_states(
				builder,
				document,
				root.op_plans[method],
				root.op_state_classes[method][:],
				dart_schemas,
				names,
				operation_request_name,
			)
		}
	}

	for key in root.child_keys {
		emit_dart_path_nodes(builder, root.children[key], document, dart_schemas, names, operation_request_name)
	}
}

@(private)
build_dart_path_tree :: proc(paths: map[string]map[string]ir.Operation, root_name: string) -> ^DartPathNode {
	root := new(DartPathNode)
	root.class_name = root_name
	root.children = make(map[string]^DartPathNode)
	root.op_state_classes = make(map[string][dynamic]string)
	root.op_plans = make(map[string]DartOpPlan)

	for path in sorted_keys(paths) {
		current := root
		trimmed := strings.trim(path, "/")
		if trimmed != "" {
			for seg in strings.split(trimmed, "/") {
				if seg == "" { continue }
				is_param := strings.has_prefix(seg, "{") && strings.has_suffix(seg, "}") && len(seg) > 2
				clean_seg := seg
				prefix := "s:"
				if is_param {
					clean_seg = seg[1:len(seg) - 1]
					prefix = "p:"
				}
				key := fmt.aprintf("%s%s", prefix, clean_seg)
				child, exists := current.children[key]
				if !exists {
					child = new(DartPathNode)
					child.segment = clean_seg
					child.is_param = is_param
					child.children = make(map[string]^DartPathNode)
					child.op_state_classes = make(map[string][dynamic]string)
					child.op_plans = make(map[string]DartOpPlan)
					current.children[key] = child
				}
				current = child
			}
		}
		current.has_ops = true
		current.full_path = path
		current.operations = paths[path]
	}

	sort_dart_path_children(root)
	return root
}

@(private)
sort_dart_path_children :: proc(node: ^DartPathNode) {
	static_keys := make([dynamic]string)
	param_keys := make([dynamic]string)
	for key, child in node.children {
		if child.is_param { append(&param_keys, key) } else { append(&static_keys, key) }
	}
	slice.sort(static_keys[:])
	slice.sort(param_keys[:])
	for key in static_keys {
		append(&node.child_keys, key)
		sort_dart_path_children(node.children[key])
	}
	for key in param_keys {
		append(&node.child_keys, key)
		sort_dart_path_children(node.children[key])
	}
}

@(private)
clone_captured_params :: proc(params: []CapturedParam) -> [dynamic]CapturedParam {
	copy := make([dynamic]CapturedParam, len(params))
	for param, index in params {
		copy[index] = param
	}
	return copy
}

@(private)
collect_subtree_operations :: proc(
	node: ^DartPathNode,
	bindings: map[string]map[string]OperationBinding,
	out: ^[dynamic]SubtreeOperation,
) {
	if node.has_ops {
		for method in sorted_keys(node.operations) {
			append(out, SubtreeOperation{
				full_path = node.full_path,
				method    = method,
				operation = node.operations[method],
				binding   = bindings[node.full_path][method],
			})
		}
	}
	for key in node.child_keys {
		collect_subtree_operations(node.children[key], bindings, out)
	}
}

@(private)
can_bind_param_node :: proc(
	node: ^DartPathNode,
	bindings: map[string]map[string]OperationBinding,
	dart_schemas: map[string]ir.Model,
	names: ^GeneratorNames,
	ancestor_params: []CapturedParam,
) -> (CapturedParam, bool) {
	for param in ancestor_params {
		if param.raw_name == node.segment {
			return {}, false
		}
	}

	subtree_ops := make([dynamic]SubtreeOperation)
	collect_subtree_operations(node, bindings, &subtree_ops)
	if len(subtree_ops) == 0 {
		return {}, false
	}

	first_type := ""
	first_nullable := false
	first_model: ir.Model
	first_model_path := ""

	for op, index in subtree_ops {
		schema_key, has_path_schema := op.binding.parameters[.path]
		if !has_path_schema { return {}, false }
		group, has_path_group := op.operation.parameters[.path]
		if !has_path_group { return {}, false }
		entry, has_field := group.fields[node.segment]
		if !has_field || !entry.required { return {}, false }

		schema_path := child_path("schema", schema_key)
		field_path := child_path(child_path(schema_path, "fields"), node.segment)
		dart_type := model_type(entry.model, field_path, names, dart_schemas)
		nullable := model_nullable(entry.model, dart_schemas)

		if index == 0 {
			first_type = dart_type
			first_nullable = nullable
			first_model = entry.model
			first_model_path = field_path
			continue
		}

		if dart_type != first_type || nullable != first_nullable || !same_payload(first_model, entry.model) {
			return {}, false
		}
	}

	used_fields := make(map[string]bool)
	for param in ancestor_params {
		used_fields[param.field_name] = true
	}
	for reserved in ([6]string{"_pathParams", "_query", "_headers", "_cookie", "_body", "_contentType"}) {
		used_fields[reserved] = true
	}
	// Reserve dart_json_encode local pattern variables so nested encoders never shadow a field.
	for i in 0..<10 {
		used_fields[fmt.aprintf("_v%d", i)] = true
	}

	dart_name := readable_name(node.segment, true)
	field_name := allocate_name(&used_fields, fmt.aprintf("_%s", dart_name))
	return CapturedParam{
		raw_name   = node.segment,
		dart_name  = dart_name,
		field_name = field_name,
		dart_type  = first_type,
		model      = first_model,
		model_path = first_model_path,
		nullable   = first_nullable,
	}, true
}

@(private)
analyze_dart_path_bindings :: proc(
	node: ^DartPathNode,
	ancestor_params: []CapturedParam,
	bindings: map[string]map[string]OperationBinding,
	dart_schemas: map[string]ir.Model,
	names: ^GeneratorNames,
) {
	node.captured_params = clone_captured_params(ancestor_params)

	if node.is_param {
		if own, ok := can_bind_param_node(node, bindings, dart_schemas, names, ancestor_params); ok {
			node.bind_param = true
			node.own_param = own
			node.bound_params = clone_captured_params(ancestor_params)
			append(&node.bound_params, own)
		} else {
			node.bind_param = false
			node.bound_params = clone_captured_params(ancestor_params)
		}
	} else {
		node.bound_params = clone_captured_params(ancestor_params)
	}

	for key in node.child_keys {
		analyze_dart_path_bindings(node.children[key], node.bound_params[:], bindings, dart_schemas, names)
	}
}

@(private)
build_dart_operation_plans :: proc(
	node: ^DartPathNode,
	bindings: map[string]map[string]OperationBinding,
	dart_schemas: map[string]ir.Model,
	names: ^GeneratorNames,
) {
	if node.has_ops {
		for method in sorted_keys(node.operations) {
			node.op_plans[method] = create_dart_op_plan(
				node.full_path,
				method,
				node.operations[method],
				bindings[node.full_path][method],
				node.bound_params[:],
				dart_schemas,
				names,
			)
		}
	}
	for key in node.child_keys {
		build_dart_operation_plans(node.children[key], bindings, dart_schemas, names)
	}
}

@(private)
add_dart_error_variant :: proc(
	plan: ^DartOpPlan,
	model: ir.Model,
	status: string,
	names: ^GeneratorNames,
	dart_schemas: map[string]ir.Model,
) -> int {
	for previous, index in plan.error_variants {
		if same_payload(previous.model, model) { return index }
	}
	append(&plan.error_variants, DartErrorVariant{
		model        = model,
		dart_type    = model_type(model, "", names, dart_schemas),
		first_status = status,
	})
	return len(plan.error_variants) - 1
}

@(private)
create_dart_op_plan :: proc(
	full_path: string,
	method: string,
	operation: ir.Operation,
	binding: OperationBinding,
	bound_params: []CapturedParam,
	dart_schemas: map[string]ir.Model,
	names: ^GeneratorNames,
) -> DartOpPlan {
	plan := DartOpPlan{
		full_path                 = full_path,
		method                    = method,
		operation                 = operation,
		binding                   = binding,
		bound_params              = bound_params,
		all_path_bound            = operation_path_params_all_bound(operation, bound_params),
		path_slot_idx             = -1,
		query_slot_idx            = -1,
		header_slot_idx           = -1,
		cookie_slot_idx           = -1,
		body_slot_idx             = -1,
		slots                     = make([dynamic]DartOpSlot),
		req_indices               = make([dynamic]int),
		opt_indices               = make([dynamic]int),
		error_type                = "Never",
		error_variants            = make([dynamic]DartErrorVariant),
		error_entries             = make([dynamic]DartErrorEntry),
		default_error_expr        = "null",
		default_error_variant_idx = -1,
	}

	if path_schema_key, has_path_binding := binding.parameters[.path]; has_path_binding {
		plan.has_path_binding = true
		if !plan.all_path_bound {
			group := operation.parameters[.path]
			param_type := names.types[child_path("schema", path_schema_key)]
			is_req := group_has_required_field(group)
			slot := DartOpSlot{
				method_name    = "pathParams",
				with_name      = "withPathParams",
				ctor_param     = "pathParams",
				field_name     = "_pathParams",
				field_type     = "Map<String, dynamic>" if is_req else "Map<String, dynamic>?",
				required       = is_req,
				encode_to_json = true,
				is_named_obj   = true,
				schema_key     = path_schema_key,
				obj_model      = group,
				type_name      = param_type if is_req else dart_nullable_type(param_type, true),
			}
			plan.path_slot_idx = len(plan.slots)
			append(&plan.slots, slot)
		}
	}

	ParamSlotSpec :: struct {
		loc:         ir.ParameterLocation,
		method_name: string,
		with_name:   string,
		ctor_param:  string,
		field_name:  string,
		slot_idx:    ^int,
	}
	non_path_specs := [3]ParamSlotSpec{
		{.query, "query", "withQuery", "query", "_query", &plan.query_slot_idx},
		{.header, "headers", "withHeaders", "headers", "_headers", &plan.header_slot_idx},
		{.cookie, "cookie", "withCookie", "cookie", "_cookie", &plan.cookie_slot_idx},
	}

	for spec in non_path_specs {
		schema_key, ok := binding.parameters[spec.loc]
		if !ok { continue }
		group := operation.parameters[spec.loc]
		param_type := names.types[child_path("schema", schema_key)]
		is_req := group_has_required_field(group)
		slot := DartOpSlot{
			method_name    = spec.method_name,
			with_name      = spec.with_name,
			ctor_param     = spec.ctor_param,
			field_name     = spec.field_name,
			field_type     = "Map<String, dynamic>" if is_req else "Map<String, dynamic>?",
			required       = is_req,
			encode_to_json = true,
			is_named_obj   = true,
			schema_key     = schema_key,
			obj_model      = group,
			type_name      = param_type if is_req else dart_nullable_type(param_type, true),
		}
		spec.slot_idx^ = len(plan.slots)
		append(&plan.slots, slot)
	}

	if req_body, has_body := operation.request_body.?; has_body && len(binding.request_media) > 0 {
		media_keys := sorted_keys(binding.request_media)
		first_model := binding.request_media[media_keys[0]]
		first_type := model_type(first_model, "", names, dart_schemas)
		all_same := true
		for media in media_keys[1:] {
			if model_type(binding.request_media[media], "", names, dart_schemas) != first_type {
				all_same = false
				break
			}
		}

		body_type := first_type if all_same else "Object?"
		if !req_body.required && body_type != "dynamic" && !strings.has_suffix(body_type, "?") {
			body_type = fmt.aprintf("%s?", body_type)
		}

		slot := DartOpSlot{
			method_name = "body",
			with_name   = "withBody",
			ctor_param  = "body",
			field_name  = "_body",
			field_type  = "Object?",
			required    = req_body.required,
			type_name   = body_type,
		}
		if all_same {
			if body_schema_key, body_obj, is_named_obj := resolve_named_object_schema(first_model, dart_schemas); is_named_obj {
				slot.is_named_obj = true
				slot.schema_key = body_schema_key
				slot.obj_model = body_obj
			}
		}
		plan.body_slot_idx = len(plan.slots)
		append(&plan.slots, slot)

		if len(media_keys) == 1 {
			plan.has_fixed_content_type = true
			plan.fixed_content_type = media_keys[0]
		} else {
			default_media := media_keys[0]
			if _, has_json := binding.request_media["application/json"]; has_json {
				default_media = "application/json"
			}
			plan.has_content_type_selector = true
			plan.default_content_type = default_media
		}
	}

	for slot, idx in plan.slots {
		if slot.required {
			append(&plan.req_indices, idx)
		} else {
			append(&plan.opt_indices, idx)
		}
	}

	// Compute success response type and decoder.
	success_models := make([dynamic]ir.Model)
	has_empty_2xx := false
	for status in sorted_keys(binding.responses) {
		if !strings.has_prefix(status, "2") { continue }
		content := binding.responses[status]
		if len(content) == 0 {
			has_empty_2xx = true
			continue
		}
		for media in sorted_keys(content) {
			model := content[media]
			if !contains_payload(success_models[:], model) {
				append(&success_models, model)
			}
		}
	}

	plan.res_type = "void"
	plan.decode_expr = "(Object? _) {}"
	if len(success_models) == 1 {
		model := success_models[0]
		nullable := has_empty_2xx || model_nullable(model, dart_schemas)
		plan.res_type = model_type(model, "", names, dart_schemas)
		if nullable && !model_nullable(model, dart_schemas) {
			plan.res_type = dart_nullable_type(plan.res_type, true)
		}
		decoded := dart_json_decode(model, "", "data", nullable, names, dart_schemas)
		plan.decode_expr = fmt.aprintf("(Object? data) => %s", decoded)
	} else if len(success_models) > 1 {
		plan.res_type = "Object?"
		plan.decode_expr = "(Object? data) => data"
	}

	for status in sorted_keys(binding.responses) {
		if status == "default" {
			models := collect_distinct_media_models(binding.responses[status])
			if len(models) == 1 {
				model := models[0]
				decoded := dart_json_decode(model, "", "data", model_nullable(model, dart_schemas), names, dart_schemas)
				plan.default_error_expr = decoded
				plan.default_error_variant_idx = add_dart_error_variant(&plan, model, status, names, dart_schemas)
			}
			continue
		}
		if !strings.has_prefix(status, "4") && !strings.has_prefix(status, "5") { continue }
		code, ok := strconv.parse_int(status)
		if !ok { continue }
		models := collect_distinct_media_models(binding.responses[status])
		if len(models) == 1 {
			model := models[0]
			decoded := dart_json_decode(model, "", "data", model_nullable(model, dart_schemas), names, dart_schemas)
			variant_idx := add_dart_error_variant(&plan, model, status, names, dart_schemas)
			append(&plan.error_entries, DartErrorEntry{code, decoded, variant_idx})
		} else {
			append(&plan.error_entries, DartErrorEntry{code, "null", -1})
		}
	}

	if len(plan.error_variants) == 0 {
		plan.error_type = "Never"
	} else if len(plan.error_variants) == 1 {
		plan.error_type = plan.error_variants[0].dart_type
	}

	return plan
}

@(private)
allocate_op_state_classes :: proc(
	used_types: ^map[string]bool,
	op_base: string,
	req_count: int,
) -> [dynamic]string {
	classes := make([dynamic]string)
	append(&classes, allocate_name(used_types, op_base))
	if req_count == 0 {
		return classes
	}
	if req_count == 1 {
		append(&classes, allocate_name(used_types, fmt.aprintf("%sReady", op_base)))
		return classes
	}

	state_count := (1 << uint(req_count)) if req_count == 2 else (req_count + 1)
	for s in 1..<state_count {
		if s == state_count - 1 {
			append(&classes, allocate_name(used_types, fmt.aprintf("%sReady", op_base)))
		} else {
			append(&classes, allocate_name(used_types, fmt.aprintf("%sS%d", op_base, s)))
		}
	}
	return classes
}

@(private)
assign_dart_path_names :: proc(
	node: ^DartPathNode,
	used_types: ^map[string]bool,
	class_prefix: string,
	names: ^GeneratorNames,
) {
	used_members := make(map[string]bool)
	for member in ([4]string{"hashCode", "runtimeType", "toString", "noSuchMethod"}) {
		used_members[member] = true
	}
	if node.has_ops {
		used_members["path"] = true
		for method in sorted_keys(node.operations) {
			used_members[method] = true
			op_base := fmt.aprintf("%s%s", class_prefix, readable_name(method, false))
			plan := node.op_plans[method]
			req_count := len(plan.req_indices)
			node.op_state_classes[method] = allocate_op_state_classes(used_types, op_base, req_count)

			if len(plan.error_variants) >= 2 {
				union_base := plan.binding.base_name
				if union_base == "" {
					union_base = operation_base(plan.method, plan.full_path, plan.operation)
				}
				plan.error_union_name = allocate_name(used_types, fmt.aprintf("%sError", union_base))
				plan.error_type = plan.error_union_name

				used_getters := make(map[string]bool)
				for reserved in ([5]string{"hashCode", "runtimeType", "toString", "noSuchMethod", "value"}) {
					used_getters[reserved] = true
				}
				for &variant in plan.error_variants {
					getter_base := ""
					suffix_base := ""
					if ref, is_ref := variant.model.(ir.Reference); is_ref {
						ref_type := names.types[child_path("schema", ref.name)]
						getter_base = readable_name(ref_type, true)
						suffix_base = readable_name(ref_type, false)
					} else if variant.first_status == "default" {
						getter_base = "defaultError"
						suffix_base = "Default"
					} else {
						getter_base = fmt.aprintf("status%s", variant.first_status)
						suffix_base = fmt.aprintf("Status%s", variant.first_status)
					}
					variant.getter_name = allocate_name(&used_getters, getter_base)
					variant.class_name = allocate_name(used_types, fmt.aprintf("%s%s", plan.error_union_name, suffix_base))
				}
				node.op_plans[method] = plan
			}
		}
	}

	for key in node.child_keys {
		child := node.children[key]
		member_base := readable_name(child.segment, true)
		class_suffix := readable_name(child.segment, false)
		if child.is_param {
			member_base = readable_name(fmt.aprintf("by_%s", child.segment), true)
			class_suffix = fmt.aprintf("By%s", readable_name(child.segment, false))
		}
		child.member_name = allocate_name(&used_members, member_base)
		next_prefix := fmt.aprintf("%s%s", class_prefix, class_suffix)
		child.class_name = allocate_name(used_types, next_prefix)
		if child.bind_param {
			child.bound_class_name = allocate_name(used_types, fmt.aprintf("%sBound", child.class_name))
		}
		assign_dart_path_names(child, used_types, next_prefix, names)
	}
}

@(private)
emit_dart_captured_fields_and_ctor :: proc(builder: ^strings.Builder, class_name: string, params: []CapturedParam) {
	if len(params) == 0 {
		fmt.sbprintf(builder, "  const %s._();\n", class_name)
		return
	}
	for param in params {
		fmt.sbprintf(builder, "  final %s %s;\n", param.dart_type, param.field_name)
	}
	ctor_args := make([dynamic]string, len(params))
	for param, index in params {
		ctor_args[index] = fmt.aprintf("this.%s", param.field_name)
	}
	joined, _ := strings.join(ctor_args[:], ", ")
	fmt.sbprintf(builder, "  const %s._(%s);\n", class_name, joined)
}

@(private)
dart_ctor_invocation :: proc(class_name: string, params: []CapturedParam, extra_arg := "") -> string {
	if len(params) == 0 && extra_arg == "" {
		return fmt.aprintf("const %s._()", class_name)
	}
	args := make([dynamic]string)
	for param in params {
		append(&args, param.field_name)
	}
	if extra_arg != "" {
		append(&args, extra_arg)
	}
	joined, _ := strings.join(args[:], ", ")
	return fmt.aprintf("%s._(%s)", class_name, joined)
}

@(private)
emit_dart_path_member_getters :: proc(
	builder: ^strings.Builder,
	node: ^DartPathNode,
	document: ^ir.Document,
	available_params: []CapturedParam,
) {
	for key in node.child_keys {
		child := node.children[key]
		ctor_call := dart_ctor_invocation(child.class_name, available_params)
		fmt.sbprintf(builder, "  %s get %s => %s;\n", child.class_name, child.member_name, ctor_call)
	}

	if node.has_ops {
		for method in sorted_keys(node.operations) {
			entry_class := node.op_state_classes[method][0]
			doc := documentation_comment(operation_documentation(document, node.full_path, method, node.operations[method]), .dart, "  ")
			if doc != "" { fmt.sbprint(builder, doc) }
			ctor_call := dart_ctor_invocation(entry_class, available_params)
			fmt.sbprintf(builder, "  %s get %s => %s;\n", entry_class, method, ctor_call)
		}
	}
}

@(private)
emit_dart_path_nodes :: proc(
	builder: ^strings.Builder,
	node: ^DartPathNode,
	document: ^ir.Document,
	dart_schemas: map[string]ir.Model,
	names: ^GeneratorNames,
	operation_request_name: string,
) {
	if node.bind_param {
		fmt.sbprintf(builder, "final class %s {{\n", node.class_name)
		emit_dart_captured_fields_and_ctor(builder, node.class_name, node.captured_params[:])
		if node.has_ops {
			fmt.sbprintf(builder, "  String get path => %s;\n", dart_json_key(node.full_path))
		}
		bound_call := dart_ctor_invocation(node.bound_class_name, node.captured_params[:], node.own_param.dart_name)
		fmt.sbprintf(builder, "  %s call(%s %s) => %s;\n", node.bound_class_name, node.own_param.dart_type, node.own_param.dart_name, bound_call)
		fmt.sbprintln(builder, "}\n")

		fmt.sbprintf(builder, "final class %s {{\n", node.bound_class_name)
		emit_dart_captured_fields_and_ctor(builder, node.bound_class_name, node.bound_params[:])
		if node.has_ops {
			fmt.sbprintf(builder, "  String get path => %s;\n", dart_json_key(node.full_path))
		}
		emit_dart_path_member_getters(builder, node, document, node.bound_params[:])
		fmt.sbprintln(builder, "}\n")
	} else {
		fmt.sbprintf(builder, "final class %s {{\n", node.class_name)
		emit_dart_captured_fields_and_ctor(builder, node.class_name, node.bound_params[:])
		if node.has_ops {
			fmt.sbprintf(builder, "  String get path => %s;\n", dart_json_key(node.full_path))
		}
		emit_dart_path_member_getters(builder, node, document, node.bound_params[:])
		fmt.sbprintln(builder, "}\n")
	}

	if node.has_ops {
		for method in sorted_keys(node.operations) {
			emit_dart_operation_states(
				builder,
				document,
				node.op_plans[method],
				node.op_state_classes[method][:],
				dart_schemas,
				names,
				operation_request_name,
			)
		}
	}

	for key in node.child_keys {
		emit_dart_path_nodes(builder, node.children[key], document, dart_schemas, names, operation_request_name)
	}
}

@(private)
group_has_required_field :: proc(group: ir.ObjectModel) -> bool {
	for _, field in group.fields {
		if field.required { return true }
	}
	return false
}

@(private)
collect_distinct_media_models :: proc(content: map[string]ir.Model) -> [dynamic]ir.Model {
	models := make([dynamic]ir.Model)
	for media in sorted_keys(content) {
		model := content[media]
		if !contains_payload(models[:], model) {
			append(&models, model)
		}
	}
	return models
}

@(private)
resolve_named_object_schema :: proc(model: ir.Model, schemas: map[string]ir.Model) -> (string, ir.ObjectModel, bool) {
	current := model
	for _ in 0..=len(schemas) {
		ref, is_ref := current.(ir.Reference)
		if !is_ref { return "", {}, false }
		target, found := schemas[ref.name]
		if !found { return "", {}, false }
		if obj, is_obj := target.(ir.ObjectModel); is_obj {
			return ref.name, obj, true
		}
		current = target
	}
	return "", {}, false
}

@(private)
operation_path_params_all_bound :: proc(operation: ir.Operation, bound_params: []CapturedParam) -> bool {
	group, has_path_group := operation.parameters[.path]
	if !has_path_group { return true }

	for field_name in sorted_keys(group.fields) {
		found := false
		for param in bound_params {
			if param.raw_name == field_name {
				found = true
				break
			}
		}
		if !found { return false }
	}
	return true
}

@(private)
emit_dart_bound_path_entries :: proc(
	params: []CapturedParam,
	names: ^GeneratorNames,
	dart_schemas: map[string]ir.Model,
) -> string {
	entries := make([dynamic]string, len(params))
	for param, index in params {
		encoded := dart_json_encode(param.model, param.model_path, param.field_name, param.nullable, names, dart_schemas)
		entries[index] = fmt.aprintf("%s: %s", dart_json_key(param.raw_name), encoded)
	}
	joined, _ := strings.join(entries[:], ", ")
	return joined
}

@(private)
is_req_satisfied_in_state :: proc(k, s, req_idx: int) -> bool {
	if k == 0 { return false }
	if k <= 2 { return (s & (1 << uint(req_idx))) != 0 }
	return req_idx < s
}

@(private)
is_req_callable_in_state :: proc(k, s, req_idx: int) -> bool {
	if k <= 2 { return true }
	return req_idx <= s
}

@(private)
target_state_for_req :: proc(k, s, req_idx: int) -> int {
	if k <= 2 { return s | (1 << uint(req_idx)) }
	if req_idx == s { return s + 1 }
	return s
}

@(private)
req_pos_for_slot :: proc(plan: DartOpPlan, slot_idx: int) -> (int, bool) {
	for idx, pos in plan.req_indices {
		if idx == slot_idx { return pos, true }
	}
	return -1, false
}

@(private)
StateField :: struct {
	field_name:    string,
	ctor_param:    string,
	field_type:    string,
	required:      bool,
	default_value: string,
}

@(private)
collect_state_fields :: proc(plan: DartOpPlan, state_idx: int) -> [dynamic]StateField {
	fields := make([dynamic]StateField)
	k := len(plan.req_indices)

	for slot_idx in plan.opt_indices {
		slot := plan.slots[slot_idx]
		append(&fields, StateField{
			field_name = slot.field_name,
			ctor_param = slot.ctor_param,
			field_type = slot.field_type,
			required   = false,
		})
	}

	for req_pos, slot_idx in plan.req_indices {
		_ = req_pos
	}
	for slot_idx, req_pos in plan.req_indices {
		if !is_req_satisfied_in_state(k, state_idx, req_pos) { continue }
		slot := plan.slots[slot_idx]
		append(&fields, StateField{
			field_name = slot.field_name,
			ctor_param = slot.ctor_param,
			field_type = slot.field_type,
			required   = true,
		})
	}

	if plan.has_content_type_selector {
		append(&fields, StateField{
			field_name    = "_contentType",
			ctor_param    = "contentType",
			field_type    = "String",
			required      = false,
			default_value = dart_json_key(plan.default_content_type),
		})
	}

	return fields
}

@(private)
emit_dart_state_fields_and_ctor :: proc(
	builder: ^strings.Builder,
	class_name: string,
	bound_params: []CapturedParam,
	state_fields: []StateField,
) {
	for param in bound_params {
		fmt.sbprintf(builder, "  final %s %s;\n", param.dart_type, param.field_name)
	}
	for field in state_fields {
		fmt.sbprintf(builder, "  final %s %s;\n", field.field_type, field.field_name)
	}

	if len(bound_params) == 0 && len(state_fields) == 0 {
		fmt.sbprintf(builder, "  const %s._();\n", class_name)
		return
	}

	pos_parts := make([dynamic]string)
	for param in bound_params {
		append(&pos_parts, fmt.aprintf("this.%s", param.field_name))
	}

	if len(state_fields) == 0 {
		joined_pos, _ := strings.join(pos_parts[:], ", ")
		fmt.sbprintf(builder, "  const %s._(%s);\n", class_name, joined_pos)
		return
	}

	named_parts := make([dynamic]string)
	init_parts := make([dynamic]string)
	for field in state_fields {
		if field.required {
			append(&named_parts, fmt.aprintf("required %s %s", field.field_type, field.ctor_param))
		} else if field.default_value != "" {
			append(&named_parts, fmt.aprintf("%s %s = %s", field.field_type, field.ctor_param, field.default_value))
		} else {
			append(&named_parts, fmt.aprintf("%s %s", field.field_type, field.ctor_param))
		}
		append(&init_parts, fmt.aprintf("%s = %s", field.field_name, field.ctor_param))
	}

	joined_named, _ := strings.join(named_parts[:], ", ")
	joined_init, _ := strings.join(init_parts[:], ", ")
	if len(pos_parts) > 0 {
		joined_pos, _ := strings.join(pos_parts[:], ", ")
		fmt.sbprintf(builder, "  const %s._(%s, {{%s}}) : %s;\n", class_name, joined_pos, joined_named, joined_init)
	} else {
		fmt.sbprintf(builder, "  const %s._({{%s}}) : %s;\n", class_name, joined_named, joined_init)
	}
}

@(private)
format_state_ctor_call :: proc(
	target_class: string,
	bound_params: []CapturedParam,
	target_fields: []StateField,
	override_field: string,
	override_expr: string,
) -> string {
	args := make([dynamic]string)
	for param in bound_params {
		append(&args, param.field_name)
	}
	for field in target_fields {
		val := field.field_name
		if field.field_name == override_field {
			val = override_expr
		}
		append(&args, fmt.aprintf("%s: %s", field.ctor_param, val))
	}
	joined, _ := strings.join(args[:], ", ")
	return fmt.aprintf("%s._(%s)", target_class, joined)
}

@(private)
emit_dart_slot_builder_methods :: proc(
	builder: ^strings.Builder,
	slot: DartOpSlot,
	target_class: string,
	bound_params: []CapturedParam,
	target_fields: []StateField,
	names: ^GeneratorNames,
	dart_schemas: map[string]ir.Model,
) {
	if slot.is_named_obj {
		schema_path := child_path("schema", slot.schema_key)
		dto_class := names.types[schema_path]
		if slot.obj_model.nullable {
			dto_class = names.types[child_path(schema_path, "nullable")]
		}

		fields := sorted_keys(slot.obj_model.fields)
		_, has_additional := slot.obj_model.additional_properties.?
		if len(fields) == 0 && !has_additional {
			dto_expr := fmt.aprintf("const %s()", dto_class)
			if slot.encode_to_json { dto_expr = fmt.aprintf("%s.toJson()", dto_expr) }
			ctor_call := format_state_ctor_call(target_class, bound_params, target_fields, slot.field_name, dto_expr)
			fmt.sbprintf(builder, "\n  %s %s() => %s;\n", target_class, slot.method_name, ctor_call)
		} else {
			fmt.sbprintf(builder, "\n  %s %s({{\n", target_class, slot.method_name)
			ctor_args := make([dynamic]string)
			for field in fields {
				entry := slot.obj_model.fields[field]
				field_path := child_path(child_path(schema_path, "fields"), field)
				field_name := names.fields[field_path]
				field_type := model_type(entry.model, field_path, names, dart_schemas)
				if !entry.required && !model_nullable(entry.model, dart_schemas) {
					field_type = dart_nullable_type(field_type, true)
				}
				if entry.required {
					fmt.sbprintf(builder, "    required %s %s,\n", field_type, field_name)
				} else {
					fmt.sbprintf(builder, "    %s %s,\n", field_type, field_name)
				}
				append(&ctor_args, fmt.aprintf("%s: %s", field_name, field_name))
			}
			if additional, ok := slot.obj_model.additional_properties.?; ok {
				additional_type := model_type(additional^, child_path(schema_path, "additionalProperties"), names, dart_schemas)
				additional_name := names.additional_fields[schema_path]
				fmt.sbprintf(builder, "    Map<String, %s> %s = const {{}},\n", additional_type, additional_name)
				append(&ctor_args, fmt.aprintf("%s: %s", additional_name, additional_name))
			}
			joined_dto_args, _ := strings.join(ctor_args[:], ", ")
			dto_expr := fmt.aprintf("%s(%s)", dto_class, joined_dto_args)
			if slot.encode_to_json { dto_expr = fmt.aprintf("%s.toJson()", dto_expr) }
			ctor_call := format_state_ctor_call(target_class, bound_params, target_fields, slot.field_name, dto_expr)
			fmt.sbprintf(builder, "  }}) => %s;\n", ctor_call)
		}

		with_expr := "value"
		if slot.encode_to_json {
			with_expr = "value.toJson()" if slot.required else "value?.toJson()"
		}
		with_call := format_state_ctor_call(target_class, bound_params, target_fields, slot.field_name, with_expr)
		fmt.sbprintf(builder, "\n  %s %s(%s value) => %s;\n", target_class, slot.with_name, slot.type_name, with_call)
		return
	}

	// Non-object body (primitive, array, map, etc.).
	ctor_call := format_state_ctor_call(target_class, bound_params, target_fields, slot.field_name, "value")
	fmt.sbprintf(builder, "\n  %s %s(%s value) => %s;\n", target_class, slot.method_name, slot.type_name, ctor_call)
}

@(private)
emit_dart_error_union :: proc(
	builder: ^strings.Builder,
	plan: DartOpPlan,
	dart_schemas: map[string]ir.Model,
) {
	if len(plan.error_variants) < 2 { return }

	fmt.sbprintf(builder, "sealed class %s {{\n", plan.error_union_name)
	fmt.sbprintf(builder, "  const %s();\n", plan.error_union_name)
	for variant in plan.error_variants {
		getter_type := dart_nullable_type(variant.dart_type, !model_nullable(variant.model, dart_schemas))
		fmt.sbprintf(builder, "  %s get %s => null;\n", getter_type, variant.getter_name)
	}
	fmt.sbprintln(builder, "}\n")

	for variant in plan.error_variants {
		fmt.sbprintf(builder, "final class %s extends %s {{\n", variant.class_name, plan.error_union_name)
		fmt.sbprintf(builder, "  final %s value;\n", variant.dart_type)
		fmt.sbprintf(builder, "  const %s(this.value);\n\n", variant.class_name)
		fmt.sbprintln(builder, "  @override")
		fmt.sbprintf(builder, "  %s get %s => value;\n\n", variant.dart_type, variant.getter_name)
		fmt.sbprintln(builder, "  @override")
		fmt.sbprintf(
			builder,
			"  bool operator ==(Object other) => identical(this, other) || other is %s && other.runtimeType == runtimeType && _deepEqual(value, other.value);\n\n",
			variant.class_name,
		)
		fmt.sbprintln(builder, "  @override")
		fmt.sbprintln(builder, "  int get hashCode => Object.hash(runtimeType, _deepHash(value));")
		fmt.sbprintln(builder, "}\n")
	}
}

@(private)
format_dart_error_decoder :: proc(plan: DartOpPlan, expr: string, variant_idx: int) -> string {
	if variant_idx < 0 { return "null" }
	if len(plan.error_variants) >= 2 {
		variant := plan.error_variants[variant_idx]
		return fmt.aprintf("(Object? data) => %s(%s)", variant.class_name, expr)
	}
	return fmt.aprintf("(Object? data) => %s", expr)
}

@(private)
emit_dart_operation_states :: proc(
	builder: ^strings.Builder,
	document: ^ir.Document,
	plan: DartOpPlan,
	state_classes: []string,
	dart_schemas: map[string]ir.Model,
	names: ^GeneratorNames,
	operation_request_name: string,
) {
	emit_dart_error_union(builder, plan, dart_schemas)

	k := len(plan.req_indices)
	state_count := len(state_classes)
	doc := documentation_comment(operation_documentation(document, plan.full_path, plan.method, plan.operation), .dart)

	for state_idx in 0..<state_count {
		class_name := state_classes[state_idx]
		state_fields := collect_state_fields(plan, state_idx)

		if state_idx == 0 && doc != "" {
			fmt.sbprint(builder, doc)
		}
		fmt.sbprintf(builder, "final class %s {{\n", class_name)
		emit_dart_state_fields_and_ctor(builder, class_name, plan.bound_params, state_fields[:])
		fmt.sbprintf(builder, "  String get method => '%s';\n", strings.to_upper(plan.method))
		fmt.sbprintf(builder, "  String get path => %s;\n", dart_json_key(plan.full_path))

		for slot, slot_idx in plan.slots {
			target_idx := state_idx
			if slot.required {
				req_pos, found := req_pos_for_slot(plan, slot_idx)
				if !found || !is_req_callable_in_state(k, state_idx, req_pos) {
					continue
				}
				target_idx = target_state_for_req(k, state_idx, req_pos)
			}
			target_class := state_classes[target_idx]
			target_fields := collect_state_fields(plan, target_idx)
			emit_dart_slot_builder_methods(builder, slot, target_class, plan.bound_params, target_fields[:], names, dart_schemas)
		}

		if plan.has_content_type_selector {
			ct_call := format_state_ctor_call(class_name, plan.bound_params, state_fields[:], "_contentType", "value")
			fmt.sbprintf(builder, "\n  %s contentType(String value) => %s;\n", class_name, ct_call)
		}

		if state_idx == state_count - 1 {
			path_expr := "null"
			if plan.has_path_binding {
				if plan.all_path_bound {
					if len(plan.bound_params) > 0 {
						path_expr = fmt.aprintf("<String, dynamic>{{%s}}", emit_dart_bound_path_entries(plan.bound_params, names, dart_schemas))
					}
				} else if len(plan.bound_params) > 0 {
					path_slot := plan.slots[plan.path_slot_idx]
					spread := "..._pathParams" if path_slot.required else "...?_pathParams"
					path_expr = fmt.aprintf("<String, dynamic>{{%s, %s}}", emit_dart_bound_path_entries(plan.bound_params, names, dart_schemas), spread)
				} else {
					path_expr = "_pathParams"
				}
			} else if len(plan.bound_params) > 0 {
				path_expr = fmt.aprintf("<String, dynamic>{{%s}}", emit_dart_bound_path_entries(plan.bound_params, names, dart_schemas))
			}

			query_expr := "_query" if plan.query_slot_idx >= 0 else "null"
			headers_expr := "_headers" if plan.header_slot_idx >= 0 else "null"
			cookie_expr := "_cookie" if plan.cookie_slot_idx >= 0 else "null"
			body_expr := "_body" if plan.body_slot_idx >= 0 else "null"
			content_type_expr := "null"
			if plan.has_content_type_selector {
				content_type_expr = "_contentType"
			} else if plan.has_fixed_content_type {
				content_type_expr = dart_json_key(plan.fixed_content_type)
			}

			fmt.sbprintln(builder)
			fmt.sbprintf(builder, "  %s<%s, %s> get request => (\n", operation_request_name, plan.res_type, plan.error_type)
			fmt.sbprintf(builder, "    method: '%s',\n", strings.to_upper(plan.method))
			fmt.sbprintf(builder, "    path: %s,\n", dart_json_key(plan.full_path))
			fmt.sbprintf(builder, "    pathParams: %s,\n", path_expr)
			fmt.sbprintf(builder, "    query: %s,\n", query_expr)
			fmt.sbprintf(builder, "    headers: %s,\n", headers_expr)
			fmt.sbprintf(builder, "    cookie: %s,\n", cookie_expr)
			fmt.sbprintf(builder, "    body: %s,\n", body_expr)
			fmt.sbprintf(builder, "    contentType: %s,\n", content_type_expr)
			fmt.sbprintf(builder, "    decodeResponse: %s,\n", plan.decode_expr)

			if len(plan.error_entries) == 0 {
				fmt.sbprintf(builder, "    errorDecoders: const <int, %s Function(Object? data)?>{{}},\n", plan.error_type)
			} else {
				fmt.sbprintf(builder, "    errorDecoders: <int, %s Function(Object? data)?>{{\n", plan.error_type)
				for entry in plan.error_entries {
					fmt.sbprintf(builder, "      %d: %s,\n", entry.code, format_dart_error_decoder(plan, entry.expr, entry.variant_idx))
				}
				fmt.sbprintln(builder, "    },")
			}
			fmt.sbprintf(
				builder,
				"    defaultErrorDecoder: %s,\n",
				format_dart_error_decoder(plan, plan.default_error_expr, plan.default_error_variant_idx),
			)
			fmt.sbprintln(builder, "  );")
		}

		fmt.sbprintln(builder, "}\n")
	}
}
