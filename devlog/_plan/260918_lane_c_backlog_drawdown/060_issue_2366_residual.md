# #2366 — residual scope, and a ratchet blocker that decides the shape

## What `dev` already has, and what is genuinely new

The instruction was to review only the residual timeline and failure classification and not
to rebuild diagnostic fields already on `dev`. `src/server/request-log.ts` already carries
`terminalStatus`, `terminalHttpStatus`, the structured terminal code preserved across status
mapping, `transportPhase`, `terminalSource`, a `failureDiagnostics` block gated on
`status >= 400 || terminalStatus !== "completed"`, and a status-to-code classifier.

#2366 does not re-add any of them. What it actually contributes is three things:

1. `StreamTimeline` — first-write-wins relative-millisecond milestones, recorded both per
   request and per attempt.
2. `failureSide` and `failureStage` — two attribution axes beside the existing
   `transportPhase` / `terminalSource`.
3. `normalizeStreamDiagnostics` — one normalizer replacing the two per-field guards
   `isKnownTransportPhase` and `isKnownTerminalSource`, applied to entries and to each
   attempt.

So the residual is real and reasonably scoped. It is not a narrow pull request — six source
files — but it is not duplicated work either.

## Blocker: the test file is exactly at its ratchet cap

`tests/usage/request-log.test.ts` is **2075 lines and its baseline cap is 2075**. #2366 adds
`+255/-1` to it. A baselined file may not grow by a single line, and `updateBaseline` only
lowers caps, so no tooling can clear this. The pull request cannot land in its current shape
regardless of whether the design is accepted.

The resolution is mechanical and is the direction the host asked for — shrink the file
rather than raise the cap. Move the new timeline and attribution cases into a sibling test
file with their bodies unchanged. That sibling then needs byte-identical entries in both
`scripts/test-layout/layout.json` `explicit` and `tests/fixtures/test-layout-expected.json`,
or `tests/test-layout-tooling.test.ts` names the missing one.

`tests/usage/usage-log.test.ts` (+268) is not baselined, so it is unaffected.

## Two review findings to settle before it is worth running CI on

**The retained-entry clone became unconditional.** The current code keeps the retained entry
as the *same object* as the live entry when nothing changed, and its `delete` calls are
guarded by `retained !== entry` so they can never mutate the caller's object. The rewrite
always spreads into a fresh object and then deletes unconditionally. That is safe from the
mutation angle and arguably more correct — a retained snapshot should not alias a live entry
that is still being written — but it is a behaviour change, not a refactor: every logged
request now allocates a clone, and the retained copy no longer tracks later mutations of the
live entry. It should be stated as intended rather than arriving as a side effect of adding
fields.

**The timeline reads a wall clock and clamps backwards steps to zero.**
`noteStreamTimelineEvent` derives each milestone from `Date.now()` minus an origin, through
`Math.max(0, now - origin)`. If the host clock steps backwards mid-request — an NTP
correction is the ordinary case — the clamp reports `0` for a milestone that was not
measured at zero. For a diagnostics timeline whose whole purpose is attribution, that is an
unobserved value rendered as a real one, which is the failure class this round excludes. A
monotonic source is the correct fix; if the wall clock has to stay, the clamp should record
that the measurement was unusable rather than flatten it to zero.

A third item to check once the file is split: the per-attempt origin falls back to the
request origin when `activeAttemptStartedAt` is unset, which would label a request-relative
measurement as attempt-relative. Whether that fallback is reachable was not determined.
