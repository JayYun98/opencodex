# Lane F — mid-numbered open PR dispositions

Round baseline: `origin/dev` = `4f8656cc0d8fb354dfd7ac427be4049929460638` (2.59.0),
69 open issues and 84 open pull requests at intake. The round target is fewer
than 50 of each, but the target is never the justification for a disposition.

## What this lane produces

A disposition per assigned pull request, with evidence. Nothing is closed,
merged, rebased, or relabeled here; the host executes every mutation. Review
comments, when left, are English and factual.

## Assigned set (35)

`#4177`, `#4183`, `#4193`, `#4222`, `#4225`, `#4228`, `#4259`, `#4265`,
`#4309`, `#4394`, `#4523`, `#4526`, `#4560`, `#4567`, `#4572`, `#4593`,
`#4594`, `#4597`, `#4647`, `#4649`, `#4663`, `#4728`, `#4731`, `#4732`,
`#4734`, `#4740`, `#4781`, `#4793`, `#4795`, `#4803`, `#4804`, `#4805`,
`#4823`, `#4872`, `#4910`.

Out of scope because another lane holds them: `#4676`, `#4723`, `#4733`,
`#4877`, `#4900`, `#4913`, `#4924` (lane B); `#4751`, `#4898`, `#4159`,
`#2366` (lane C); `#3952`, `#4783` (lane D). `#4800` stays with lane C's
judgment that it is not an easy merge candidate.

## Disposition vocabulary

| Disposition | Bar |
| --- | --- |
| `MERGE` | Narrow, no contract change, regression test present, still correct at the current head. Name the merge-ref refresh if one is needed. |
| `SUPERSEDED` | `dev` already closed the same problem. Give the landing SHA and confirm nothing is left over. `git apply --reverse --check` passing is strong evidence; a different approach can still supersede, but then state what remains. |
| `NOT_APPLICABLE` | The premise is gone. Point at the SHA or file that removed it. |
| `STALE_BEYOND_REVIVAL` | Technically valid, but the subsystem moved enough that rebasing is author work and review is impossible. Cite the PR numbers or SHAs that moved it. |
| `PARK` | Live and sound, but outside this bug/provider line. One sentence on why. |
| `BLOCKED_ON_AUTHOR` | Something only the author can do remains: rebase, screenshot, evidence, scope reduction. Say exactly what. |

Weak evidence means `PARK` or `BLOCKED_ON_AUTHOR`, reported as such. The host
does not execute an unjustified close.

## Evidence rules

1. Judge the **current head**, never the PR description. Several authors in this
   round pushed follow-ups that already closed the review findings quoted in
   their own descriptions.
2. Verification is static reasoning plus hosted CI at the exact head. No local
   `bun test`, `bun run test*`, `bun run typecheck`, `bun x tsc`,
   `bun install`, `bun run build:gui`, and no `ocx` execution — a past local
   suite deleted the user's real `~/.opencodex`, and a subagent shell backtick
   once triggered `ocx restore`.
3. No backticks or command substitution in shell command strings, even quoted.
   Quoted text goes to a file through `apply_patch` and is passed with
   `--body-file` / `-F`.
4. Conflict state is measured with `git merge-tree` against
   `4f8656cc0d`, which writes nothing to a working tree.
5. GUI-touching pull requests are checked against the screenshot gate before
   anything else: the gate arms on a changed path under `gui/`, so a
   `gui/`-touching PR with no screenshot in the description is
   `BLOCKED_ON_AUTHOR` regardless of code quality.
6. New providers are judged on endpoint evidence, authenticated discovery,
   model capability, and a maintenance owner. Missing any of those is
   `BLOCKED_ON_AUTHOR`; the addition itself is not a release condition.

## Progress table

Filled in `20_dispositions.md` as each pull request is judged.
