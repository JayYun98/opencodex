# Lane F — dispositions

Baseline `origin/dev` = `4f8656cc0d8fb354dfd7ac427be4049929460638` (2.59.0). Every
judgment below is taken at the pull request’s current head, measured with
`git merge-tree --write-tree` for conflicts and direct check-run queries for CI.
No local suite, typecheck, build, install, or `ocx` invocation was used.

## Outcome

| Disposition | Count | Pull requests |
| --- | --- | --- |
| `MERGE` | 6 | #4523, #4526, #4572, #4593, #4594, #4805 |
| `PARK` | 6 | #4222, #4225, #4560, #4781, #4803, #4872 |
| `STALE_BEYOND_REVIVAL` | 1 | #4183 |
| `BLOCKED_ON_AUTHOR` | 22 | #4177, #4193, #4228, #4259, #4265, #4309, #4394, #4567, #4597, #4647, #4649, #4663, #4728, #4731, #4732, #4734, #4740, #4793, #4795, #4804, #4823, #4910 |
| `SUPERSEDED` | 0 | — |
| `NOT_APPLICABLE` | 0 | — |

Nothing in this set was independently closed by `dev`, so no `SUPERSEDED` or
`NOT_APPLICABLE` judgment is available. #4183 is the only assigned pull request
whose disposition supports closing it.

## Two facts that shape every judgment

**Repository CI has run at the exact head of only two of the 35.** #4222
(`fc8460d70a`) and #4731 (`1527754747`) carry full matrices. The other 33 heads
have only `enforce-target`, `hygiene`, `label`, and `resolve-pr`. Fork
contributors cannot start repository CI, so this is not an author failing — it
means every `MERGE` below carries a host obligation to run full CI at the exact
head first.

**A `CONFLICTING` flag on this set is usually documentation churn.** Each
`structure/` doc records ownership for the source it covers, and several authors
prepend a paragraph to `structure/runtime.md`, so two independent pull requests
collide on line 3 of a file neither of them is really changing. #4523 (11
conflicts), #4526 (5), #4593 (4), #4572 (2), and #4594 (1) conflict *only* in
`structure/*.md`; their code merges clean. #4560 conflicts only in
`scripts/test-layout/layout.json` and `tests/fixtures/test-layout-expected.json`,
which is registry churn of the same kind. Distinguish that from #4183, #4731,
#4259, and #4228, where the conflict is in live source.

## MERGE

All six need a merge-ref refresh — `4f8656cc0d` is an ancestor of none of these
heads — and full repository CI at the refreshed head. The host performs both.

### #4523 — validate provider send paths before management writes

Head `6e275a82e5`. The file-config schema validated `responsesPath` and
`chatCompletionsPath` (`src/config/schema/config-schema.ts:363`); the management
write boundary did not, so `POST /api/providers` accepted
`responsesPath: "https://other.example.test/send"` and persisted it. The fix adds
the same check to `providerManagementConfigError` in `src/server/auth-cors.ts` and
moves the validator to `src/config/provider-relative-send-path.ts` so the
management boundary does not have to import the config facade to reach it. It
reads `raw[field]` rather than the typed view, which is how a non-string value is
caught at all.

The coverage is unusually direct about the property that matters: each rejection
case asserts that in-memory config and the bytes on disk are both unchanged, and
that `providerDestinationResolvedError` was never called. A separate
`tests/server/provider-send-path-import.test.ts` spawns a child process that
imports the management module before `src/config.ts` to pin the initialization
order the refactor exists to protect. Nothing was deleted — the `config()` helper
moved to `tests/helpers/management-relative-send-paths.ts` and is re-imported.

Exact-head fork run `35241195780` (luvs01) is green on every job except
`macos control`, which was cancelled at the 30-minute dispatch cap and flips the
aggregate `ci` job to failure.

Residual: this rejects configurations the API previously accepted. A user holding
a pre-existing invalid send path can no longer `PATCH` unrelated transport fields
on that provider until the bad value is removed — the PR’s own test asserts that
behavior deliberately. For a field that can redirect credentialed traffic to
another host, tightening is the right trade, but it is a user-visible change and
belongs in the release note.

### #4526 — avoid eager Unicode schema cloning

Head `c376cc4faf`. Rewrites `stripUnicodePropertyPatterns` in
`src/adapters/responses-tool-schema.ts` to clone only the ancestors of a removed
`pattern` and share every untouched subtree, instead of rebuilding the whole tree
and allocating one closure per sibling.

