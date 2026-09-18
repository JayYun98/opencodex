# macOS control workload disposition

Recommendation: keep the control unsharded and size its outer job budget from
complete-run evidence through an explicit maintainer decision. Do not turn it
into another copy of the existing two-shard platform lane. No workflow or budget
change is made by this audit.

## Observed workload

Run 35277467396, job 105391505883, source head
317b0858f552914a52a83979ebdc1bafdfb3865c (documentation-only over 3dddc1ec2b):

| Measurement | Value |
| --- | --- |
| Test invocation | 21:35:34.626Z to 22:05:26.822Z on 2026-09-17 |
| Test-step wall time | 29m52.196s |
| Completed test results | 18,576 |
| Printed test failures | 0 |
| Sum of bracketed test durations | 23m02.730s |
| Wall time outside those durations | 6m49.466s |
| Job lifetime from GitHub job metadata | 21:35:13Z to 22:05:33Z, 30m20s including termination/cleanup |
| Outcome | Cancelled at the outer budget, while still progressing |

The unitemized interval can include imports/evaluation, hooks, isolate
transitions, teardown and logging. Its allocation is not established by this
log. The job reached another test file immediately before cancellation; there
is no long silent interval matching the shard hang in `100_macos_cancellation_rca.md`.
Zero failures in an executed prefix is not a pass for unexecuted tests.

## Why preserve the control

`.github/workflows/ci.yml:641-648` defines a full suite in one pool as the
control for sharded verification. Its command at `:706` is one invocation of
`bun test --isolate --timeout 60000 tests`, with first-occurrence failure rather
than reruns. Bun's [isolation documentation](https://github.com/oven-sh/bun/blob/main/docs/test/parallel.mdx)
states that file isolation replaces globals and module registries inside the
same process, sharing transpiled-source and bytecode caches. Thus it retains
long-range process pressure and ordering that shard boundaries reset.

| Option | Benefit | Cost to verification |
| --- | --- | --- |
| Shard the control | Less wall time per job | Removes the independent whole-process observation and duplicates the platform shards |
| Resize the outer job budget | Preserves the control's purpose | More runner occupancy and a later outer stop for a true process hang |

The latter preserves the intended evidence. Existing per-test limits, crash
failure behavior, all tests and the one-invocation shape should remain intact.
The 30-minute budget is demonstrably insufficient for this observed workload.
The incomplete run does not establish a sufficient replacement: 35, 40 or 45
minutes cannot be called validated from this prefix, nor can file counts be
treated as uniform execution cost.

The maintainer should use completed same-control historical runs where available,
or explicitly authorize a bounded workload-measurement run, then select the
permanent outer bound from completion duration and measured variation. That is
a CI-policy decision requiring the repository's security review, not a timeout
adjustment to slip into these release fixes.

## Authorized bounded measurement

The release owner explicitly authorized one measurement from current dev
61ee64747bedc5fafbeb5fc811898ea4db4ec738, after #4948 landed.
Throwaway branch: `codex/lane-g-2590-control-measurement`.
Measurement head: 118e82d514bfcba81c8a357b8d909b540160b97e.
Run: [35281782986](https://github.com/lidge-jun/opencodex/actions/runs/35281782986),
dispatched with `lane=macos-control`.

Its entire diff is one value: the macos-control job's outer timeout changes
from 30 to 60 minutes. Commands, tests, per-test limits, isolation, actions,
permissions and other jobs are unchanged. The branch has no PR and must never
be merged. This is a measurement, not a fix; 60 minutes is not proposed as the
repository's permanent budget.

The requested result is the duration of a complete zero-failure control run.
If the run fails, hangs or reaches the measurement bound, that result cannot
be presented as a clean completion time. Once complete evidence exists, the
recommendation will state measured duration plus explicit headroom; the owner
retains the permanent workflow decision.

## Terminal measurement result: failed, not a clean sizing baseline

The authorized measurement's control job
[105405217666](https://github.com/lidge-jun/opencodex/actions/runs/35281782986/job/105405217666)
completed with **failure**, exiting 1 before the 60-minute outer ceiling.
The exact head remains 118e82d514bfcba81c8a357b8d909b540160b97e, based on
61ee64747bedc5fafbeb5fc811898ea4db4ec738. All 42,368 lines of the downloaded
job log were scanned, including every distinct failure and the final summary.

| Measurement | Observed value |
| --- | --- |
| Job start/end | 2026-09-17 23:12:38Z to 2026-09-18 00:04:07Z |
| Job duration | 51m29s |
| Test-step start/end | 2026-09-17 23:13:17Z to 2026-09-18 00:03:56Z |
| Test-step duration | 50m39s |
| Bun-reported suite duration | 3034.18s, or 50m34.18s |
| Final suite counts | 26,475 pass / 46 skip / 5 fail; 26,526 tests across 1,343 files |
| Assertions | 383,039 |
| Outcome | Full suite summary emitted; Test exited 1; control job failed |

The five failures are distinct; repeated failure-summary lines are not counted
twice:

| Test | Evidence |
| --- | --- |
| GitHub Actions hardening: bounded jobs and immutable action references | tests/ci-workflows/ci-workflows.test.ts:121 expects control timeout 30, received 60; job log line 25769 |
| Web-search retry wait longer than the stall budget | 6,233.05 ms elapsed, explicit 5,000 ms test timeout; log line 33960 |
| OpenAI Chat image that cannot be dropped still counts toward budget | 60,323.51 ms elapsed, 60,000 ms test timeout; log line 42020 |
| OpenAI Chat imageTierBias reaches the normalizer | 91,516.75 ms elapsed, 60,000 ms test timeout; log line 42025 |
| OpenAI provider-option Pool/Direct/API ownership integration spine | 31,801.03 ms elapsed, 30,000 ms test timeout; log line 42041 |

The first failure is measurement-induced, not a newly established product
defect: changing only the job timeout conflicts with the existing exact-value
assertion. That conflict was missed during measurement preflight. The other
four are observed timeouts; this inspection does not establish their root causes.
Even setting the measurement-induced failure aside would not make this run green.

Therefore the requested **zero-failure completion duration was not obtained**.
The 50m39s step duration is a failed-run observation, not a validated baseline
for duration-plus-headroom sizing. No permanent budget or headroom is recommended
from this run. The single measurement is not retried, its assertions are not
changed, and the throwaway branch remains unmerged with no PR. The 60-minute
ceiling remains measurement-only. The follow-up reports these results and stops.
