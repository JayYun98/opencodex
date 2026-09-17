# Carried originals

The question for each is narrow: after the maintainer replay landed, does the original
still hold a change the replay does not have? It was answered by diffing the two pull
requests, not by reading their descriptions.

## #4788 — nothing unique remains

`gh pr diff 4788` and `gh pr diff 4888` are **byte-identical** once the `index` lines are
removed: same five files, same 448 diff lines, `diff` reports no difference. The replay
merged as `25311bcc00`, and its commit carries
`Co-authored-by: oliver-mee <102673257+oliver-mee@users.noreply.github.com>`, so the
contribution is attributed on the graph.

Alternate-close candidate. Nothing is lost by closing it, and the catalog values it
measured are what shipped.

## #4863 — nothing functional remains

The two diffs differ in exactly three places, all in one hunk: the local is named
`contextWindow` in the original and `parsedContextWindow` in the replay, and the replay
carries a trailing comment recording why an invalid draft must not read as "field omitted /
override cleared". Behaviour is identical. The replay merged as `3bdaf61962` with
`Co-authored-by: liangbo <liangbo.yejc@bytedance.com>`.

Alternate-close candidate.

## #4802 — one real policy difference, and it should be decided against the original

#4889 (`cdd564b974`, `Co-authored-by: Yum-wu`) shipped the top-level mirror. The only
surviving difference is which window the mirror carries when a row has an opt-in long tier:

- #4802: `context_window` / `context_length` = `contextLength` (the **base**, 272k for
  native GPT-5.6), while `capabilities.context_length` stays the long window (922k).
- #4889: both shapes carry `effectiveContextLength` (922k).

The original's stated reason is cost safety — a flat-property client that does not parse
Cursor pricing overrides should not budget into a tiered surcharge unknowingly.

**Recommendation: keep #4889's behaviour and close #4802 as superseded.** Three reasons,
in order of weight.

1. #4802 makes a single row self-contradicting. `context_length` at the top level would say
   272k while `capabilities.context_length` says 922k, with nothing on the row declaring
   which is authoritative. A client that reads the wrong one is wrong in a new way, and a
   client that reads both cannot tell which. That is the reason the host already gave in
   #4889 and it survives contact with the diff.
2. Under-reporting is not the safe default it looks like. For rows where the long window is
   the usable window, reporting the base makes a client compact early and truncate context
   it could have sent — the same symptom class as #4857 and #508, reached from the other
   direction. "Safe" here trades an over-spend risk for a silent capability loss.
3. The base is still discoverable on the row. `pricing.overrides[0].min_prompt_tokens`
   carries `contextLength` at the top level whenever a long tier exists, and #4889 left that
   untouched. A client that wants the threshold has it.

The corollary the host already stated holds: changing the default window policy is a
separate change that moves the nested value, the top-level mirror and the threshold
together. It is not this pull request, and it is not a blocker for closing it.
