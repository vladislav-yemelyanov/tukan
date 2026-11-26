import type { Schemas } from './spec';

type Get = Schemas['Operations']['/documents/{id}']['get'];
type Put = Schemas['Operations']['/documents/{id}']['put'];

export const parameters: Get['parameters'] = { path: { id: 'document-1' } };
export const query: Get['parameters'] = {
  path: { id: 'document-1' },
  query: { includeContent: false },
};
export const sameNames: Get['parameters'] = {
  path: { id: 'document-1' },
  header: { id: 'request-1' },
  cookie: { id: false },
};

export const response: Get['responses']['200']['application/json'] = { id: 'document-1' };
export const upload: Put = {
  parameters: { path: { id: 'document-1' } },
  requestBody: { 'multipart/form-data': { file: new Blob() } },
  responses: { '204': {}, '404': { 'application/json': { message: 'missing' } } },
};

// @ts-expect-error a path parameter group containing required id cannot be omitted.
export const missingPath: Get['parameters'] = {};

// @ts-expect-error includeContent is a boolean when supplied.
export const invalidQuery: Get['parameters'] = { path: { id: 'a' }, query: { includeContent: 'yes' } };

// @ts-expect-error a required requestBody must remain required after projection to TypeScript.
export const missingBody: Put = { parameters: upload.parameters, responses: upload.responses };

// @ts-expect-error upload file content is binary.
export const invalidFile: Put['requestBody'] = { 'multipart/form-data': { file: 'text' } };

// @ts-expect-error response schema references Document and requires id.
export const invalidResponse: Get['responses']['200']['application/json'] = {};

// @ts-expect-error the header id is a string, independent of the cookie id.
export const invalidHeader: Get['parameters'] = { path: { id: 'a' }, header: { id: 1 } };

// @ts-expect-error the cookie id is a boolean, independent of the path id.
export const invalidCookie: Get['parameters'] = { path: { id: 'a' }, cookie: { id: 'yes' } };
