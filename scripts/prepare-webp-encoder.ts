#!/usr/bin/env node
import { prepareWebpEncoder } from '../tools/teavm/webp.ts';

const source = await prepareWebpEncoder();
console.log(`Prepared libwebp ${source.version} encoder (${source.size} B)`);
