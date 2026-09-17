# 2.59.0 hosted verification ledger

Audited, held candidate: `a0f611d4aceb9476d44268e43722273b7b211846`.
The release host will freeze a new SHA after the three focused fixes land.
The final release table must refer to that new SHA and its fresh full dispatch.

## Evidence identities

| Run | Event | Exact head | Role |
| --- | --- | --- | --- |
| [35277719805](https://github.com/lidge-jun/opencodex/actions/runs/35277719805) | workflow_dispatch, lane=all | a0f611d4aceb9476d44268e43722273b7b211846 | Primary evidence for the audited, held candidate; dispatched by release host |
| [35277470041](https://github.com/lidge-jun/opencodex/actions/runs/35277470041) | push | a0f611d4aceb9476d44268e43722273b7b211846 | Ordinary integration coverage |
| [35277467396](https://github.com/lidge-jun/opencodex/actions/runs/35277467396) | workflow_dispatch, lane=all | 317b0858f552914a52a83979ebdc1bafdfb3865c | Corroboration only; one audit-doc commit over the older 3dddc1ec2b source tree |
| [35276608167](https://github.com/lidge-jun/opencodex/actions/runs/35276608167) | push | 3dddc1ec2b1315311ca240ad2a3dbd10222e2c67 | Superseded and cancelled; not complete release evidence |

## Completed table for the held candidate

Run 35277719805 completed with conclusion **failure** at exact
a0f611d4aceb9476d44268e43722273b7b211846.

| Requested proof | Final result |
| --- | --- |
| Linux test 1/4, 2/4, 3/4, 4/4 | All four success |
| Windows 1/9, 2/9, 3/9, 4/9, 5/9, 6/9, 7/9, 8/9, 9/9 | All nine success |
| macOS shard 1/2 | Cancelled after a long silent interval; not passed |
| macOS shard 2/2 | Success |
| macOS unsharded control | Cancelled at the 30-minute bound while still progressing; not passed |
| Keyring: Ubuntu, Windows, macOS | All success |
| npm-global: Ubuntu, Windows, macOS | All success |
| Gates, API usage, storage policy, Docker, docs build | All success |
| Changes and Windows runner selection | Both success |
| Aggregate ci | Failure |

The exact-candidate control completed 19,098 passing test results and printed
no failing assertion before cancellation. Its last PASS was at 22:12:39.127915Z,
about two seconds before cancellation at 22:12:41.170363Z, which supports the
continuous-work classification. Its reported test durations total 1,391,363 ms.
The separate silent shard hang is not explained by that workload result.

The final release table will replace neither these facts nor their disposition.
It must name the post-fix merged SHA and a fresh full workflow run selected by
the release host. That SHA has not yet been frozen in this audit record.

## The coverage gap

The normal push workflow omits the entire Windows suite and the unsharded
macOS control. Their skipped job results are intentional workflow behavior,
not evidence that those tests passed. A green push aggregate is therefore
insufficient for an all-platform release claim.

| Surface | Ordinary runtime-changing push | Full lane=all dispatch |
| --- | --- | --- |
| Linux suite | test 1/4, 2/4, 3/4, 4/4 | All four shards |
| macOS sharded suite | macos 1/2, 2/2 | Both shards |
| macOS unsharded control | Skipped | macos control |
| Windows suite | Skipped; a single unexpanded matrix job is visible | windows 1/9 through 9/9 |
| Keyring smoke | Ubuntu, macOS, Windows | Same three platforms |
| npm-global smoke | Ubuntu, macOS, Windows | Same three platforms |
| Gates | Typecheck, dashboard checks/build, privacy and helper checks | Same gates |
| Other jobs | Storage, API usage, Docker; docs build depends on changes | All requested jobs, including docs build |

Source: `.github/workflows/ci.yml:281`, `:493`, `:641-648`, `:737-783`,
`:874`, `:989` and `:1089-1201`. The aggregate distinguishes requested jobs
from skipped jobs and counts all nine Windows legs on a full dispatch.
Windows smoke successes do not substitute for the Windows test shards.

The smallest existing workflow mode that executes all nine Windows shards is
`lane=all`; `lane=macos-control` does not. No new workflow, retries, wider
timeouts or altered platform conditions are needed. Dispatch the workflow at
the candidate ref and inspect the returned run's `head_sha` before accepting it.
The host did this for run 35277719805, so an additional dispatch is unnecessary.
That statement applies to the audited source only. Once fixes are integrated,
the newly frozen merged SHA needs its own full dispatch.

## Focused fix verification

| Fix | PR | Verification boundary |
| --- | --- | --- |
| Reauth polling/cancellation composition | [#4945](https://github.com/lidge-jun/opencodex/pull/4945) | Exact-head PR CI, including dashboard tests and both macOS shards |
| Configured send cap/recovery reserve composition | [#4947](https://github.com/lidge-jun/opencodex/pull/4947) | Exact-head PR CI, paired budget tests and one-send original-response regression |
| Cold status fixture setup | [#4948](https://github.com/lidge-jun/opencodex/pull/4948) | PR CI plus [full dispatch 35279223062](https://github.com/lidge-jun/opencodex/actions/runs/35279223062) at cca06b1693fc4f7d4711bb920ea5f5417655edf5 |

The host merged #4948 as 61ee64747bedc5fafbeb5fc811898ea4db4ec738 under
the explicit scoped integration exception recorded on that PR. This is not a
claim that its unrelated macOS failure disappeared.

At the audit handoff, #4945 remains at fd2f1cd03d6d99f2d27280ee12aed9a40a4b572e:
all requested jobs except macOS shard 2 succeeded, and that shard was cancelled
after the silent catalog-runner interval documented in the RCA. #4947 remains at
50ecf0627347343a6eaa0c9f55aee25a6a906b13: Linux, gates and its new send-cap
assertions passed, but macOS shard 2 reproduced the separately assigned combo
connect-cancellation hook timeout at 30,050.44 ms (job 105398860800;
12,810 pass / 12 skip / 1 fail). Its shard 1 result was still pending at handoff.
Neither PR is marked ready under an assertion that its exact head is fully green.
The host owns the remaining macOS investigation and integration disposition.

The first #4947 run failed only its new absent-recovery-label expectation:
the existing request-attempt initializer creates an empty array, not an absent
field. The one-send and original-400-body assertions passed. The expectation
was corrected to require an empty array at head 50ecf0627; the changed head
requires fresh CI. This is a source-grounded test correction, not a rerun or
weakening of the send-cap assertions.

## Windows baseline comparison

| Evidence | First row | Second row | Remaining two-child rows | Disposition |
| --- | --- | --- | --- | --- |
| 35277467396 / job 105391449887 | 15,587 ms, killed | 13,074 ms | 1,518–1,741 ms | Real cold-path setup failure |
| 35277719805 / job 105392362979 | 2,048 ms, pass | 1,391 ms | 1,342–1,385 ms | Warm-path corroboration; does not erase the failure |

The status fixture implicitly depended on whether the surrounding shard work
had already paid cold CLI/diagnostic setup. The exact share attributable to
transpilation, filesystem/Defender behavior or external diagnostics is not
established. The correction makes one cold setup explicit and bounded before
all sixteen unchanged 15-second projection assertions. New-code hosted timing
evidence must show this setup and the individual measured children separately.

Changed-code Windows 7/9 job 105397453194 in run 35279223062 completed
successfully at exact head cca06b1693fc4f7d4711bb920ea5f5417655edf5.
Its setup took 1,755 ms; all sixteen measured children took 583–933 ms and
every original row passed. This verifies the explicit setup/measurement path;
it does not claim that the original 15.6-second cold environment was reproduced.

All nine Windows shards and all four Linux shards subsequently completed
successfully on that exact #4948 head, with gates green. Its separate PR run
35279139497 reports a macOS shard-2 failure in the pre-existing combo
connect-cancellation teardown hook (job 105396939652, 30,066.66 ms;
12,807 pass / 12 skip / 1 fail). The branch changes only the CLI status fixture.
The release owner assigned that hook failure to a separate investigation and
authorized evaluating #4948 on its Windows/Linux proof rather than hiding or
fixing the unrelated hang inside that PR. Pending macOS jobs remain pending;
this is a scoped integration exception, not an all-platform green claim.

The earlier corroborating run's macOS control, job 105391505883, was cancelled
at its 30-minute bound. The captured log contains 18,576 completed tests and
zero failing tests before cancellation, with reported test durations totaling
1,382,730 ms. It continued progressing through tests until cancellation, so
the evidence shows incomplete total-work coverage rather than a demonstrated
single stuck assertion. Its overall CI result is failure. No bound, isolation
mode, test or platform was changed to conceal this result.

The exact held candidate's macOS shard 1/2, job 105392401547 in run
35277719805, was also cancelled after 20 minutes. Unlike the control's
continuous progress, its last completed test was the real injection lock-contention
case at 21:52:22Z, followed by silence until cancellation at 22:08:37Z.
The cause of that silent interval requires separate root-cause analysis;
the absence of a printed failing assertion does not establish success.

The generation-bound denial issue is explicitly deferred to
[#4952](https://github.com/lidge-jun/opencodex/issues/4952) as the next round's
first item. The owner accepted its bounded avoidance behavior because
empty-filter restoration prevents an outage and the current flagship routing
improves the earlier repeated-refusal behavior. Its unpublished local patch is
not part of this fix train.

## Browser and local-verification boundary

Aside's existing signed-in GitHub session exposed the older run's gates job
and its typecheck, dashboard tests/build and privacy step list. Opening the same
[job URL](https://github.com/lidge-jun/opencodex/actions/runs/35276608167/job/105388996334)
without that session returned "Sign in to view logs". This confirms why a real
authenticated browser was needed for that observation. Exact run identity and
final outcomes are read from the GitHub API, not inferred from a page title.

No local suite, focused test, typecheck, build, install or proxy binary was run.
Static source/data inspection is not represented as executable verification.

## Current outcome

The audit candidate is held for the three focused fixes. No all-platform release
approval is recorded until they are integrated and every requested job, including
all nine Windows shards, succeeds on the host's newly frozen merged SHA. Final
results and the audit verdict will replace this pending statement after that
hosted evidence is available.

The source audit and historical correction are complete within their stated
limits. The dedicated macOS lane owns the unresolved hang cause. One narrowly
authorized control-duration measurement is pending at run 35281782986; see
`110_macos_control_disposition.md`. Its terminal result will be recorded as a
follow-up, without retrying or treating a measurement timeout change as a fix.
