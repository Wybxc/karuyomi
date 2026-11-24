import { createSourceEgressServer } from './server.ts';

createSourceEgressServer().listen(8080, '0.0.0.0');
