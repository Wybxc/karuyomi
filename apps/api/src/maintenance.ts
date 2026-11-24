export { RuntimeSession } from './runtime-session.js';

export default {
  fetch(): Response {
    return new Response('Karuyomi 维护中，请稍后重试。\n', {
      status: 503,
      headers: {
        'Cache-Control': 'no-store',
        'Content-Type': 'text/plain; charset=utf-8',
        'Retry-After': '120',
        'X-Karuyomi-Maintenance': '1',
      },
    });
  },
};
