package openapi

import "core:fmt"
import "core:net"
import "core:strings"

component_name :: proc(ref, section: string) -> Maybe(string) {
	if !strings.has_prefix(ref, "#/") { return nil }

	// URI decoding must happen before JSON Pointer escapes are interpreted.
	pointer, ok := net.percent_decode(ref[1:])
	prefix := fmt.aprintf("/components/%s/", section)
	if !ok || !strings.has_prefix(pointer, prefix) { return nil }

	encoded := pointer[len(prefix):]
	if len(encoded) == 0 || strings.contains(encoded, "/") { return nil }

	builder := strings.builder_make()
	defer strings.builder_destroy(&builder)

	index := 0
	for index < len(encoded) {
		if encoded[index] != '~' {
			strings.write_byte(&builder, encoded[index])
			index += 1
			continue
		}

		if index + 1 >= len(encoded) { return nil }

		switch encoded[index + 1] {
		case '0': strings.write_byte(&builder, '~')
		case '1': strings.write_byte(&builder, '/')
		case: return nil
		}
		index += 2
	}

	return strings.clone(strings.to_string(builder))
}
