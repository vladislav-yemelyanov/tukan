import 'spec.dart';

void main() {
  User(role: Role.admin); // expected-error: MISSING_REQUIRED_ARGUMENT
}
