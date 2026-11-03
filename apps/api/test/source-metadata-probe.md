# Live Source metadata probe

This loopback harness loads the actual product TeaVM build through its private manifest and SHA-256 artifact loader. It runs the product `/api/bridge/http` route in real workerd with isolated D1/R2 state and an explicit `www.mangadraft.com` network policy. Its separate test entry verifies a real RS256 test JWT; the localhost proxy supplies that test assertion and maps its origin to the test API origin. It does not change or bypass authentication in the production entry point.

After building/importing the frozen product and installing workspace dependencies:

```sh
pnpm --filter @karuyomi/runtime-host build
node apps/api/test/source-metadata-probe.mjs runtime/teavm/.local/manifests/release9-mangadraft-product-e3505206005c25f69b92.json
```

Open the reported `http://127.0.0.1:8897/` URL and click **Run real metadata operations**. `SOURCE_PROBE_PORT` can select a different port. The probe opens the real Source, calls popular pages 1 and 2, search with the first real popular title, latest, details, chapters, and pages only when a real chapter reference is available. It never substitutes fixtures, changes extension bytes, or requests image bytes directly.

Results are saved to `runtime/teavm/.local/probes/source-metadata.json`. The report records response status, sizes, body hashes, public catalog parameters and small DTO summaries. It does not save Source cookies, authorization headers, response bodies or signed image query strings. Stop with Ctrl-C to dispose workerd and remove its temporary database/object state.

The checked-in observation is `runtime/teavm/verification/mangadraft-live-metadata.json`. On 2026-11-03, Chrome 156 returned 20 real entries for popular pages 1/2 and latest. Details and chapters were redirected to the upstream Human Verification page and failed with a structured Source error; pages could not proceed without a real chapter reference. No challenge was solved or bypassed.

Search returned a catalog but did not transmit the ordinary text query. Inspection of the frozen original JAR confirmed this is the Source's own behavior: its request builder includes filters and pagination but omits the text query; full-URL searches use another path. This result does not establish correct text search semantics. The probe does not verify production Access, native device behavior, or a complete metadata/reading loop.
