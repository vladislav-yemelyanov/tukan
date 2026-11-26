package openapi

import "core:encoding/json"

OpenApiSpec :: struct {
	openapi:    string,
	info:       OpenApiInfo,
	components: Maybe(Components),
	paths:      Maybe(map[string]PathItem),

	// Raw JSON preserves explicit null for semantic validation.
	security:   json.Value,
}

OpenApiInfo :: struct {
	title:       string,
	description: string,
	version:     string,
}

Components :: struct {
	schemas:          Maybe(map[string]Schema),
	parameters:       Maybe(map[string]Parameter),
	request_bodies:   Maybe(map[string]RequestBody) `json:"requestBodies"`,
	responses:        Maybe(map[string]Response),
	security_schemes: json.Value `json:"securitySchemes"`,
}

// Keep schema keywords until conversion so unsupported features can be diagnosed.
Schema :: distinct json.Object

PathItem :: struct {
	ref:        Maybe(json.Value) `json:"$ref"`,

	parameters: Maybe([]Parameter),

	get:        Maybe(Operation),
	put:        Maybe(Operation),
	post:       Maybe(Operation),
	delete:     Maybe(Operation),
	options:    Maybe(Operation),
	head:       Maybe(Operation),
	patch:      Maybe(Operation),
	trace:      Maybe(Operation),
}

Operation :: struct {
	operation_id: Maybe(string) `json:"operationId"`,
	summary: Maybe(string),
	description: Maybe(string),
	security:     json.Value,
	parameters:   Maybe([]Parameter),
	request_body: Maybe(RequestBody) `json:"requestBody"`,
	responses:    Maybe(map[string]Response),
}

Parameter :: struct {
	ref:      Maybe(string) `json:"$ref"`,
	name:     string,
	location: string `json:"in"`,
	required: Maybe(bool),
	schema:   Maybe(Schema),
	content:  Maybe(map[string]MediaType),
}

RequestBody :: struct {
	ref:      Maybe(string) `json:"$ref"`,
	required: Maybe(bool),
	content:  Maybe(map[string]MediaType),
}

Response :: struct {
	ref:     Maybe(string) `json:"$ref"`,
	content: Maybe(map[string]MediaType),
}

MediaType :: struct {
	encoding: json.Value,

	schema: Maybe(Schema),
}
