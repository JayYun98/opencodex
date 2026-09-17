# No fork pull request in this round carried exact-head test evidence

Reading check-runs at the exact head of every candidate returned the same four names and
nothing else: `resolve-pr`, `label`, `hygiene`, `enforce-target`. No `ci`, no `test 1/4`,
no `gates`, no platform legs. For comparison, the head of maintainer PR #4889
(`5504923707`) carries the full matrix — `ci`, `test 1/4` through `4/4`, `macos 1/2` and
`2/2`, `gates`, `storage policy`, `api usage`, `docker smoke`, `keyring` on three
platforms, `npm-global` on three platforms.

The cause is not workflow configuration. `.github/workflows/ci.yml` triggers on
`pull_request: {}` with no base filter, deliberately so, and its header explains that a
base-branch allowlist once silently excluded stacked children. The runs exist; they sit in
`action_required`, waiting on maintainer approval for an outside contributor. At the time
of writing the repository holds on the order of nine hundred such runs across all heads.

This is the round's largest single lever on evidence quality. A verdict of "narrow, tested,
contract-preserving" on a fork pull request is a source reading until its head has run the
suite, and this lane cannot start those runs.

## Requested, in priority order

Approval is needed only for the run at each **current** head; approving an older SHA cancels
the newer run through the branch concurrency group.

| PR | Head | Why it is worth a slot |
| --- | --- | --- |
| #4753 | `e5f4b6ca99` | Self-contained: one new module, a three-line wiring change in `src/server/index.ts`, 377 test lines, plus doc and `structure/` updates. Highest evidence-per-slot. |
| #4751 | `eef5364ff3` | Largest behavioural surface of the narrow set and the one whose author evidence is explicitly not a Bun result. Needs repository CI most. |
| #4898 | `719510669d` | Two files, additive price overlays; fast confirmation. |
| #4623 | `b61811020a` | Devlog text only; should pass in minutes and removes a pull request from the count. |
| #4913 | `a5f76582e8` | **Approval did not take.** The `Cross-platform CI` run at this head is still `action_required`; only `React Doctor`, `hygiene`, `label` and `enforce-target` completed. Worth a second attempt. |

Already running after the host's approval: #4877 (`795a416b5b`) and #4900 (`5702c8e4f9`).

## Heads with no pending run at all

#4159 (`9be8f1a229`) and #4823 (`867c8868f9`) have no queued `Cross-platform CI` run at
their current head, so approval alone will not produce evidence for them. They need a push
or a re-run before the question can even be asked.
