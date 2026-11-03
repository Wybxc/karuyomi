import { DurableObject } from 'cloudflare:workers';

// Coordination boundary only. Source execution stays in the client Worker.
// Session/callback routes are introduced with P0-A, after their contracts exist.
export class RuntimeSession extends DurableObject {
  override async fetch(): Promise<Response> {
    return Response.json(
      { error: 'runtime_sessions_not_implemented' },
      { status: 501, headers: { 'Cache-Control': 'no-store' } },
    );
  }
}
