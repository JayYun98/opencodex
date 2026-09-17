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

Source-level cause and historical comparison remain pending. No fix or
resolution is claimed by this investigation entry.
