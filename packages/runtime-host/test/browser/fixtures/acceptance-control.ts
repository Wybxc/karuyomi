import { create } from '@bufbuild/protobuf';
import {
  encodeControlResponse,
  parseControlRequest,
  parseControlResponse,
  type ControlRequest,
} from '@karuyomi/contracts';
import {
  ControlResponseSchema,
  RuntimeErrorCode,
  RuntimeErrorSchema,
  type ControlResponseJson,
  type RuntimeSlot,
} from '@karuyomi/protocol';

import { detailsRefreshAcceptanceControl } from './acceptance-details-refresh.js';
import { filterAcceptanceControl } from './acceptance-filters.js';
import { migrationAcceptanceControl } from './acceptance-migration.js';
import { preferenceGroupAcceptanceControl } from './acceptance-preference-groups.js';
import { readerBoundaryAcceptanceControl } from './acceptance-reader-boundary.js';
import { searchChoicesAcceptanceControl } from './acceptance-search-choices.js';
import { searchRetirementAcceptanceControl } from './acceptance-search-retirement.js';

interface BrowserRuntime {
  control(input: unknown): Promise<ControlResponseJson>;
}

const profile = new URLSearchParams(location.search).get('acceptance-runtime');
const originalHost = new URL(
  '/runtime/host.js?acceptance-original=1',
  location.origin,
);
await import(/* @vite-ignore */ originalHost.href);

const browser = window as Window & { karuyomiRuntime?: BrowserRuntime };
const host = browser.karuyomiRuntime;
if (!host) throw new Error('Acceptance requires the verified Web host');

if (profile === 'filters') {
  const outcome = new URLSearchParams(location.search).get('filter-outcome');
  browser.karuyomiRuntime = {
    ...host,
    control: filterAcceptanceControl((input) => host.control(input), outcome),
  };
}

if (profile === 'details-refresh') {
  const stage = new URLSearchParams(location.search).get(
    'details-refresh-stage',
  );
  if (stage !== 'details' && stage !== 'chapters') {
    throw new Error('Details refresh acceptance requires details or chapters');
  }
  browser.karuyomiRuntime = {
    ...host,
    control: detailsRefreshAcceptanceControl(
      (input) => host.control(input),
      stage,
    ),
  };
}

if (profile === 'migration') {
  const parameters = new URLSearchParams(location.search);
  const rejectBuild = parameters.get('migration-reject-build');
  const listingSource = parameters.get('migration-listing-source');
  if (!rejectBuild || !listingSource) {
    throw new Error('Migration acceptance requires exact fixture targets');
  }
  browser.karuyomiRuntime = {
    ...host,
    control: migrationAcceptanceControl(
      (input) => host.control(input),
      rejectBuild,
      listingSource,
    ),
  };
}

if (profile === 'preference-groups') {
  browser.karuyomiRuntime = {
    ...host,
    control: preferenceGroupAcceptanceControl((input) => host.control(input)),
  };
}

if (profile === 'reader-boundary') {
  browser.karuyomiRuntime = {
    ...host,
    control: readerBoundaryAcceptanceControl((input) => host.control(input)),
  };
}

if (profile === 'retire-search') {
  browser.karuyomiRuntime = {
    ...host,
    control: searchRetirementAcceptanceControl((input) => host.control(input)),
  };
}

if (profile === 'search-choices') {
  browser.karuyomiRuntime = {
    ...host,
    control: searchChoicesAcceptanceControl((input) => host.control(input)),
  };
}

if (profile === 'stop' || profile === 'close' || profile === 'cache') {
  let heldSearch:
    | {
        requestId: string;
        generation: string;
        slot: RuntimeSlot;
        release(): void;
      }
    | undefined;
  let searchHeld = false;
  let cacheHeld = false;
  let resetSlot: RuntimeSlot | undefined;
  let resetFailures = profile === 'close' ? 2 : 1;

  const audit = (
    event: string,
    fields: Record<string, string | number | boolean>,
  ) =>
    console.info(
      'ACCEPTANCE_RUNTIME_CONTROL',
      JSON.stringify({ profile, event, ...fields }),
    );
  const delay = (milliseconds: number) =>
    new Promise<void>((resolve) => setTimeout(resolve, milliseconds));
  const lostReply = (request: ControlRequest) =>
    encodeControlResponse(
      create(ControlResponseSchema, {
        requestId: request.requestId,
        slotId: request.slotId,
        result: {
          case: 'error',
          value: create(RuntimeErrorSchema, {
            code: RuntimeErrorCode.RUNTIME_LOST,
            message: 'Acceptance fixture withheld the runtime acknowledgement',
          }),
        },
      }),
    );

  browser.karuyomiRuntime = {
    ...host,
    async control(input) {
      let request: ControlRequest;
      try {
        request = parseControlRequest(input);
      } catch {
        return host.control(input);
      }
      const { command, slotId } = request;
      if (
        profile === 'cache' &&
        command.case === 'forgetExtensionArtifact' &&
        !cacheHeld
      ) {
        cacheHeld = true;
        const response = await host.control(input);
        const result = parseControlResponse(response).result;
        if (result.case === 'completed' && result.value.completed) {
          audit('cache-held', { sha256: command.value.sha256 });
          await delay(7000);
          audit('cache-delivered', { sha256: command.value.sha256 });
        }
        return response;
      }
      if (
        profile !== 'cache' &&
        !searchHeld &&
        command.case === 'invoke' &&
        command.value.request.case === 'search'
      ) {
        searchHeld = true;
        const { requestId, generation } = command.value;
        let release = () => {};
        const gate = new Promise<void>((resolve) => {
          release = resolve;
        });
        const timer = setTimeout(release, 25000);
        const pending = { requestId, generation, slot: slotId, release };
        heldSearch = pending;
        try {
          const response = await host.control(input);
          const result = parseControlResponse(response).result;
          audit('search-buffered', {
            requestId,
            generation,
            hostResult: result.case ?? 'missing',
            items:
              result.case === 'source' &&
              result.value.payload.case === 'mangaPage'
                ? result.value.payload.value.mangas.length
                : 0,
          });
          await gate;
          audit('search-delivered', { requestId, generation });
          return response;
        } finally {
          clearTimeout(timer);
          heldSearch = undefined;
        }
      }
      if (
        command.case === 'cancel' &&
        heldSearch?.requestId === command.value.requestId &&
        heldSearch.generation === command.value.generation &&
        heldSearch.slot === slotId
      ) {
        const pending = heldSearch;
        const actual = await host.control(input);
        audit('stop-held', {
          requestId: pending.requestId,
          generation: pending.generation,
          hostResult: parseControlResponse(actual).result.case ?? 'missing',
        });
        await delay(6500);
        resetSlot = slotId;
        pending.release();
        audit('stop-reply-lost', {
          requestId: pending.requestId,
          generation: pending.generation,
        });
        return lostReply(request);
      }
      if (command.case === 'rebuild' && resetSlot === slotId) {
        const response = await host.control(input);
        const result = parseControlResponse(response).result;
        if (result.case !== 'completed' || !result.value.completed)
          return response;
        const lost = resetFailures > 0;
        if (lost) --resetFailures;
        audit('reset', { slot: slotId, acknowledgementDelivered: !lost });
        if (!lost) resetSlot = undefined;
        return lost ? lostReply(request) : response;
      }
      return host.control(input);
    },
  };
}
