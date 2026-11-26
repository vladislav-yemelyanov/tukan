import 'spec.dart';

void main() {
  final empty = Widget.fromJson({});
  assert(empty.obj == null);
  assert(!empty.toJson().containsKey('obj'));

  final input = <String, dynamic>{
    r'cost$usd': 'price',
    'Name': 'capital',
    'name': 'lower',
    'additionalProperties': 'field',
    'toJson': 'reserved',
    'byName': {'first': 1},
    'obj': {'Inner': 'nested', 'flag': false},
    'status': 'with dash',
    'extra': 'extension',
  };
  final widget = Widget.fromJson(input);
  assert(widget.costUsd == 'price');
  assert(widget.name2 == 'capital');
  assert(widget.name == 'lower');
  assert(widget.additionalProperties == 'field');
  assert(widget.additionalProperties2['extra'] == 'extension');
  assert(widget.obj!.inner == 'nested' && widget.obj!.flag == false);
  assert(widget.status == WidgetStatus.withDash2);

  final withNullFlag = Widget.fromJson({'obj': {'Inner': 'nested', 'flag': null}});
  assert(withNullFlag.obj!.flag == null);

  final json = widget.toJson();
  assert(json['Name'] == 'capital' && json['name'] == 'lower');
  assert(json[r'cost$usd'] == 'price');
  assert(json['toJson'] == 'reserved' && json['extra'] == 'extension');
  assert((json['obj'] as Map)['flag'] == false);
  assert(json['status'] == 'with dash');
  assert(Widget.fromJson(json) == widget && Widget.fromJson(json).hashCode == widget.hashCode);
  assert(widget.copyWith(name: null).name == null);

  assert(WidgetStatus.fromJson('active') == WidgetStatus.active);
  assert(WidgetStatus.toString2.value == 'toString');
  assert(Empty.fromJson({}).toJson().isEmpty);
  assert(const Empty() == Empty.fromJson({}) && const Empty().hashCode == Empty.fromJson({}).hashCode);

  try {
    Required.fromJson({});
    throw StateError('Missing required value was accepted');
  } on FormatException catch (_) {}
}