I traced each branch against the old implementation and found no behavioral
divergence. Name-bag depth is preserved: the old code pushed name-bag children
with `inNameBag: false` through an explicit branch, and
`!frame.inNameBag && SCHEMA_NAME_BAG_KEYS.has(key)` evaluates the same way in
both directions. Preserved and literal-value keys still skip recursion and keep
their values through the clone. Non-object values are no longer pushed onto the
stack, which was a no-op assignment before.

The obvious worry — that structural sharing lets a caller mutate its own input
through the result — does not hold, because the old code already did
`return dropped === 0 ? node : result`, returning the input by identity in the
common no-op case. No caller could ever have relied on receiving a fresh tree.
Both callers (`src/adapters/openai-responses/tool-schema.ts:16` and
`src/adapters/openai-chat/tool-schema.ts:429`) spread the result into a new object
rather than mutating it.

Two added tests assert the property the rewrite is for, using `toBe` identity on
untouched siblings across a 25,000-key schema and on an array path, and assert the
input is unmodified. No existing test was removed. `Ingwannu` approved on
2026-09-14; no review thread is open. Exact-head fork run `35147630288` is green
except the same cancelled `macos control`.

Residual: the old code rebuilt every object with a null prototype; the new code
does so only for cloned ancestors. A schema carrying `__proto__` as data in an
untouched subtree is now returned by reference. That is identical to the input and
serializes identically, so I could not construct a wire-visible difference, but it
is the one semantic the rewrite genuinely narrows.

### #4572 — register legacy recovery backups for owned cleanup

Head `f4fbc146c7`. Eight lines in `src/oauth/store.ts`. `backupLegacyOnce` copies
`auth.json` to `auth.json.pre-multiauth` during the multi-account migration but
never claimed it, so an owned uninstall left a credential copy on disk.
Registration is best-effort by design: both a `false` return and a thrown error
emit one fixed warning and keep the backup, because an intentionally unowned home
must still get downgrade recovery.

Three tests cover the owned-uninstall path, both registration failure modes with
an assertion that the warning carries no error detail, and the case where a
pre-existing unregistered backup is left unclaimed and unmodified.
`structure/config.md` explains why timestamped invalid-config copies are
deliberately *not* registered — unbounded manifest growth would push it past its
path ceiling, and a manifest that stops validating makes uninstall refuse
outright, which is worse than the leak being fixed.

