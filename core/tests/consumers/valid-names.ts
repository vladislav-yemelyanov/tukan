import type { Schemas } from './spec';

export const value: Schemas['A/B~C'] = {
  class: 'reserved',
  'quote"name': 'quoted',
  'line\nbreak': 'newline',
  'dollar$value': 'dollar',
  'ключ': 'unicode',
};
export const text: Schemas['Text'] = '$value';

// @ts-expect-error escaped identifiers must preserve the required property.
export const missing: Schemas['A/B~C'] = {};

// @ts-expect-error enum values retain their literal contents.
export const invalidText: Schemas['Text'] = 'other';
