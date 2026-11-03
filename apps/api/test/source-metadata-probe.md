# Live Source metadata probe

This loopback harness loads the actual product TeaVM build through its private manifest and SHA-256 artifact loader. It runs the product `/api/bridge/http` route in real workerd with isolated D1/R2 state and an explicit `www.mangadraft.com` network policy. Its separate test entry verifies a real RS256 test JWT; the localhost proxy supplies that test assertion and maps its origin to the test API origin. It does not change or bypass authentication in the production entry point.

After building a product package and installing workspace dependencies:

```sh
pnpm --filter @karuyomi/runtime-host build
node apps/api/test/source-metadata-probe.ts PATH_TO_OUTPUT/manifest.json PATH_TO_OUTPUT/artifacts
```

Open the reported `http://127.0.0.1:8897/` URL and click **Run real metadata operations**. `SOURCE_PROBE_PORT` can select a different port. `SOURCE_PROBE_ALLOWED_HOSTS` supplies a comma-separated explicit hostname policy; it defaults to `www.mangadraft.com` and is passed directly to registration, never inferred from requests. For example, set it to `arknights.global` for the Arknights Comics build. `SOURCE_PROBE_EVIDENCE` can select a separate report path for each build. Artifact files default to the `artifacts` directory beside the manifest. The probe opens the real Source, calls popular pages 1 and 2, search with the first real popular title, latest only when supported, details, chapters, and pages only when a real chapter reference is available. `supportsLatest=false` records an explicit unsupported-operation skip. It never substitutes fixtures, changes extension bytes, or requests image bytes directly.

Results default to `runtime/teavm/.local/probes/source-metadata.json`. The report records response status, sizes, incremental body hashes, public catalog parameters and small DTO summaries. Request and response use the strict HTTP-v2 reader and re-encode one demanded DATA frame at a time; a Node pipeline preserves downstream backpressure. There is no network-body aggregation, Base64 parsing, detached tee consumer or background evidence reader. Disconnect/abort cancels dispatch and both framed readers. HTML diagnostics inspect only an 8KiB prefix, so an absent challenge marker does not prove that the whole page is challenge-free. It does not save Source cookies, authorization headers, response bodies or signed image query strings. Stop with Ctrl-C to dispose workerd and remove its temporary database/object state.

The useful historical conclusions are summarized in [runtime evidence](../../../docs/verification/runtime-evidence.md); raw reports stay in the ignored local research archive. Those earlier Source results used HTTP v1 and do not establish v2 online compatibility. In that run on 2026-11-03, Chrome 156 returned 20 real entries for popular pages 1/2 and latest. Details and chapters were redirected to the upstream Human Verification page and failed with a structured Source error; pages could not proceed without a real chapter reference. No challenge was solved or bypassed.

Search returned a catalog but did not transmit the ordinary text query. Inspection of the frozen original JAR confirmed this is the Source's own behavior: its request builder includes filters and pagination but omits the text query; full-URL searches use another path. This result does not establish correct text search semantics. The probe does not verify production Access, native device behavior, or a complete metadata/reading loop.