CI evidence needs care. The exact head has a green `Service lifecycle` run
(`35149363750`) but no Cross-platform run. The last full run on this branch,
`35038844920` at the earlier head `01f2b161fb`, failed — and the failures are
`desktop restart membership is a path boundary` and two `macOS desktop restart`
cases on a Windows shard, unrelated to OAuth storage. Those are the test families
that dev commit `6ed8986c64` (#4835) repaired, and `6ed8986c64` is now merged into
this branch. So the red run is dev-side breakage the branch has since absorbed,
not a defect here — but the exact head has never had a full matrix, so running one
is not a formality.

### #4593 — bind stored Direct account identity on both materializers

Head `3ffe766d91`. Two lines of source: `selected.delete("chatgpt-account-id")`
before the stored credential is installed, in both
`materializeCodexUpstreamAuth` and `materializeCodexUpstreamAuthAsync`
(`src/codex/auth-context.ts`). Without it a caller-supplied `chatgpt-account-id`
survived substitution and rode upstream alongside *our* stored Direct token — the
caller’s claimed identity paired with a credential it never held.

Coverage reaches three layers rather than restating the unit: the sync and async
materializers directly, `/v1/responses` and `/v1/responses/compact` end to end in
`tests/responses/responses-native-main-refresh.test.ts`, and the standalone
transcription route in `tests/server/audio-transcriptions.test.ts`. The tests also
assert the inbound `Headers` object is not mutated. The pre-existing #1686 test was
relocated verbatim into `tests/helpers/stored-direct-identity.ts` and re-registered,
so no assertion was lost.

Same CI shape as #4572: green `Service lifecycle` run `35150228320` at the exact
head, and the last full run (`35039034213`, earlier head `36bba42f69`) red on the
same dev-side Windows desktop-restart tests now fixed by `6ed8986c64`.

### #4594 — preserve retryable reauth cancellation and settle terminal failures

Head `aa67f23ac9`. A retryable `DELETE` failure during device reauthentication
moved the flow into a phase the main-account card renders nothing for, so the live
device code, the waiting notice, and the Cancel control all vanished while the
device authorization was still open. `gui/src/components/use-main-device-reauth.ts`
now keeps ownership and polling through that failure, marks the state
`cancelFailed`, and distinguishes an expired flow (404 `unknown_flow`) from a lost
response instead of claiming either cancellation or success.

Exact-head fork run `35217283983` is the best CI evidence in the whole assigned
set: `test 1-4/4`, `windows 1-9/9`, `macos 1-2/2`, `gates`, `storage policy`,
`docker smoke`, `docs site build`, `api usage`, `keyring` on three platforms, and
`npm-global` on three platforms all succeeded. Only `macos control` was cancelled,
which is what fails the aggregate `ci` job. The screenshot is embedded in the
description and labeled as an isolated fixture rather than a live login. No review
thread is open.

Residual: this is the least narrow of the six at 656 insertions, and it adds three
refs and a `cancelFailed` flag to a hook that was previously a flat state machine.
The 391-line ownership test file is what makes that reviewable.

### #4805 — make the gajae loopback integration work without an API key env var

Head `b67c24076c`. Replaces the required `apiKeyEnv` with the non-secret
`opencodex-loopback` placeholder already used by OMP, MCode, and ZCode, so the
generated provider emits a schema-known `apiKey` and the dashboard stops warning
about a key that does not apply. Writer coverage checks refresh and disable
behavior, export tests pin the exact emitted fields, and GUI coverage confirms the
keyless dialog keeps its copy and download actions. All six review threads are
resolved at the current head, and lane C already confirmed the screenshot and the
`enforce-target` pass.

## PARK

- **#4803** — the pre-judgment holds. `src/server/chat-native-sse.ts:367-378` now
  treats a text-bearing stream that reaches EOF with no terminal event as a
  success, and EOF cannot distinguish an intentional finish from a truncated
  transport. Tool-bearing and empty streams stay fail-closed, but ordinary text
  moves from terminal-evidence-required to best-effort. That is a contract change
  needing a maintainer decision, ideally provider-scoped, not an easy merge.
- **#4222** — opt-in reuse of a completed parent Desktop chat’s prompt-cache prefix,
  wired at `src/adapters/openai-responses/passthrough.ts:421-454`. `dev` has no
  `src/codex/side-chat-cache.ts`, so it is neither superseded nor inapplicable.
  Worth correcting the intake reading: exact-head run `34963407148` is **green**,
  and the `enforce-target`/`hygiene` failures report only `unsponsored_surface` for
  `src/server/auth-cors.ts` — a sponsorship gate, not a test failure.
- **#4225** — pins initial effort and inserts `configuration_update` items to hold
  Astra prompt prefixes across effort changes. Not in `dev`. Excluded as an
  experiment, and the description itself says the net cache benefit is unverified.
  1,124 commits behind with a real conflict at `src/adapters/openai-responses.ts`.
- **#4872** — routes verified manual `/compact` to a configured model and effort
  (`src/server/responses/request-prepare.ts:151-155,441-444`). One commit behind,
  no conflicts, all 12 review threads resolved. The cleanest park in the set: it is
  simply not this line.
- **#4781** — native main login profile management, 1,602 additions, explicitly
  phase 1 of the #3417 feature. A feature, not a bug fix.
- **#4560** — provider accounts workspace redesign, 5,146 additions across 44
  files, described by its author as Part 1 of 2 with pool rotation to follow. Out
  of scope by size and by staging.

## STALE_BEYOND_REVIVAL

- **#4183** — per-account model selection through `codexAccountPickerModels`. The
  feature is live and absent from `dev` (no occurrence at `4f8656cc0d`), and all 14
  review threads are resolved, so the work itself is sound. What kills it is the
  ground moving: the head is 1,203 commits behind and each of its three principal
  implementation points was split out from under it — `src/config.ts` by
  `d2d35e02e2`, `src/server/index.ts` by `a63a47363f`, and
  `src/codex/catalog/sync.ts` by `c63e9ea676`. Six substantive conflicts remain in
  live source and docs. Rebasing 41 files onto the new leaf owners is
  reconstruction by the author, not a host-side refresh. This is the only assigned
  pull request whose disposition supports a close, and it should carry an English
  comment naming those three splits.

## BLOCKED_ON_AUTHOR

Grouped by what is actually missing.

### A live defect found at the current head

- **#4734** (SSH endpoint detection) — `isAllowedSshEndpoint` evaluates the whole
  `ProxyCommand` string, so a command containing any allowed token bypasses
  detection while still exposing a different endpoint. The patterns also miss
  equals-delimited directives and commented `HostName` lines. Two threads open.
  Predecessor #4623 did land, as `43cd1ade10`.
- **#4804** (`OCX_FRESH_CONNECTION_HOSTS`) — freshness is computed from the initial
  URL, before `dispatchOverride` can replace the destination: OAuth reselection
  substitutes `rebuilt.url` at `src/server/responses/request-transport.ts:445`, and
  native Chat substitutes `activeRequest.url` at `src/server/chat-native.ts:330-353`.
  The final host can inherit policy meant for another host or miss policy it needs.
  Tests only cover unchanged destinations, and the environment variable is undocumented.
- **#4795** (usage append) — presented as allocation and syscall reduction, but it
  changes observable behavior. The old code re-applied `chmodSync` to the usage
  directory and file on every append; the new code skips both permanently once
  cached (`src/usage/log.ts:858-877`), so permissions widened externally are never
  narrowed again. The added test counts calls and covers directory deletion but
  never broadens permissions and checks for re-hardening.
- **#4567** (pool threshold summary) — `gui/src/codex-quota-utils.ts:81-87` scores
  from the general `updatedAt` with a five-hour window and compares reset
  timestamps without normalizing seconds; server truth at
  `src/codex/routing/cooldown-math.ts:162-177` uses `shortObservedAt`, a
  five-minute freshness bound, and `resetAtToMs`. The GUI and the router can
  disagree about the same account. Fixtures at
  `gui/tests/account-pool-strategy.test.tsx:296-305` also violate `AccountQuota`.
  Its exact-head `enforce-target` is cancelled, so there is no current gate
  evidence either.
- **#4910** (CLI installation attestation) — not narrow at 1,757 additions across 40
  files including native FFI and a CLI contract. Three live findings:
  `cli-installation-targets.ts:41` reads the entire candidate before slicing to
  8 KiB; lines 91-99 silently substitute PATH-resolved `codex` for a configured
  path-shaped candidate, which can attest a different installation than the one
  named; and `cli-installation-identity.ts:167` accepts the backing shim although
  the documented contract admits only `codex.cmd` or `bin/codex.js`. Fork run
  `35255842168` does target the exact SHA with all substantive jobs green, but
  `macos control` cancellation fails the aggregate.
- **#4394** (Orca account import) — five threads open.
  `src/codex/account-store.ts:959` takes the mutation lock for every source-token
  read; the persisted-record validator admits incomplete source links;
  `src/codex/orca-import.ts:188-193` can let a rollback failure replace the
  original commit error.
- **#4193** (Fast selector rows toggle) — real conflicts in `gui/src/main.tsx` and
  `src/server/management/config-routes.ts`, plus a live thread:
  `config-routes.ts:619-625` converges only the Codex catalog and leaves existing
  external-client pickers unsynchronized, and `FastRowsSetting.tsx:94-97` rolls
  back after an ambiguous PUT without reconciling what was persisted.
- **#4265** (Vietnamese localization) — registration is wired correctly through
  `catalogs.ts` and `shared.ts` with parity tests, but the Lab UI still renders
  English at `gui/src/i18n/lab-translations.ts:481-487`, which is the unresolved
  review finding. Incomplete for a localization PR.

### A structural conflict the author has to resolve

- **#4731** (in-place SSE scanning) — the interesting case, because it *has* full
  green CI at its exact head `1527754747`. The conflict in `src/server/relay.ts` is
  semantic, not mechanical: dev `c272309b37` added `createBoundedResponseLogBody`,
  dropped relay’s use of the shared empty-bytes constant, and restored a
  relay-local `sseDataPayload`, while this PR moves that parser into the shared
  rewrite module. Someone must pick one parser and keep the bounded
  response-log integration. The existing green run cannot cover whatever
  resolution is chosen.
- **#4228** (`projectContext` envelope) — real conflict in
  `src/adapters/command-code.ts`, gates failing `unsponsored_surface`, five threads
  formally open although the one non-outdated test finding is addressed by
  `a0a69ff8e3`.

### Security or workflow surface requiring explicit review

- **#4649** (remember admin token) — stores an accepted admin token in plaintext
  `localStorage` (`gui/src/admin-token-dialog.ts:10-23,177-180`) and silently
  reuses it after verification (`gui/src/api.ts:293-305`). Opt-in and tested, with
  a screenshot, and the only open thread is outdated — but this is credential
  handling, so `MAINTAINERS.md` requires explicit security review of the
  same-origin script/XSS exposure and the token lifetime. No maintainer has
  approved it; the reviews are comments.
- **#4597** (manual release-gate lane) — touches `.github/`, which is release
  automation under `MAINTAINERS.md:68-69`. Gates fail `unsponsored_surface`, 52
  commits behind including seven later CI changes, and the workflow needs
  revalidation against current CI semantics. Its only conflict is structure-doc
  churn.
- **#4647** (Z.ai Start Plan) — exclusion holds and hardens. Not in `dev`, so not
  superseded. `captcha-solver.ts:217-219` fetches mutable CDN JavaScript and
  executes it through host-realm instrumentation around lines 631 and 1751-1765;
  direct gateway sends bypass the supplied executor at
  `zcode-start-plan.ts:173-183`; response bodies are unbounded at lines 67-84. It
  also adds `happy-dom` as a runtime dependency, which is why `package.json` and
  `bun.lock` conflict. Authentication plus dependency boundary, gates failing
  `new_suppression` and `unsponsored_surface`.
- **#4728** (four control planes) — 28,028 additions across 140 files with 13 open
  threads, including fixed-salt credential derivation at
  `src/credentials/vault.ts:26-27` and advertised-but-incomplete commands at
  `src/cli/skill.ts:14-45`. Not reviewable as one pull request; it needs splitting
  by control plane and trust boundary.
- **#4259** (ZCode app-server provider) — exclusion holds. `dev` has ZCode
  client-config export (`c9d10ed37a`, `f2034368db`) but no provider adapter or
  Desktop bridge, so not superseded. Its base predates the server, core, registry,
  and catalog splits (`a63a47363f`, `485a525aa9`, `ee9f4df7b1`, `47b1879af9`,
  `35969857f2`), giving five substantive code conflicts; the structure and layout
  conflicts are mechanical. `desktop-bootstrap.cjs:59-76` still leaves stale
  `agents-state.json` overrides, contradicting its own `zcode-agent.md:60-63`.

### New providers — judged on the four grounds, not on looking reasonable

Both endpoints are alive: each returns 401 without credentials.

- **#4309** (Crusoe) — the strongest of the two. `entries-extended.ts:217-280` names
  `@acheamponge` as maintenance owner and records the authenticated capture, and
  `crusoe-provider.test.ts:187-220` exercises Bearer validation and discovered-model
  filtering through real call paths. What blocks it is freshness: Crusoe’s current
  published catalog deprecated five of the fixture models on 2026-09-12, while the
  test still expects the older 17-model capture. Refresh the capture and the
  assertions.
- **#4823** (Opper) — capability and endpoint documentation is good, but two of the
  four grounds are missing. `opper-provider.test.ts:70-80` only checks URL
  construction and the absence of `apiKeyValidation`; it never exercises or
  fixtures a successful authenticated `/models` response. And no maintenance owner
  is named in the source — the description saying the author works at Opper and is
  happy to adjust is not an owner recorded where the registry can be held to it.

### Sound but unattested

- **#4793** (per-model cache metrics) — the fields already exist in
  `src/usage/summary.ts:1068-1088`, the GUI consumes them at
  `gui/src/pages/Usage.tsx:672-698`, the test verifies both reported values and
  unavailable-telemetry dashes, no coverage was weakened, merge-tree is clean, and
  no review comment is open. The screenshot is embedded. Only the four-box
  readiness checklist and CI are outstanding — the nearest miss in this group.
- **#4732** (registry lookup caching) — the maps are built from the module-static
  `PROVIDER_REGISTRY` at `src/router.ts:101` and the live model cache is still read
  per call at `src/router.ts:146`, so no invalidation path is owed. But the
  assertion at `tests/responses/responses-state-write-amplification.test.ts:245`
  has no matcher, and the routing test discriminates only one NVIDIA model-hint
  lookup out of three cached paths.
- **#4740** (single-pass log query) — no observable contract drift found: filtering
  stays one ordered predicate pass, tail still precedes the total, and limit/offset
  still select backward from the filtered end
  (`src/server/request-log.ts:1399-1468`), with the management route consuming
  count and rows together. Needs readiness and full CI, nothing else.
- **#4177** (blocked-model redirects) — reachable for a one-provider user whenever
  `blockedModelRedirects` is set, and it does not pull in Lab. The open question is
  compatibility: a bare mapping now reruns full routing for its target before
  default-provider resolution, where the previous `routeResult` behavior substituted
  the model after provider selection. A maintainer `CHANGES_REQUESTED` asked for an
  explicit policy on that and the current head has no replacement approval.

## What this means for the round target

Lane F yields six merge candidates and one close candidate out of 35. The
assigned set does not move the open-PR count below 50 on its own, and no
disposition here was chosen to make it do so.

