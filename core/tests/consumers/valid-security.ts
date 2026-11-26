import type { Schemas } from './spec';
const component: Schemas['TukanMetadata'] = 'component';
if (component !== 'component') throw new Error('Original schema names must be preserved');
