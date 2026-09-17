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

## Approval alone is not enough: the merge ref has to be current too

A second gate sits behind the first. `pull_request` CI checks out the **merge ref**, and
that merge commit is computed from the base at the moment the run was created and then
pinned to it. The `release version line` test reads the checked-out git tags and compares
them with the in-tree version, so every run whose merge ref predates the `v2.58.0` tag fails
on that one case regardless of what the pull request changes. A re-run cannot clear it,
because it reuses the pinned merge commit; only a push recomputes the merge ref against the
current `dev`.

Every candidate in this lane is affected. `package.json` at each current head:

| PR | Head | In-tree version |
| --- | --- | --- |
| #4751 | `eef5364ff3` | 2.58.0 |
| #4753 | `e5f4b6ca99` | 2.58.0 |
| #4898 | `719510669d` | 2.58.0 |
| #4623 | `b61811020a` | 2.58.0 |
| #4159 | `9be8f1a229` | 2.58.0 |
| #4805 | `b67c24076c` | 2.58.0 |
| #4649 | `53d92db2aa` | 2.58.0 |
| #4788 | `fce03915e0` | 2.57.0 |
| #4802 | `a356f7397e` | 2.57.0 |
| #4863 | `5745fc79bf` | 2.58.0 |
| #4823 | `867c8868f9` | 2.57.0 |

So a `release version line` failure on any of these is not a finding about the pull request,
and this lane will report it as "merge ref needs refreshing" rather than as a defect.

## Refresh and approval are one operation, not two

Refreshing a fork head creates a **new** workflow run that is itself `action_required`.
Confirmed on both heads the host refreshed: `Cross-platform CI` at #4877 `bdd71e4182` and
at #4913 `77f21a4538` are both sitting in `action_required`, with only `resolve-pr`,
`label`, `hygiene` and `enforce-target` completed. Batching should therefore pair each
push with an approval, or the refresh buys nothing.

## Requested, in priority order

Each needs a merge-ref refresh **and** an approval on the resulting run.

| PR | Head | Why it is worth a slot |
| --- | --- | --- |
| #4753 | `e5f4b6ca99` | Self-contained: one new module, a three-line wiring change in `src/server/index.ts`, 377 test lines, plus doc and `structure/` updates. Highest evidence-per-slot. |
| #4623 | `b61811020a` | Devlog text only; should pass in minutes and removes a pull request from the count. |
| #4898 | `719510669d` | Two files, additive price overlays; fast confirmation. |
| #4751 | `eef5364ff3` | Largest behavioural surface of the narrow set, and the one whose author evidence is explicitly not a Bun result. Needs repository CI most, so it is worth a slot only once the cheaper three have cleared. |

#4913 and #4877 are already refreshed and only need the approval.
