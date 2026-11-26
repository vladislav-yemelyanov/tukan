package ir

import "core:encoding/json"

PrimitiveType :: enum {
	string,
	number,
	integer,
	boolean,
}

Primitive :: struct {
	source_path: string,
	annotations: json.Object,

	type:     PrimitiveType,
	format:   Maybe(string),
	nullable: bool,
}

Enumeration :: struct {
	source_path: string,
	annotations: json.Object,

	values:   []json.Value,
	nullable: bool,
}

Reference :: struct {
	source_path: string,
	annotations: json.Object,

	name:     string,
	nullable: bool,
}

ArrayModel :: struct {
	source_path: string,
	annotations: json.Object,

	items:    ^Model,
	nullable: bool,
}

Field :: struct {
	model:      Model,
	// Presence and nullability are independent: an optional field may still reject null.
	required:   bool,
	read_only:  bool,
	write_only: bool,
}

ObjectModel :: struct {
	source_path: string,
	annotations: json.Object,

	fields:                map[string]Field,
	nullable:              bool,

	// nil means no additional-property model; UnknownModel allows arbitrary values.
	additional_properties: Maybe(^Model),
	closed: bool,
}

UnknownModel :: struct {
	source_path: string,
	annotations: json.Object,

	nullable: bool,
}

Model :: union {
	Primitive,
	Enumeration,
	Reference,
	ArrayModel,
	ObjectModel,
	UnknownModel,
}

Document :: struct {
	schemas: map[string]Model,
	paths:   map[string]map[string]Operation,
	security: Maybe([]SecurityRequirement),
	security_schemes: Maybe(json.Object),
}

SecurityRequirement :: map[string][]string

ParameterLocation :: enum {
	path,
	query,
	header,
	cookie,
}

Content :: map[string]Model

RequestBody :: struct {
	source_path: string,
	encodings: map[string]json.Object,

	required: bool,
	content:  Content,
}

Operation :: struct {
	operation_id: Maybe(string),
	summary: Maybe(string),
	description: Maybe(string),
	security:     Maybe([]SecurityRequirement),
	parameters:   map[ParameterLocation]ObjectModel,
	request_body: Maybe(RequestBody),
	responses:    map[string]Content,
}
