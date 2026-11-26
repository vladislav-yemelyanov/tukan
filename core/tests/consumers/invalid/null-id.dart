import 'spec.dart';

void main() {
  User(id: null, role: Role.admin); // expected-error: ARGUMENT_TYPE_NOT_ASSIGNABLE
}
