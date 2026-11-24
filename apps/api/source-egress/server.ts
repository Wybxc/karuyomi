import { lookup } from 'node:dns/promises';
import {
  createServer,
  type IncomingMessage,
  type ServerResponse,
} from 'node:http';
import { isIP, type LookupFunction } from 'node:net';
import { Readable } from 'node:stream';
import { pipeline } from 'node:stream/promises';
import { Agent, fetch, Headers } from 'undici';
import {
  customDnsUrlSchema,
  dnsHostnameSchema,
  HTTP_FRAME_LIMIT,
  publicDnsAddressSchema,
  publicDnsAddressesSchema,
  SOURCE_DNS_ADDRESSES_HEADER,
  SOURCE_DNS_ADDRESS_LIMIT,
  SOURCE_DNS_DECODED_HEADER,
  SOURCE_DNS_ERROR_HEADER,
  SOURCE_DNS_TARGET_HEADER,
} from '@karuyomi/contracts';

const transportHeaders =
  /^(?:host|connection|transfer-encoding|upgrade|keep-alive|proxy-.*|te|trailer|x-karuyomi-dns-.*)$/i;

export function pinnedLookup(
  host: string,
  addresses: string[],
): LookupFunction {
  const destinations = addresses.map((address) => ({
    address,
    family: isIP(address),
  }));
  return (hostname, options, callback) => {
    const candidates = destinations.filter(({ family }) => {
      if (options.family === 'IPv4') return family === 4;
      if (options.family === 'IPv6') return family === 6;
      return !options.family || options.family === family;
    });
    if (hostname !== host || candidates.length === 0) {
      callback(new Error('No eligible DNS candidate'), '');
      return;
    }
    const first = candidates[0]!;
    if (options.all) callback(null, candidates);
    else callback(null, first.address, first.family);
  };
}

async function relay(
  request: IncomingMessage,
  response: ServerResponse,
): Promise<void> {
  const target = customDnsUrlSchema.parse(
    request.headers[SOURCE_DNS_TARGET_HEADER],
  );
  const addresses = publicDnsAddressesSchema.parse(
    request.headersDistinct[SOURCE_DNS_ADDRESSES_HEADER]?.join(',').split(','),
  );
  const url = new URL(target);
  const method = request.method;
  if (!method) throw new Error('HTTPS method is required');
  const headers = new Headers();
  for (const [name, values] of Object.entries(request.headersDistinct))
    if (values && name !== 'content-length' && !transportHeaders.test(name))
      for (const value of values) headers.append(name, value);
  const withBody =
    method !== 'GET' &&
    method !== 'HEAD' &&
    Boolean(
      request.headers['transfer-encoding'] ||
      Number(request.headers['content-length']),
    );
  const controller = new AbortController();
  response.once('close', () => controller.abort());
  const signal = AbortSignal.any([
    controller.signal,
    AbortSignal.timeout(300_000),
  ]);
  const dispatcher = new Agent({
    allowH2: true,
    connect: {
      lookup: pinnedLookup(url.hostname, addresses),
      rejectUnauthorized: true,
    },
  });
  try {
    const upstream = await fetch(url, {
      method,
      headers,
      redirect: 'manual',
      signal,
      dispatcher,
      ...(withBody ? { body: request, duplex: 'half' } : {}),
    });
    const encoding = upstream.headers
      .get('content-encoding')
      ?.trim()
      .toLowerCase();
    const decoded = upstream.body && encoding && encoding !== 'identity';
    const nominated = new Set(
      (upstream.headers.get('connection') ?? '')
        .toLowerCase()
        .split(',')
        .map((name) => name.trim()),
    );
    for (const [name, value] of upstream.headers) {
      if (
        name === 'set-cookie' ||
        transportHeaders.test(name) ||
        nominated.has(name) ||
        (decoded && (name === 'content-encoding' || name === 'content-length'))
      )
        continue;
      response.setHeader(name, value);
    }
    if (decoded) response.setHeader(SOURCE_DNS_DECODED_HEADER, '1');
    const cookies = upstream.headers.getSetCookie();
    if (cookies.length) response.setHeader('set-cookie', cookies);
    response.writeHead(upstream.status, upstream.statusText);
    response.flushHeaders();
    if (upstream.body)
      await pipeline(Readable.fromWeb(upstream.body), response, { signal });
    else response.end();
  } finally {
    await dispatcher.destroy();
  }
}

async function handle(
  request: IncomingMessage,
  response: ServerResponse,
): Promise<void> {
  const url = new URL(request.url ?? '/', 'http://source-egress.internal');
  if (request.method === 'GET' && url.pathname === '/') {
    response.writeHead(204).end();
    return;
  }
  if (request.method === 'GET' && url.pathname === '/resolve') {
    const host = dnsHostnameSchema.parse(url.searchParams.get('host'));
    const records = await lookup(host, { all: true });
    const addresses = [...new Set(records.map((record) => record.address))]
      .filter((address) => publicDnsAddressSchema.safeParse(address).success)
      .slice(0, SOURCE_DNS_ADDRESS_LIMIT);
    response.setHeader('content-type', 'application/json');
    response.end(JSON.stringify(addresses));
    return;
  }
  if (url.pathname === '/request') {
    await relay(request, response);
    return;
  }
  response.writeHead(404).end();
}

export function createSourceEgressServer() {
  return createServer(
    { maxHeaderSize: HTTP_FRAME_LIMIT * 2 },
    (request, response) => {
      void handle(request, response).catch(() => {
        if (response.headersSent) response.destroy();
        else response.writeHead(502, { [SOURCE_DNS_ERROR_HEADER]: '1' }).end();
      });
    },
  );
}
