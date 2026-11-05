# Live Source metadata probe

This loopback harness loads the actual product TeaVM build through its public static manifest and explicit gzip artifact loader. It runs the product `/api/bridge/http` route in real workerd with isolated policy-only D1 state and an explicit `www.mangadraft.com` network policy. Its separate test entry verifies a real RS256 test JWT; the localhost proxy supplies that test assertion and maps its origin to the test API origin. It does not change or bypass authentication in the production entry point.

For each forwarded `/api/*` request, the proxy signs a new assertion with the same test subject, issuer, audience and key ID, a current `iat`, and a 30-minute `exp`. It does not cache an assertion from startup or extend an existing credential. This keeps a long-running local test service usable while the real verifier continues checking every request. It does not exercise production Access credentials, login cookies or expiration recovery; those require separate dedicated tests.

The first Android server-sync attempt on 2026-11-05 used the former startup-scoped assertion after its 30-minute lifetime had elapsed: bootstrap/state requests returned 401 and the official integration test failed in the Access-paused state. That attempt is a failure, not a sync or production Access pass. Its raw report remains in the ignored `.local/android-server-sync/android-from-web.log`; subsequent runs must record their own inputs and results.

The API hop uses pinned Undici directly against `unsafeGetDirectURL()` for the user Worker, with a loopback HTTP Host/Origin and the normal product checks. It does not use Miniflare's front `dispatchFetch` Worker, which has independent request-signal settings. Each API request owns one client/socket; a browser disconnect resets that socket before aborting its upload/response. This makes an idle HTTP/1 cancellation visible to workerd; ordinary local stream destruction alone did not do so in a controlled comparison. It does not establish production HTTP/2 or HTTP/3 behavior.

After building a product package and installing workspace dependencies:

```sh
pnpm --filter @karuyomi/runtime-host build
node apps/api/test/source-metadata-probe.ts PATH_TO_OUTPUT/manifest.json PATH_TO_OUTPUT/artifacts
```

Open the reported `http://127.0.0.1:8897/` URL and click **Run real metadata operations**. `SOURCE_PROBE_PORT` can select a different port. `SOURCE_PROBE_ALLOWED_HOSTS` supplies a comma-separated explicit hostname policy; it defaults to `www.mangadraft.com` and is passed directly to registration, never inferred from requests. For example, set it to `arknights.global` for the Arknights Comics build. `SOURCE_PROBE_SOURCE_ID` selects one exact Source ID from a multi-Source package; it must appear in the manifest and runtime session. With no selection, the first runtime Source is used. `SOURCE_PROBE_EVIDENCE` can select a separate report path for each build. The sole bundle file is `artifacts/<canonicalSHA>.gz`; files default to the `artifacts` directory beside the manifest. A controlled static snapshot provides `/extensions/index.json`, `/extensions/builds/<buildId>/manifest.json` and `/extensions/artifacts/<canonicalSHA>.gz` directly from the loopback static server. Registration uses the explicit local `--static-root` snapshot; extension bytes never pass through an `/api` proxy or R2. Only HTTP bridge requests pass through the authenticated workerd proxy. The probe opens the real Source, calls popular pages 1 and 2, search with the first real popular title, latest only when supported, details, chapters, and pages only when a real chapter reference is available. `supportsLatest=false` records an explicit unsupported-operation skip. It never substitutes fixtures, changes extension bytes, or requests image bytes directly.

Results default to `runtime/teavm/.local/probes/source-metadata.json`. Each network entry retains the HTTP `requestId` and `runtimeGeneration`; response META must match both before any body is relayed. HTTP request IDs identify individual network requests, separately from the Source/image control request ID. The report also records response status, sizes, incremental body hashes, public catalog parameters, header/Cookie names, image hosts, counts of processing fragments, and small DTO summaries. Request and response use the strict HTTP-v2 reader and re-encode one demanded DATA frame at a time; a Node pipeline preserves downstream backpressure. There is no network-body aggregation, Base64 parsing, detached tee consumer or background evidence reader. Disconnect/abort cancels dispatch and both framed readers; that alone does not prove that a remote origin observed cancellation. HTML diagnostics inspect only an 8KiB prefix, so an absent challenge marker does not prove that the whole page is challenge-free. It does not save Source cookies, authorization headers, response bodies or signed image query strings.

