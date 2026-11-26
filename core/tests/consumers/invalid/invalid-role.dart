import 'spec.dart';

void main() {
  User(id: 1, role: 'admin'); // expected-error: ARGUMENT_TYPE_NOT_ASSIGNABLE
}
