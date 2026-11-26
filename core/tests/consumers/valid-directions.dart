import 'spec.dart';

void main() {
  const inline = CreateInlineRequest(label: 'inline');
  assert(inline.label == 'inline');
  const item = CreateInlineResponseItem(label: 'response');
  assert(item.label == 'response');

  const request = UserRequest(name: 'Alice', password: 'secret');
  const UserResponse response = UserResponse(
    id: 'user-1',
    name: 'Alice',
    children: [UserResponse(id: 'user-2', name: 'Bob')],
  );

  assert(request.password == 'secret');
  assert(response.children!.single.id == 'user-2');
  assert(response.copyWith(name: 'Alicia').name == 'Alicia');

  final roundTrip = UserRequest.fromJson(request.toJson());
  assert(roundTrip == request && roundTrip.hashCode == request.hashCode);
  final responseRoundTrip = UserResponse.fromJson(response.toJson());
  assert(responseRoundTrip == response && responseRoundTrip.hashCode == response.hashCode);
}