Stop with Ctrl-C, then verify that this process, its workerd child and reported port are gone. The pinned Miniflare installs a signal exit hook that can terminate before this harness's asynchronous dispose/remove completes; exit code 130 alone does not prove graceful cleanup or evidence persistence. Inspect and remove only this run's temporary database/static snapshot if it remains; never remove another run's state or AOT inputs.

Set `SOURCE_PROBE_IMAGES=1` to additionally acquire the first, middle and last real chapter pages through `runtime.acquireImage`. This needs a build exporting the managed Page session and processed image ABI. The original Source resolves and fetches each image; the probe never fetches a raw Source image URL. Each resource must belong to the current generation, expose a managed Blob URL, and decode in the browser with the reported dimensions. The probe detaches the image before releasing the resource, checks repeated release, checks URL revocation, and closes the original Page session. Reports retain dimensions, byte counts and pass/failure summaries only. This checks the Web host resource boundary; it does not establish Flutter navigation, processed/decrypted image compatibility, native file transfer or peak memory.

The current Arknights Comics first title's metadata identifies `webusstatic.yo-star.com` as its image host; for that explicit local image test use `SOURCE_PROBE_ALLOWED_HOSTS=arknights.global,webusstatic.yo-star.com`. This is a local test policy, not an automatic approval of the package in production. If a later chapter uses another host, inspect and explicitly select the test policy; the probe does not learn or expand its allowlist from traffic.

To exercise the actual Flutter UI against the same build and network boundary, first run `pnpm build` and set `SOURCE_PROBE_READER_DIR=apps/reader/build/web` when starting this harness. The normal built app is served at `/`, and the explicit metadata/image gate moves to `/probe`. Static Flutter files use the pinned `sirv` middleware; missing `/runtime`, `/extensions` and `/api` paths never fall back to the app. The app's bootstrap still passes through the test JWT verifier and isolated workerd. This verifies the local product flow, not a production Access login; use a real Source and the normal browse, chapter and reader controls.

## Optional HTTPS and the Native main entry

The HTTP listener always remains available at `http://127.0.0.1:8897`, with `SOURCE_PROBE_PORT` selecting its port. Supply both `SOURCE_PROBE_TLS_CERT` and `SOURCE_PROBE_TLS_KEY` to additionally listen at `https://localhost:8898`; `SOURCE_PROBE_TLS_PORT` selects that port. Both listeners bind only to `127.0.0.1`, use the exact same handler, and share one workerd/D1 instance. Ports must be different integers from 1 to 65535. Both listeners are closed together on shutdown or a listener startup failure.

The certificate must be currently valid, contain `localhost` in its SAN, and match the private key. The Native platform must already trust its issuing CA through the normal platform trust mechanism. The built-in browser can use the HTTP listener while only an isolated iOS Simulator or Android debug App trusts the development CA. This harness never installs a certificate, changes trust settings or disables TLS verification; an expired historical fixture certificate cannot be reused.

For example, after preparing trusted local certificate files and building the actual app:

```sh
SOURCE_PROBE_TLS_CERT="$PWD/.local/server-sync/tls/localhost.pem" \
SOURCE_PROBE_TLS_KEY="$PWD/.local/server-sync/tls/localhost-key.pem" \
SOURCE_PROBE_READER_DIR=apps/reader/build/web \
SOURCE_PROBE_SOURCE_ID=1538249443376436084 \
SOURCE_PROBE_ALLOWED_HOSTS=xkcd.com,imgs.xkcd.com \
SOURCE_PROBE_PORT=8897 \
SOURCE_PROBE_TLS_PORT=8898 \
SOURCE_PROBE_EVIDENCE=.local/server-sync/xkcd-network.json \
node apps/api/test/source-metadata-probe.ts \
  .local/v4-source-validation/xkcd/manifest.json \
  .local/v4-source-validation/xkcd/artifacts
```

