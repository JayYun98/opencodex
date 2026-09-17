# 2.59.0 composition audit scope

Date: 2026-09-18. Lane G owns this audit record and any focused repair proposed
from it. Integration and release decisions remain with the release host.

The audited dev commit is `a0f611d4aceb9476d44268e43722273b7b211846`.
The branch is `codex/lane-g-2590-release-audit`. The primary round is
`4655d32f88^..a0f611d4ac`, with earlier Responses and combo merges included
where they supply a composition dependency.

The initial pin was `3dddc1ec2b1315311ca240ad2a3dbd10222e2c67`; the host
extended it by the one intervening commit, #4526. Its lazy Unicode schema
normalization and five hand-resolved structure documents are explicit targets.
The #4925 transient retry import resolution is another explicit target.
An exact detached worktree supplies the new source view; the documentation
branch is not merged or rebased, as the lane forbids both operations.

## Method and limits

This is a static source review with hosted CI as executable verification.
No local test, focused suite, typecheck, build, dependency installation,
repository runtime or proxy binary is permitted. No timeout, budget, retry,
platform selection or CI gate may be relaxed to obtain success.

The audit uses seven independent Sol/medium subagent requests on the V1 surface:

1. Upstream Codex source and recent PR contracts.
2. File-size ratchet, both test-layout registries and colliding paths.
3. Structure manifest, path and invariant bindings, ownership and doc semantics.
4. Responses retry/steering composition, Lab isolation and synchronous startup.
5. Codex account identity, affinity and OAuth composition.
6. Exhaustive maps, client rosters and reauthorization composition.
7. Usage pricing, Cursor/Google changes, web-search replay and Devin limits.

The lane owner handles authenticated Aside observations, exact-SHA hosted CI,
finding adjudication and publication. Workers are read-only; any verified repair
gets a focused change and PR against dev, with all template sections completed.
Unpublished security findings stay in ignored scratch space.

## Records and completion

- This file records the scope and constraints.
- `080_composition_audit.md` will record adjudicated source findings and upstream
  compatibility evidence.
- `090_composition_ci.md` will record exact commit/run identities, platform
  coverage and the release verdict.

A clean static result is valid. It is distinct from a complete hosted platform
verification result. The final verdict must state both and name the exact SHA.
The requested directory remains under `_plan` while the release host owns the
open train; the audit lane does not move or close that train.
