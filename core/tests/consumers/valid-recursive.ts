import type { Schemas } from './spec';

export const tree: Schemas['Node'] = {
  name: 'root',
  children: [{ name: 'child', metadata: { owner: 'team' } }],
};

// @ts-expect-error recursive children retain the required name.
export const invalidChild: Schemas['Node'] = { name: 'root', children: [{}] };

// @ts-expect-error nested dictionary values remain strings.
export const invalidMetadata: Schemas['Node'] = { name: 'root', metadata: { owner: 1 } };
