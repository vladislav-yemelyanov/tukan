import 'spec.dart';

void main() {
  // The source schema and required property are both named "class".
  const value = Class(
    classValue: 'reserved',
  );
  final ABC reference = value;

  assert(reference.classValue == 'reserved');

  assert(Text.quoteValue.value == 'quote"value');
  assert(Text.lineBreak.value == 'line\nbreak');
  assert(Text.value2.value == r'$value');
  assert(Text.field.value == 'ключ');
}
