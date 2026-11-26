import type { Schemas } from './spec';

type Operation = Schemas['Operations']['/users']['post'];
const request: Operation['requestBody'] = {
  'application/json': { name: 'Alice', password: 'secret', children: [{ name: 'Bob', password: 'child' }] },
};
const response: Operation['responses']['200'] = {
  'application/json': { id: 'user-1', name: 'Alice', children: [{ id: 'user-2', name: 'Bob' }] },
};
const invalidRequest: Schemas['UserRequest'] = {
  name: 'Alice', password: 'secret',
  // @ts-expect-error readOnly fields are excluded from requests
  id: 'user-1',
};
const invalidResponse: Schemas['UserResponse'] = {
  id: 'user-1', name: 'Alice',
  // @ts-expect-error writeOnly fields are excluded from responses
  password: 'secret',
};
// @ts-expect-error writeOnly required fields are still required in requests
const missingPassword: Schemas['UserRequest'] = { name: 'Alice' };
// @ts-expect-error readOnly required fields are still required in responses
const missingId: Schemas['UserResponse'] = { name: 'Alice' };
void [request, response, invalidRequest, invalidResponse, missingPassword, missingId];
