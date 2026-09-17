# 2.59.0 merged-tree composition audit

Audit target: `a0f611d4aceb9476d44268e43722273b7b211846`, 2026-09-18.
This candidate is held. It is not releasable: the audit found two functional
merge-result defects and hosted Windows exposed a cold-path test failure.
A further credential-generation issue survived falsification but was explicitly
deferred by the release owner with the rationale recorded below.

These are failures of the integrated behavior. The record does not attribute
them to the quality of an isolated PR review. The release host will integrate
focused fixes, freeze a new exact dev SHA and dispatch a fresh `lane=all` run.
Neither this old candidate nor a collection of individual PR greens substitutes
for that final merged-tree proof.

## Confirmed composition defects

### Reauthentication polling and cancellation ownership

At `gui/src/components/use-main-device-reauth.ts:183-194`, a non-2xx polling
response returns from the poll loop. The cancellation path preserves the same
active flow at `:120-131`, including when its DELETE fails. Together these
leave an active card whose later successful device login cannot be observed.
The existing cancellation race matrix tests a second DELETE, while the separate
completion test does not include a simultaneous polling HTTP failure.

The focused correction retains the existing two-second polling cadence only
while cancellation owns that flow. It keeps HTTP failure bodies out of terminal
success handling and preserves the same-flow completion fence. Four new cases
cover pending/committing and both response orders, then assert eventual success,
one completion notification and no replacement login POST. Independent static
review passed. Delivery: [PR #4945](https://github.com/lidge-jun/opencodex/pull/4945).

### Configured physical-send cap and the shared recovery reserve

At `src/server/responses/passthrough-dispatch.ts:697-700`, a configured one-send
total becomes zero remaining sends after the first dispatch. Its rebuild caller
passes that zero to `recoverySendAllowance` at `:904-908`. The helper at
`src/server/responses/request-send-budget.ts:151-165` can still grant the shared
final-recovery reserve. A rebuilt opaque-state, upload or reasoning-effort
request can therefore spend a send the operator explicitly declined.

The invariant is one physical send total when the provider sets `attempts=1`.
An exhausted configured ceiling cannot be supplemented by the shared reserve.
The unconfigured default path must retain its existing guarded final recovery
send. The fix tests those cases separately through the composed allowance and
also protects the original upstream response when no rebuild is allowed.
Delivery: [PR #4947](https://github.com/lidge-jun/opencodex/pull/4947).

### Denial evidence and same-ID credential replacement

Disposition: [issue #4952](https://github.com/lidge-jun/opencodex/issues/4952),
the next round's first item, explicitly excluded from this release's fix train.
The owner judged the shipped direction an improvement over the earlier repeated
flagship refusal; empty-filter restoration prevents an outage. Generation-bound
evidence and late-response races require a separately reviewed change without
release pressure. No correction for this issue is included in the release PRs.

`src/codex/observed-model-denials.ts:51-80` keys evidence by account and model,
without credential generation. Its only production account-wide clearing site,
`src/codex/model-entitlements.ts:877-884`, requires an old roster-cache entry.
The new flagship denial path explicitly works without such a roster. Real
reauthentication keeps the internal account ID, writes a new credential
generation and does not refresh the catalog when picker visibility is unchanged
(`src/codex/auth-api/login-flow.ts:350-374`).

The old denial can therefore avoid the newly entitled account for up to six
hours. A positive roster masks it temporarily but does not delete it; the
five-minute roster expiry can expose it again. Empty-filter restoration bounds
the impact, so this is not a hard account outage. A safe correction binds both
denial and success evidence to the dispatched generation and compares it with
the current credential identity, including late replies from an old generation.

## Windows finding

Corroborating all-platform run 35277467396 failed Windows 7/9 in
`tests/cli/cli-status-json.test.ts:77`. The first matrix row took 15,587 ms and
its child was killed by the 15,000 ms internal deadline. The next row took
13,074 ms; the remaining six rows took 1,518–1,741 ms for two children each.

That evidence supports a cold full-CLI status path entering the first timed
behavior assertion. It does not isolate the contribution of Bun transpilation,
Windows filesystem caching, Defender or external diagnostic probes. Version
comparison itself is bounded, synchronous logic with no I/O. The status path
also performs runtime discovery, service/registry checks, liveness and local
configuration diagnostics before formatting its result.

The selected fix moves one checked, finite cold status invocation into Windows
fixture setup. All sixteen JSON/human child assertions retain their 15-second
deadlines and original result assertions. Setup uses the existing 45-second
spawn budget, with a 25-second child deadline leaving the existing 15-second
Windows removal bound and five seconds for reap. Failed
setup remains a failure. Phase timings are emitted for hosted evidence; no
retry, global budget increase or platform skip is part of the change. A later
passing run alone does not dispose of the original failure.
Delivery: [PR #4948](https://github.com/lidge-jun/opencodex/pull/4948).

## Mechanical composition results

| Surface | Exact-tree static result |
| --- | --- |
| File-size ratchet | 9,193 tracked paths; 3,951 scanned; 51 caps; 12 exact exemptions; zero growing, missing-capped or unregistered oversized files |
| Baseline headroom | 41 caps unchanged; 10 files below cap; no cap was raised |
| Test layout | 1,343 test files, including two root guards; zero unresolved/misplaced files; both registries contain the same 1,333 entries |
| Round additions | All five new domain tests appear in both registries and resolve to their domains |
| Path collisions | No tracked-path case collision, test basename collision or registry case collision |
| Structure index | Manifest rendering matches committed INDEX; no new unclaimed top-level source area |
| Structure links | No broken current path/heading link or missing invariant binding found; size graces remain valid |
| Client rosters | Canonical backend and dashboard client lists agree on fifteen members/order |
| Lab/core | Static load-time graph traversal reaches 346/346/654/643 modules from router/lifecycle/responses-core/management roots with no Lab edge; activation and startup remain synchronous |

The primary round is 26 commits and 177 changed files from
`5061f2c956145ec5cbf76b259cf35c312afa9301` to the target, with earlier
Responses/combo dependencies inspected where relevant. Static calculations
read source and data; they did not invoke repository checkers or tests.

Eight seed-resolved domain tests were already absent from both explicit
registries at the round base. That inherited conformance debt is distinguished
from this round's five correctly registered additions. An old ownership-manifest
capacity concern was also falsified as an attribution to this round and excluded
from the release-regression set. The stale test title saying fourteen clients
does not change its correct fifteen-member assertion.

## Named hand-resolved conflicts

The five #4526 documents preserve 21 additive lines with no deletion against
`3dddc1ec2b`: `adapters/registry.md`, `data-planes/inbound-compat.md`,
`runtime.md`, `transports/byte-accounting.md` and `transports/inventory.md`.
All eight declared `src/adapters/` owners received the Unicode cross-link.
The heading exists at `structure/transports/byte-accounting.md:138`.
The inventory sentence is at `:202`, before the OAuth-headroom heading at
`:204`. The schema path exists, and the copy-on-write implementation preserves
literal/name-bag handling, preserved subtrees, array ancestry, unchanged sibling
identity and input immutability by static inspection.

For #4925, the removed constant has zero executable references or imports in
`passthrough-dispatch.ts`. The six former sites use `transientSendAttempts()`
at lines 840, 905, 1069, 1170, 1249 and 1297. One historical comment at line 680
still names the constant. The import conflict resolution is correct; the
separate reserve composition defect is described above.

## Documentation corrections

The mechanical structure check cannot establish that prose explains every
changed behavior. The audit identified missing descriptions of canonical
Antigravity save-time fake-IP admission, API list-price breakdown coverage,
OpenCode Go estimates, CCA billing-prefix sanitation and static asset caching.
The audit branch supplies narrow source-grounded corrections. The send-cap
fix owns its transient-policy documentation. Broad owner-update omissions with
no identified contradictory contract remain process debt rather than invented
runtime findings.

## Upstream compatibility evidence

The requested Codex research corpus contains a local OpenAI Codex clone at
snapshot `095da4b7e8b70b01afb5c6131ef926dcb8c0d85d` dated 2026-09-08.
It was not treated as current. Live PR APIs and source were inspected at
`fa8cf449858c7fffc83d9e3604894852344962a1`, dated 2026-09-17T21:25:55Z.
Aside's signed-in browser independently exposed the current closed-PR list.

- [#46300](https://github.com/openai/codex/pull/46300) keeps refresh JSON and
  authorization-code form exchange distinct while centralizing safe OAuth diagnostics.
- [#46281](https://github.com/openai/codex/pull/46281) scopes workspace routing
  by auth generation, account and destination; an owner change invalidates reuse.
- [#46230](https://github.com/openai/codex/pull/46230) preserves explicit Flex
  independently of catalog advertisement; request-setting changes defeat incremental reuse.
- [#46297](https://github.com/openai/codex/pull/46297) supplies catalog-owned
  descriptions for all six V2 collaboration tools.
- [#46306](https://github.com/openai/codex/pull/46306) preserves `bio_policy`
  as a non-retryable error across Responses transports.

The [official Responses contract](https://developers.openai.com/api/reference/cli/resources/beta/subresources/responses)
distinguishes accepted steering ownership from successor creation, the commit
point. Pending tool results use saved outputs and one explicit same-parent,
same-lane continuation. A lost acknowledgement is unknown, not permission to
replay accepted input. The reviewed implementation keeps those ownership and
fail-closed replay distinctions. A candidate finding about failed/incomplete
parent continuations was withdrawn after falsification: ordinary incomplete
continuations may be valid, and no concrete unauthorized replay or user failure
was established. No steering change was made.

## Verification boundary and delivery

No local suite, focused test, typecheck, build, install or proxy binary was run.
Several extra Sol review attempts failed with provider 429 errors; completed
review evidence was retained and available reviewers were reused. A failed
dispatch is not counted as coverage. Exact hosted run/job outcomes and the
integration sequence are recorded in `090_composition_ci.md`.
