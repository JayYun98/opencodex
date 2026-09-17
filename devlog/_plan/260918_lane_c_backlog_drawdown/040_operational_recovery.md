# #4897 — the wedge is already fixed on a released version

The reporter's root-cause analysis names an interrupted stop leaving an orphaned
`pending-teardown-<nonce>.json`. That is the trigger, but it is not what made the state
permanent, and it is not what produced six receipts.

## What the recovery loop already does

An abandoned receipt is not meant to wedge anything. `handleStop` reads every inherited
receipt and, for one recorded with `endpointSource: "exact"`, probes that exact endpoint
through `abandonedTeardownIsSafeToFinish` (`src/cli/index.ts:889`). A `"dead"` verdict puts
the nonce in `recoveredNonces`, the restore runs, and every recovered nonce is cleared
alongside this run's own. The reporter's sample receipt is `endpointSource: "exact"`, and
they report no proxy running, so this path should have discharged all six.

It did not, because of the branch immediately after: `restore.historyDeferred`. When the
Codex history preflight refused, nothing was restored, so nothing could be discharged and
every receipt was deliberately preserved — including the new one that `ocx stop` had just
claimed. Before #4896 that refusal fired on the mere presence of a `history_mode` column,
which every current Codex build has, so it was permanent rather than occasional.

That is the accumulation mechanism. Each `ocx update` runs `ocx stop`, which claims a
receipt, cannot discharge it, and leaves it behind. Six update attempts, six receipts. The
reporter's count is the signature of this loop, not of six separate interruptions.

## Why it is fixed

#4896 (`dfa02fe96a`) makes `history_paginated_requires_native_writer` a degraded restore
rather than a refusal: the config half is written, the relabel stands down, and the outcome
is reported as `artifacts.config.state: "partial"` with `historyPreflightRefusal` unset. The
comment now in `restoreSharedClientStateAfterStop` states the consequence directly — a
degraded restore "cannot enter this branch: its config obligation was discharged and the
stop receipt must be released rather than preserved."

`dfa02fe96a` is an ancestor of `v2.58.0`, and not of `v2.57.0`. The reporter was updating
2.56.0 → 2.57.0, so their run predates the fix on both sides.

## What actually remains

Both of the reporter's suggested fixes need qualification before either becomes work.

Their first suggestion — clear a receipt whose `ownerPid` is dead — contradicts the
receipt's design and should not be implemented as stated. The type comment is explicit that
recovery is decided by endpoint liveness, not by the owner: a dead owner does not prove the
proxy is down, and a Task Scheduler wrapper can respawn one after its parent dies. The
existing loop already asks the right question. Widening the launcher's
`hasPendingTeardownIn` gate to skip dead-owner receipts would let `ocx update` install over
a teardown that never ran, which is the exact outcome the receipt exists to prevent, and it
would also wave through quarantined receipts that `isAnyTeardownObligationFileName`
deliberately counts.

Their second suggestion — retract an uncommitted claim if the process dies before the stop
completes — is a real residual, but only for a claim made before any deferral was requested.
Once the proxy has been asked for a deferred teardown the obligation is genuine and must
survive the parent's death; that is the whole reason the receipt is written first. A blanket
`finally` retract would drop real obligations.

Note also that `tests/providers/xai/grok-lifecycle.test.ts` is a source oracle over both
sites: it asserts the launcher contains the literal
`hasPendingTeardownIn(readdirSync, configDir())` and that the gate block contains no
`clearPendingTeardown`. Any change here moves that test too.

**Recommendation:** ask the reporter to retest on 2.58.0 or later. Close as fixed by #4896
if confirmed, or narrow it to the pre-deferral claim-retraction residual, which is a
different and much smaller defect than the one filed.
