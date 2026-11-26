package main

import "base:runtime"
import "core:fmt"
import virtual "core:mem/virtual"
import "core:sync"
import "core:thread"
import "diagnostics"
import "openapi"
import "parser"

SpecJob :: struct {
	options: SpecOptions,
	pool: ^thread.Pool,
	pending: ^sync.Wait_Group,
	arena: virtual.Arena,
	arena_ready: bool,
	issues: diagnostics.Manager,
	result: parser.ParseResult,
	parsed: bool,
	skipped_optional: bool,
	outputs: []OutputJob,
}

OutputJob :: struct {
	spec: ^SpecJob,
	target: OutputTarget,
	arena: virtual.Arena,
	arena_ready: bool,
	issues: diagnostics.Manager,
	path: string,
}

process_spec :: proc(task: thread.Task) {
	job := cast(^SpecJob)task.data
	defer sync.wait_group_done(job.pending)
	if err := virtual.arena_init_growing(&job.arena); err != nil { return }
	job.arena_ready = true
	context.allocator = virtual.arena_allocator(&job.arena)

	load_severity: diagnostics.Severity = .warning if job.options.optional else .error
	source: []byte
	read_ok: bool
	input := job.options.input
	if is_http_url(input) {
		source, read_ok = read_spec_from_swagger(input, &job.issues, load_severity)
	} else {
		source, read_ok = read_spec_from_file(input, &job.issues, load_severity)
	}
	if !read_ok {
		if job.options.optional && !diagnostics.has_errors(&job.issues) {
			job.skipped_optional = true
		}
		return
	}
	defer delete(source)

	{
		spec, decoded := openapi.decode(source, &job.issues)
		if !decoded { return }
		job.result = parser.parse(&spec, &job.issues)
		job.parsed = true
	}

	// Generation reads the immutable IR only after the entire specification is valid.
	if !job.result.valid { return }
	for target, index in job.options.targets {
		output := &job.outputs[index]
		output.spec = job
		output.target = target
		sync.wait_group_add(job.pending, 1)
		thread.pool_add_task(job.pool, runtime.default_allocator(), process_output, output)
	}
}

process_output :: proc(task: thread.Task) {
	job := cast(^OutputJob)task.data
	defer sync.wait_group_done(job.spec.pending)
	if err := virtual.arena_init_growing(&job.arena); err != nil { return }
	job.arena_ready = true
	context.allocator = virtual.arena_allocator(&job.arena)

	job.path = write_output(&job.spec.result.document, &job.issues, job.target.language, job.target.output_dir, job.spec.options.name)
}

process_specs :: proc(config: ^Config) -> bool {
	pool: thread.Pool
	pending: sync.Wait_Group
	jobs := make([]SpecJob, len(config.specs))
	thread.pool_init(&pool, runtime.default_allocator(), config.concurrency)
	defer thread.pool_destroy(&pool)
	defer {
		for &job in jobs {
			for &output in job.outputs {
				if output.arena_ready { virtual.arena_destroy(&output.arena) }
			}
			if job.arena_ready { virtual.arena_destroy(&job.arena) }
		}
	}

	// Register all source tasks before starting workers so the count cannot reach zero early.
	sync.wait_group_add(&pending, len(jobs))
	for &job, index in jobs {
		job.options = config.specs[index]
		job.outputs = make([]OutputJob, len(job.options.targets))
		job.pool = &pool
		job.pending = &pending
		thread.pool_add_task(&pool, runtime.default_allocator(), process_spec, &job)
	}
	thread.pool_start(&pool)
	sync.wait_group_wait(&pending)
	thread.pool_join(&pool)

	valid := true
	generated_count := 0
	// Report complete groups in configuration order instead of interleaving worker output.
	for &job, index in jobs {
		if index > 0 { fmt.println() }
		fmt.printf("Specification: %s\n  Input: %s\n", job.options.name, job.options.input)
		if !job.arena_ready {
			fmt.eprintln("error: Failed to initialize memory arena:", job.options.input)
			valid = false
			continue
		}
		fmt.println("\nStatistics")
		if job.parsed {
			stats := job.result.stats
			fmt.printf("  📦 Schemas: %d parsed, %d failed\n", stats.schemas_parsed, stats.schemas_failed)
			fmt.printf("  🔗 Operations: %d parsed, %d failed\n", stats.operations_parsed, stats.operations_failed)
		} else if job.skipped_optional {
			fmt.println("  ⚠️  Skipped optional specification: input could not be read; existing outputs preserved.")
		} else {
			fmt.println("  ⚠️  Could not count schemas or operations: specification was not read.")
		}
		if len(job.issues.issues) > 0 {
			fmt.eprintf("\nDiagnostics\n  Specification: %s\n\n%s", job.options.input, diagnostics.format(&job.issues))
		}
		if diagnostics.has_errors(&job.issues) { valid = false }
		for &output in job.outputs {
			if output.spec == nil { continue }
			if !output.arena_ready {
				fmt.eprintln("error: Failed to initialize generator memory arena:", job.options.input, output_format(output.target.language).name)
				valid = false
				continue
			}
			if output.path != "" { generated_count += 1 }
			if len(output.issues.issues) > 0 {
				fmt.eprintf("\nDiagnostics (%s)\n  Specification: %s\n\n%s", output_format(output.target.language).name, job.options.input, diagnostics.format(&output.issues))
			}
			if diagnostics.has_errors(&output.issues) { valid = false }
		}
	}

	fmt.printf("\nGenerated files (%d)\n", generated_count)
	if generated_count == 0 { fmt.println("  None.") }
	for &job in jobs {
		for &output in job.outputs {
			if output.path != "" { fmt.printf("  %s\n", output.path) }
		}
	}
	return valid
}
