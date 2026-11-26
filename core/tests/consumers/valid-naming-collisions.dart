import 'spec.dart';

void main() {
  const order = Order(
    status: OrderStatus3.open,
    expand: [OrderExpandItem2.closed],
    aB: 'original',
    aB2: 'first',
    aB3: 'second',
    generated_Value: 'original helper name',
    generatedValue: 'normalized helper name',
  );
  const AB3 alias = 'referenced';
  const Maybe maybe = MaybeValue2(maybeValue2: 'present');

  assert(order.status == OrderStatus3.open);
  assert(order.expand!.single == OrderExpandItem2.closed);
  assert(order.aB == 'original' && order.aB2 == 'first' && order.aB3 == 'second');
  assert(order.generated_Value == 'original helper name');
  assert(order.generatedValue == 'normalized helper name');
  assert(alias == 'referenced' && maybe.maybeValue2 == 'present');
  assert(Value.open.value == 'open' && Value0.closed.value == 'closed');
}
