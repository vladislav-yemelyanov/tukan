import 'dart:convert';
import 'spec.dart';

void reject(void Function() action, String scenario) {
  try {
    action();
  } on FormatException {
    return;
  }
  throw StateError('Expected rejection: $scenario');
}

void main() {
  final input = {'id': 'a', 'note': null, 'name': 'initial', 'enabled': false, 'amount': 0, 'labels': ['x'], 'state': 'in-progress'};
  final patch = Patch.fromJson(input);
  assert(patch.name == 'initial');
  assert(patch.enabled == false);
  assert(patch.state == State.inProgress);

  final output = patch.toJson();
  assert(output.length == input.length && output['amount'] == 0 && output['name'] == 'initial');
  assert(Patch.fromJson(output) == patch && Patch.fromJson(output).hashCode == patch.hashCode);

  final cleared = patch.copyWith(name: null, enabled: true);
  assert(cleared.name == null && cleared.enabled == true && cleared.id == 'a');

  final minimal = Patch.fromJson({'id': 'a', 'note': null});
  assert(minimal.name == null && !minimal.toJson().containsKey('name'));

  // Unknown fields and constraint bounds do not reject JSON payloads at runtime.
  final permissive = Patch.fromJson({'id': '1', 'note': null, 'amount': -1, 'labels': [''], 'extra': true});
  assert(permissive.id == '1' && permissive.amount == -1 && permissive.labels!.single == '');

  final tree = Node.fromJson({'children': [{'value': 'nested', 'json': 'field', 'toJson': 'method'}]});
  final treeOut = tree.toJson();
  assert((treeOut['children'] as List).single['value'] == 'nested');
  assert((treeOut['children'] as List).single['json'] == 'field');
  assert((treeOut['children'] as List).single['toJson'] == 'method');
  assert(Node.fromJson(treeOut) == tree && Node.fromJson(treeOut).hashCode == tree.hashCode);

  final error = Error.fromJson({'message': null, 'extension': {'values': [false, 0, null]}});
  assert(jsonEncode(error.toJson()).contains('"extension":{"values":[false,0,null]}'));
  assert(Error.fromJson(error.toJson()) == error && Error.fromJson(error.toJson()).hashCode == error.hashCode);

  reject(() => Patch.fromJson({'id': 'a'}), 'required nullable field');
  reject(() => State.fromJson('unknown'), 'enum');
}
