import type { Schemas } from './spec';

const order: Schemas['Order'] = {
  status: 'open',
  expand: ['closed'],
  shipping: { 'postal-code': 'normalized', postalCode: 'original', i: 'i', 'ı': 'dotless' },
  'a-b': 'first',
  'a/b': 'second',
  aB: 'original',
};
const alias: Schemas['a/b'] = 'referenced';
const maybe: Schemas['Maybe'] = { MaybeValue2: 'present' };
void [order, alias, maybe];
