# #4159 security review — OAuth token exchange

Head `3f7f47787c`. `MAINTAINERS.md` makes OAuth token-exchange changes an explicit security
review item, and this pull request edits `src/oauth/orcarouter.ts`. Both questions are
answered against the diff and the surrounding source, with no local execution.

## 1. Does this create a new credential read or write point?

**No.** The only source change in `src/oauth/` is inside `exchangeToken`, which already read
the token-bearing response. `await response.json()` becomes a bounded byte read followed by
`JSON.parse`. No new `token`, `secret`, `credential`, `apiKey`, `refresh` or `access` path
is introduced, nothing new is persisted, and nothing new is logged. The two error strings
carry only an HTTP status and the byte ceiling, preserving the non-reflective policy the
existing comment states — never turn a code, verifier, or accidentally returned key into
console output.

**The bounded body is a token-bearing response, and that is stated rather than glossed.**
`POST /api/v1/auth/keys` is the key exchange; its payload carries the issued key. So the
question of truncation is live, and it resolves three ways at once:

- The ceiling is `BOUNDED_BODY_MAX_BYTES = 65_536` (64 KiB). A key-exchange JSON is orders of
  magnitude smaller, so a legitimate response cannot approach it.
- Oversize **fails closed**: `if (oversized) throw`. A truncated body is never parsed.
- `readBoundedResponseBytes` discards the retained prefix on oversize and returns an empty
  byte view, so no partial credential is retained even transiently.

No new timeout is introduced either: the call passes only `maxBytes` and `signal`, with no
`inactivityTimeoutMs`, so a slow-but-valid token response cannot be cut short by this change.

**There is an exact in-tree precedent.** `src/oauth/nous.ts` already does this, line for
line, on its own OAuth token response: same `BOUNDED_BODY_MAX_BYTES`, same
`readBoundedResponseBytes(response, { maxBytes, signal })`, same `oversized` throw, same
`JSON.parse(new TextDecoder("utf-8", { fatal: true }).decode(bytes))`. That response carries
`token_type`, `scope` and the access token. This pull request applies an already-merged,
already-reviewed pattern from one OAuth token exchange to another rather than inventing a
handling policy for credentials.

## 2. Does the new abort-time body cancellation have side effects?

**No, and the reason is structural rather than a survey of call sites.** The shared change in
`src/lib/bounded-body.ts` is three lines: when `signal.aborted` is already true on entry,
cancel the body before throwing.

```
-	if (signal?.aborted) throw signal.reason;
+	if (signal?.aborted) {
+		if (body) cancelBodyWithoutWaiting(body, signal.reason);
+		throw signal.reason;
+	}
```

**The throw is unchanged** — same `signal.reason`, same point in the function, and
`cancelBodyWithoutWaiting` is fire-and-forget behind `try { void body.cancel(reason).catch(() => undefined) } catch {}`,
so it can neither throw nor alter the rejection value. No caller can observe a different
exception, a different value, or a different ordering. A key-selection or cooldown state
machine downstream therefore cannot take a branch it does not take today; the only
observable difference is that a body which used to be leaked is now settled. That is the
property the #4733 finding turns on, and it holds here by construction rather than by
enumeration — which matters, because the helper has about a dozen callers including
`server/search.ts`, `server/images.ts`, `server/context-history.ts` and
`responses/compact.ts`.

The already-locked case is handled: `cancel()` on a locked or non-conforming stream throws
synchronously and is caught, leaving a no-op.

## Verdict

Both gates close. CI at `3f7f47787c` is 29 success, 0 failed, 0 pending.
