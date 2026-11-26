import 'spec.dart';

void main() {
  UserRequest(name: 'Alice', password: 'secret', id: '1'); // expected-error: UNDEFINED_NAMED_PARAMETER
  UserResponse(id: '1', name: 'Alice', password: 'secret'); // expected-error: UNDEFINED_NAMED_PARAMETER
  UserRequest(name: 'Alice'); // expected-error: MISSING_REQUIRED_ARGUMENT
  UserResponse(name: 'Alice'); // expected-error: MISSING_REQUIRED_ARGUMENT
}
