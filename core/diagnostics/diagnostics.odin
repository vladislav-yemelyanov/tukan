package diagnostics

import "core:fmt"
import "core:slice"
import "core:strings"

Severity :: enum {
	error,
	warning,
}

Issue :: struct {
	severity: Severity,
	code:     string,
	language: string,
	message:  string,
	subject:  string,
	path:     string,
}

Manager :: struct {
	issues: [dynamic]Issue,
}

add :: proc(manager: ^Manager, message: string, subject := "", path := "", severity := Severity.error, code := "", language := "") {
	if manager == nil { return }

	for issue in manager.issues {
		if issue.severity == severity && issue.code == code && issue.language == language && issue.message == message && issue.subject == subject && issue.path == path { return }
	}

	append(&manager.issues, Issue{severity = severity, code = code, language = language, message = message, subject = subject, path = path})
}

has_errors :: proc(manager: ^Manager) -> bool {
	if manager == nil { return false }

	for issue in manager.issues {
		if issue.severity == .error { return true }
	}

	return false
}

format :: proc(manager: ^Manager) -> string {
	builder := strings.builder_make()
	defer strings.builder_destroy(&builder)

	issues := make([]Issue, len(manager.issues))
	defer delete(issues)
	copy(issues, manager.issues[:])
	slice.sort_by(issues, proc(a, b: Issue) -> bool {
		if a.path != b.path { return a.path < b.path }
		if a.code != b.code { return a.code < b.code }
		if a.language != b.language { return a.language < b.language }
		if a.message != b.message { return a.message < b.message }
		if a.subject != b.subject { return a.subject < b.subject }
		return a.severity < b.severity
	})
	for issue, index in issues {
		if index > 0 { fmt.sbprintln(&builder) }
		fmt.sbprintf(&builder, "%d. %s: %s\n", index + 1, issue.severity, issue.message)
		if issue.code != "" { fmt.sbprintf(&builder, "   code: %s\n", issue.code) }
		if issue.language != "" { fmt.sbprintf(&builder, "   language: %s\n", issue.language) }
		if len(issue.path) > 0 { fmt.sbprintf(&builder, "   at %s\n", issue.path) }
		if len(issue.subject) > 0 { fmt.sbprintf(&builder, "   %s\n", issue.subject) }
	}

	return strings.clone(strings.to_string(builder))
}

// Escape a JSON Pointer token so names containing slashes or tildes stay unambiguous.
child_path :: proc(path, field: string) -> string {
	// Escape tildes first so the slash escape is not escaped a second time.
	escaped, _ := strings.replace_all(field, "~", "~0")
	escaped, _ = strings.replace_all(escaped, "/", "~1")

	return fmt.aprintf("%s/%s", path, escaped)
}
