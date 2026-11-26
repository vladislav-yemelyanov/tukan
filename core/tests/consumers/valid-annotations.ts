import type { Schemas } from './spec';
const input: Schemas['Input'] = {};
if ('currency-id' in input) throw new Error('Defaults must not be applied');
