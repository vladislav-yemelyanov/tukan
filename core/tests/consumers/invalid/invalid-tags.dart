import 'spec.dart';

void main() {
  User(id: 1, role: Role.admin, tags: [1]); // expected-error: LIST_ELEMENT_TYPE_NOT_ASSIGNABLE
}
