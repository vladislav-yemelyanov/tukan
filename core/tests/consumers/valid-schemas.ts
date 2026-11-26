import type { Schemas } from './spec';

export const minimal: Schemas['User'] = { id: 1, role: 'admin' };
export const nullable: Schemas['User'] = { id: 2, role: 'member', name: null };
export const users: Schemas['Users'] = [minimal, nullable];

export const scores: Schemas['Scores'] = { first: 1.5 };
export const enabled: Schemas['Enabled'] = false;
export const priority: Schemas['Priority'] = 2;

// @ts-expect-error id is required.
export const missingId: Schemas['User'] = { role: 'admin' };

// @ts-expect-error id is not nullable.
export const nullId: Schemas['User'] = { id: null, role: 'admin' };

// @ts-expect-error roles are restricted to the declared enum values.
export const invalidRole: Schemas['User'] = { id: 1, role: 'owner' };

// @ts-expect-error array entries must reference User.
export const invalidUsers: Schemas['Users'] = [1];

// @ts-expect-error dictionary values must be numbers.
export const invalidScores: Schemas['Scores'] = { first: 'one' };

// @ts-expect-error optional tags still require an array of strings.
export const invalidTags: Schemas['User'] = { id: 1, role: 'admin', tags: [1] };

// @ts-expect-error optional does not make a supplied non-nullable field nullable.
export const nullTags: Schemas['User'] = { id: 1, role: 'admin', tags: null };

// @ts-expect-error numeric enums retain their permitted values.
export const invalidPriority: Schemas['Priority'] = 4;
