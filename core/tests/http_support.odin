package tests

import "core:fmt"
import "core:net"
import "core:os"
import "core:strings"
import "core:sync"
import "core:testing"
import "core:thread"
import "core:time"

@(private)
http_fixture_timeout :: 5 * time.Second

@(private)
max_http_request_header_bytes :: 4096

HttpFixture :: struct {
	listener: net.TCP_Socket,
	worker: ^thread.Thread,

	url: string,
	request_target: string,
	response: string,

	failure: string,
	network_error: net.Network_Error,
	requests_ready: ^sync.Wait_Group,
	response_delay: time.Duration,
}

write_previous_http_output :: proc(work: TestWorkspace, content: string) -> (directory: string, err: os.Error) {
	directory = fmt.aprintf("%s/tukan-output", work.dir)
	err = os.make_directory(directory)
	if err != nil { return }

	for name in ([2]string{"spec.ts", "spec.dart"}) {
		err = os.write_entire_file(fmt.aprintf("%s/%s", directory, name), content)
		if err != nil { return }
	}

	return
}

// Each fixture serves one request. The worker owns its sockets until it exits.
start_http_fixture :: proc(t: ^testing.T, fixture: ^HttpFixture, body: []byte, status := "200 OK", request_target := "/spec.json", requests_ready: ^sync.Wait_Group = nil, response_delay: time.Duration = 0) -> bool {
	listener, err := net.listen_tcp({net.IP4_Loopback, 0})
	if !testing.expectf(t, err == nil, "HTTP fixture should listen: %v", err) { return false }

	endpoint, endpoint_err := net.bound_endpoint(listener)
	if !testing.expectf(t, endpoint_err == nil, "HTTP fixture should expose its port: %v", endpoint_err) {
		net.close(listener)
		return false
	}

	// Socket receive timeouts do not bound accept on every supported platform.
	blocking_err := net.set_blocking(listener, false)
	if !testing.expectf(t, blocking_err == nil, "HTTP fixture should allow bounded accept: %v", blocking_err) {
		net.close(listener)
		return false
	}

	fixture.listener = listener
	fixture.url = fmt.aprintf("http://127.0.0.1:%d/spec.json", endpoint.port)
	fixture.request_target = request_target
	fixture.requests_ready = requests_ready
	fixture.response_delay = response_delay
	fixture.response = fmt.aprintf("HTTP/1.1 %s\r\nContent-Type: application/json\r\nContent-Length: %d\r\nConnection: close\r\n\r\n%s", status, len(body), string(body))

	fixture.worker = thread.create(serve_http_fixture)
	if !testing.expect(t, fixture.worker != nil, "HTTP fixture worker should be created") {
		net.close(listener)
		return false
	}

	fixture.worker.data = fixture
	thread.start(fixture.worker)

	return true
}

serve_http_fixture :: proc(worker: ^thread.Thread) {
	fixture := cast(^HttpFixture)worker.data
	defer net.close(fixture.listener)

	client: net.TCP_Socket
	started := time.now()
	for {
		accepted, _, accept_err := net.accept_tcp(fixture.listener)
		if accept_err == nil {
			client = accepted
			break
		}
		if accept_err != .Would_Block || time.since(started) >= http_fixture_timeout {
			fixture.failure = "accept"
			fixture.network_error = accept_err
			return
		}
		time.sleep(time.Millisecond)
	}

	defer net.close(client)
	if err := net.set_blocking(client, true); err != nil {
		fixture.failure = "blocking connection"
		return
	}

	for option in ([2]net.Socket_Option{.Receive_Timeout, .Send_Timeout}) {
		if err := net.set_option(client, option, http_fixture_timeout); err != nil {
			fixture.failure = "socket timeout"
			fixture.network_error = err
			return
		}
	}

	request: [max_http_request_header_bytes]byte
	used := 0

	// TCP reads may split the headers; wait for their terminator before responding.
	for !strings.contains(string(request[:used]), "\r\n\r\n") {
		if used == len(request) {
			fixture.failure = "request headers exceed fixture limit"
			return
		}

		count, err := net.recv_tcp(client, request[used:])
		if err != nil || count == 0 {
			fixture.failure = "incomplete request"
			fixture.network_error = err
			return
		}

		used += count
	}

	if !strings.has_prefix(string(request[:used]), fmt.aprintf("GET %s HTTP/", fixture.request_target)) {
		fixture.failure = "unexpected request method or path"
		return
	}

	// A batch fixture can require all requests to arrive before any response is sent.
	if fixture.requests_ready != nil {
		sync.wait_group_done(fixture.requests_ready)
		if !sync.wait_group_wait_with_timeout(fixture.requests_ready, http_fixture_timeout) {
			fixture.failure = "requests did not overlap"
			return
		}
	}

	if fixture.response_delay > 0 { time.sleep(fixture.response_delay) }
	if _, err := net.send_tcp(client, transmute([]byte)fixture.response); err != nil {
		fixture.failure = "send response"
		fixture.network_error = err
	}
}
