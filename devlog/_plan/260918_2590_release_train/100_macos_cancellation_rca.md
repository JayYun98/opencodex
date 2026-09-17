# macOS cancellation root-cause investigation

This is a first-class investigation, separate from the two functional
composition fixes and the Windows cold-setup correction. The release owner
requires a named cause for the silent shard hang before promotion.

## Proven current signature

Exact source: a0f611d4aceb9476d44268e43722273b7b211846.
Run: [35277719805](https://github.com/lidge-jun/opencodex/actions/runs/35277719805).
Job: [macos 1/2, 105392401547](https://github.com/lidge-jun/opencodex/actions/runs/35277719805/job/105392401547).

The job began at 21:48:24Z on 2026-09-17. Its Test step began at 21:48:54Z.
The final test result at 21:52:22.117553Z was PASS for the real injection
lock-contention case in tests/codex-integration/codex-inject-write-lock.test.ts:
"a held lock makes real injection report busy and write nothing".
There was no subsequent test output until cancellation at 22:08:37.498629Z.
Cleanup terminated the remaining Bun and tee processes.

That 16-minute-15-second silent interval is a hung execution. It is not a
capacity cancellation before work began and not the continuously progressing
macOS control exceeding its total-work budget. The passing line localizes the
boundary, but does not by itself identify whether the blockage is teardown,
the next test, or a runtime/process interaction.

## Investigation lanes

- Production coordinator/lock implementation and blocking operations.
- Independent fixture/next-case, child-pipe and teardown lifetime review.
- Historical cancellation logs from the 2.58.0 full dispatch 35247708168 and
  every main-push attempt at 6fe4cd0de85d63b8cdd0c3552e5e8883c0a029ee.
- Separate macOS-control purpose and workload disposition.

All work is source reasoning and hosted log inspection. No local test,
typecheck, build, installation or proxy execution is permitted. No rerun,
wider timeout, test skip or CI-policy change may hide the failure.

## Earlier release characterization

The 2.58.0 release record currently calls its macOS non-green entries capacity
cancellations. That characterization is not accepted as evidence. The historical
jobs must be split into never-started capacity loss, continuous work reaching
the job bound, and silent hung execution. A matching old hang requires an
explicit correction to that record, preserving the original run and release
facts while withdrawing the unsupported benign explanation.

## Historical comparison completed

The 2.58.0 characterization is withdrawn in its release record. Run 35247708168
attempt 2 shard 2 emitted 2,514 passing results before 17m32.932s of silence.
Main push run 35254182109 attempt 1 shard 2 emitted 2,512 passing results before
17m19.098s of silence. Both had completed setup and were executing tests; both
stopped after catalog-picker cases. The current #4945 shard-2 cancellation
stops at the same full-ordering case and remains silent for 17m33s.

The two historical control cancellations were different: they were still
progressing near cancellation, and each had already logged a failure. Attempt 1
failed storage-trash restore responsiveness with ECONNRESET. Attempt 2 failed
retained-sync/convergence, expecting committed and receiving stale. A later
successful main attempt does not explain either failure or the shard hangs.

## Source investigation and remaining cause boundary

The held-lock case joins the holder's exit and both pipes before PASS. Its
contender also returns before the assertion. The next source-ordered case can
enter synchronous subprocess execution; Bun's JavaScript test timer cannot
observe a native synchronous call that does not return. An unrelated catalog
file's following setup also enters synchronous runtime-version probing.

The production coordinator uses bounded acquisition, zero SQLite busy timeout,
and transaction close in finally. Unsharded control completed the same lock
adoption cases in 0.82s and 1.90s. These facts weigh against a deterministic
standalone lock deadlock, but do not disprove a state/order-dependent runtime
failure or one-off blocking syscall.

Bun isolate/shard scheduling, teardown, and synchronous subprocess liveness are
plausible hypotheses. No process sample, active handle/FD list, or native stack
was captured during the stalls, so the logs cannot establish which one caused
them. No production lock patch is justified by this evidence. The negative
result and saved logs were handed to the dedicated macOS investigation through
the release host. A hypothesis is not renamed as a cause here.
