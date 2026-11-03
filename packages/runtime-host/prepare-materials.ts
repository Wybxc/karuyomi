#!/usr/bin/env node
import path from 'node:path';
import { collectMaterials, prepareMaterials } from './materials.ts';

const args = process.argv.slice(2);
let materials;
if (args.length === 1 && args[0] === '--print') {
  materials = await collectMaterials({ includeWasmBytes: false });
} else if (args.length === 2 && args[0] === '--output') {
  materials = await prepareMaterials(path.resolve(args[1]!));
} else {
  console.error(
    'Usage: node packages/runtime-host/prepare-materials.ts --print | --output DIR',
  );
  process.exit(64);
}
console.log(JSON.stringify(materials.catalog, null, 2));
