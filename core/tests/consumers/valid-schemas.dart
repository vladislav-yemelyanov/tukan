import 'spec.dart';

void main() {
  const minimal = User(id: 1, role: Role.admin);
  const nullable = User(
    id: 2,
    role: Role.member,
    name: 'Alice',
    tags: ['first'],
  );
  final Users users = [minimal, nullable];
  const scores = Scores(additionalProperties: {'first': 1.5});

  assert(minimal.name == null);
  assert(nullable.name == 'Alice');
  assert(users.length == 2 && scores.additionalProperties['first'] == 1.5);
  assert(!Enabled.value1.value && Priority.value1.value == 2);

  final cleared = nullable.copyWith(id: 3, name: null);
  assert(cleared.id == 3 && cleared.role == Role.member && cleared.name == null);
  assert(cleared.tags != null && cleared.tags!.single == 'first');

  final json = nullable.toJson();
  assert(json['role'] == 'member' && json['name'] == 'Alice');
  final restored = User.fromJson({...json, 'unknownField': 'ignored'});
  assert(restored == nullable && restored.hashCode == nullable.hashCode);
  assert(restored.tags!.single == 'first');
}
