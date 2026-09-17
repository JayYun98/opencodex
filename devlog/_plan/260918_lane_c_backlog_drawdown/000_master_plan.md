# Lane C — backlog drawdown round (2026-09-18)

Baseline: `origin/dev` = `2f025814f3`, `package.json` 2.59.0. `main` and `preview` are
released at 2.58.0. 79 open issues, 77 open pull requests. The round targets fewer than 50
of each.

This lane does not add net pull requests. Opening a change and merging it is neutral on the
PR count, so the lane's work is review, integration and justified alternate closure of work
that already exists. Nothing here closes an issue or a pull request; closure is the host's.

## Verification posture

No local verification was run in this lane: no `bun test` in any form, no `bun run test`,
`test:changed`, `typecheck`, `bun x tsc`, `bun install`, `build:gui`, and no `ocx`
invocation. A past local suite run deleted real `~/.opencodex` data. Every finding below
rests on reading source at a named commit, on `git merge-base --is-ancestor` against
`origin/dev`, and on hosted check-runs read at an exact head.

## Units

- `010_merged_issue_closure_matrix.md` — the eleven issues whose fix is already on `dev`:
  what each issue asked for, what the merge delivered, what remains, and a closure
  recommendation per row.
- `020_carry_original_disposition.md` — the carried originals (#4788, #4863, #4802) and
  whether anything unique survives in them.
- `030_fork_ci_approval_gate.md` — why no fork pull request in this round carries
  exact-head test evidence, and what unblocks a batch of them at once.
- `040_operational_recovery.md` — #4897 and the release that already carries its fix.

## Standing constraint

No change in this round may hide a failure to move a number: no failover on every 400, no
replay of a send whose delivery is unknown, no unconditional stripping of an unsupported
field, and no reporting of unobserved usage as zero.
