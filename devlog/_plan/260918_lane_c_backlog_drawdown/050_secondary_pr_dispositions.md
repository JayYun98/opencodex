# Secondary pull-request dispositions

## Supersession sweep

Every open pull request was checked mechanically for content already on `dev`: its diff was
reverse-applied against the `dev` tree with `git apply --reverse --check`, which succeeds
only when the change is already present in full.

Across 79 open pull requests, exactly one succeeded: **#4788**, which confirms by machine
what the byte-identical diff comparison already showed. #4863 and #4802 fail the check for
the reasons recorded in `020` — a variable rename and one policy line respectively — so the
detector agrees with the manual reading rather than merely echoing it.

`#4022` returns an empty diff, which is not supersession: it is a 175-file, +35,574-line
branch whose diff `gh` cannot produce. It is out of round regardless.

There is no further batch of already-merged work sitting in the open set. Drawdown has to
come from review and from justified alternate closure, not from a sweep.

## The two wrong-branch pull requests

Both target `main`, so `enforce-target` rejects them and neither can merge as written.

**#4866** (`main` ← `patch-1`, @coding-ax) changes one line of `readme/README.zh-CN.md`,
turning the bare `**http://localhost:10100**` into a markdown link. The change is not on
`dev`, so it is not superseded — but it should not be taken as written either. All seven
locale readmes and the English `README.md` (line 90) use the bare form; applying this would
leave zh-CN as the only file in the linked form, which is the locale-divergence the review
guidelines ask reviewers to prevent. The correct version of this change touches all eight
files and targets `dev`.

**#4783** (`main` ← `openai-apikey-websearch-reasoning`, @vietanhdang) is a 14-file
web-search feature touching `src/web-search/` broadly. Beyond the wrong base, it has not been
updated since 2026-09-16 while that subsystem moved substantially on `dev` — #4867, #4801,
#4595, #4586 and the `openai-responses` facade split in #4671 all landed after it. Rebasing
it is author work, not review work.

## #4800 is not an easy merge

`fix(retry): extend transient-5xx replay budget to openai-responses passthrough` is two
source lines, which makes it look like a cheap win. It is not one. It widens
`transientRetryPolicyFor` from key-auth `openai-chat` to key-auth `openai-responses`, and
replaying a Responses passthrough send is exactly the class this round excludes: a transport
where the upstream may already have committed work the client cannot see.

It also inverts an existing assertion rather than adding to one. `openai-responses` is
**removed** from the negative list in
`tests/providers/upstream-transient-retry.test.ts` and re-added as a positive case. Coverage
is not lost, but the test that pinned the narrow scope now pins the wide one, and the doc
comment describing the gate as "this first version covers key-auth `openai-chat` only" is
edited to match. Whether that widening is correct is a contract decision about replay
safety, and it belongs next to #4803 and #3389 rather than in a count-reduction batch.
