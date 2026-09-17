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
