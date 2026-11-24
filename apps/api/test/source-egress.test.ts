import { once } from 'node:events';
import { test, expect } from 'vitest';
import {
  SOURCE_DNS_ADDRESSES_HEADER,
  SOURCE_DNS_ERROR_HEADER,
  SOURCE_DNS_TARGET_HEADER,
} from '@karuyomi/contracts';
import {
  createSourceEgressServer,
  pinnedLookup,
} from '../source-egress/server.ts';

test('the HTTPS client can only resolve its original hostname to supplied candidates', () => {
  const resolve = pinnedLookup('source.example', [
    '8.8.8.8',
    '2001:4860:4860::8888',
  ]);
  resolve('source.example', { all: true }, (error, addresses) => {
    expect(error).toBeNull();
    expect(addresses).toEqual([
      { address: '8.8.8.8', family: 4 },
      { address: '2001:4860:4860::8888', family: 6 },
    ]);
  });
  resolve('source.example', { family: 6 }, (error, address, family) => {
    expect(error).toBeNull();
    expect(address).toBe('2001:4860:4860::8888');
    expect(family).toBe(6);
  });
  resolve('other.example', { all: true }, (error) => {
    expect(error).toBeInstanceOf(Error);
  });
});

test('the container interface rejects invalid connection candidates independently', async () => {
  const server = createSourceEgressServer().listen(0, '127.0.0.1');
  try {
    await once(server, 'listening');
    const address = server.address();
    if (!address || typeof address === 'string')
      throw new Error('Expected a TCP port');
    const response = await fetch(
      'http://127.0.0.1:' + address.port + '/request',
      {
        headers: {
          [SOURCE_DNS_TARGET_HEADER]: 'https://source.example',
          [SOURCE_DNS_ADDRESSES_HEADER]: '127.0.0.1',
        },
      },
    );
    expect(response.status).toBe(502);
    expect(response.headers.get(SOURCE_DNS_ERROR_HEADER)).toBe('1');
    await response.body?.cancel();
  } finally {
    await new Promise<void>((resolve) => server.close(() => resolve()));
  }
});
