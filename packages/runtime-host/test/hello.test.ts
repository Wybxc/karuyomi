import { expect, test } from 'vitest';
import { runtimeHelloSchema } from '@karuyomi/contracts';
import { createHello } from '../src/hello.js';

test('bootstrap handshake is versioned and does not claim a ready Source', () => {
  const hello = runtimeHelloSchema.parse(createHello('test-generation'));
  expect(hello.sourceReady).toBe(false);
  expect(hello.capabilities).toEqual(['control-handshake']);
  expect(
    runtimeHelloSchema.safeParse({ ...hello, protocolVersion: 999 }).success,
  ).toBe(false);
});