This prints both `http://127.0.0.1:8897` for the built-in browser and `https://localhost:8898` for Native. Configure a fresh Native build with the exact HTTPS `APP_ORIGIN`; iOS Simulator can reach the host loopback listener, and Android Emulator needs an explicit `adb reverse tcp:8898 tcp:8898`. Use an isolated debug App's exact-localhost Network Security Config if Android requires a development CA; keep system roots, hostname checks and pin validation intact. Do not change the production App's trust configuration. These two origins are explicit test-only aliases of the same account and database, not evidence of production Access or shared-cookie behavior.

`GET` and `HEAD` on `/runtime/host` and `/runtime/host.html` serve the exact built `dist/public/runtime/host.html`, not a substitute control page. Run the normal build first so this file exists. The product Native document-start host and bundled materials remain responsible for the runtime; the harness does not inject a replacement Native runtime. The optional Web UI continues to use its built Flutter files and product Web host.

All `/api/*` traffic, including library and state routes, reaches the same real workerd/D1 instance and verified `probe-owner` test subject. The probe supplies a signed test assertion on this explicit loopback hop; it does not exercise production Access, Native login cookies or an identity switch. Its network report records Source HTTP operations, not an automatic business mutation trace or Flutter UI verdict.

The same ignored evidence report includes `tlsRequestPaths`: counts of pathnames received by the HTTPS listener only. It does not record request queries, headers or bodies, infer a platform from User-Agent, or alter serving behavior. The HTTP browser listener never contributes to these counts. At most 128 distinct pathnames of up to 2048 characters are retained; any excess sets `tlsRequestPathOverflow=true`, which invalidates a claim that all Native requests were observed. To establish that this run's Native client used its bundled runtime materials, first require a nonzero `/runtime/host` or `/runtime/host.html` count and `tlsRequestPathOverflow=false`, then verify zero requests to `/runtime/materials.json`, every `/runtime/materials/*` path, `/runtime/host.js` and `/runtime/worker.js`. Absent entries have count zero. Keep the HTTPS listener exclusive to that Native client during this observation; these counts do not independently identify a client or establish successful runtime initialization or reading.

The startup log prints `Local D1 state: ...`. While this run is alive, that exact path can be used for read-only local inspection:

```sh
pnpm --filter @karuyomi/api exec wrangler d1 execute DB \
  --local --persist-to /ABSOLUTE/PRINTED/STATE \
  --command "SELECT revision FROM account_state WHERE subject = 'probe-owner'" \
  --json
```

Never replace `--local` with `--remote` for probe evidence. Record UI actions/screenshots and read back the business API or these local rows separately; two clients of this harness are local integration evidence, not a production or physical-device verdict.

The useful historical conclusions are summarized in [runtime evidence](../../../docs/verification/runtime-evidence.md); raw reports stay in the ignored local research archive. Those earlier Source results used HTTP v1 and do not establish v2 online compatibility. In that run on 2026-11-03, Chrome 156 returned 20 real entries for popular pages 1/2 and latest. Details and chapters were redirected to the upstream Human Verification page and failed with a structured Source error; pages could not proceed without a real chapter reference. No challenge was solved or bypassed.

Search returned a catalog but did not transmit the ordinary text query. Inspection of the frozen original JAR confirmed this is the Source's own behavior: its request builder includes filters and pagination but omits the text query; full-URL searches use another path. This result does not establish correct text search semantics. The probe does not verify production Access, native device behavior, or a complete metadata/reading loop.
