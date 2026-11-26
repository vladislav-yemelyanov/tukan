import type { Schemas } from './spec';
const patch: Schemas['Patch'] = {id:'a',note:null,name:null,enabled:false,amount:0,state:'in-progress'};
const node: Schemas['Node'] = {children:[{value:'nested'}]};
// @ts-expect-error note must be provided even though it allows null
const missing: Schemas['Patch'] = {id:'a'};
// @ts-expect-error enum remains a closed union of wire values
const invalidState: Schemas['State'] = 'unknown';
// @ts-expect-error optional nonnullable fields reject null
const invalidEnabled: Schemas['Patch'] = {id:'a',note:null,enabled:null};
void [patch,node,missing,invalidState,invalidEnabled];
