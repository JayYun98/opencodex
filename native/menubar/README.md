# OpenCodex Monitor (local macOS companion)

Native AppKit + SwiftUI + Swift Charts monitor, informed by CodexBar's
`Sources/CodexBar/StatusItemController.swift` status-item pattern.
No third-party dependencies or copied CodexBar source. Requires macOS 14+.

## Build and run

Run `sh build.sh`, then open `build/OpenCodex Monitor.app`.
To show the dashboard immediately:

```sh
open 'build/OpenCodex Monitor.app' --args --dashboard
```

The build runs isolated self-checks. `OpenCodexMonitor --probe` additionally
checks the running local proxy, graph reading and cached account quotas.
Rebuilds do not stop or restart any process; quit only this monitor before
opening the updated build. No login item is installed.

## UI

Choose **OpenCodex dashboard · display settings…** from the OCX menu.

The native menu supports English and Korean. Choose **Language → Follow system /
English / 한국어**, or set `language` to `auto`, `en`, or `ko` in the monitor config.
`auto` follows the first macOS preferred language, falling back to English for
unsupported languages. The web dashboard keeps its own existing language selection.
Built-in summary templates switch with the menu language, including previously
saved Korean defaults. Custom templates, account labels and model names are kept
verbatim. An exact match to a built-in default is treated as a default; a customized
list of summary lines is preserved as a whole.

- **사용량**: today's requests/tokens/estimated cost, time × tokens line chart
  with model or model/account legends, today's model list.
- **프로바이더**: each configured account plus the main account, session and
  weekly remaining percentage and bars together. Expired web quota observations display as unknown.
- **표시 설정**, below Usage: section visibility, menu-bar metric, graph token metric and
  individual model selection. Use Save to apply dashboard edits.

Display settings below the usage graph select 6/24/72/168 hours and 1–1,440-minute buckets.
Graph values default to per-bucket sums, not cumulative totals. Input already includes
cache; total uses max(input + output, stored total), matching opencodex's
`usageDisplayTotalTokens`. Attempt-level measurements are attributed to their
own model instead of double-counting their parent request. The last revision
of each request wins. Missing measurements are disclosed, not estimated.

Other configured providers show today's requests and tokens. OpenCode Go also
shows session/weekly/monthly remaining bars, fetched with a read-only GET from
its fixed official usage URL. Unsupported providers show “잔여 한도 미지원”.
Provider switches in settings apply to the provider tab and menu, not the
all-provider totals/chart. Hidden Go providers are not probed.

## Config

`~/.config/opencodex-monitor/config.json` is separate from proxy configuration.
The monitor rereads it on refresh (automatically every 60 seconds). Invalid
values retain the last working configuration and show an error.

```json
{
  "language": "auto",
  "hiddenProviders": [],
  "showToday": true,
  "showChart": true,
  "showAccounts": true,
  "showModels": true,
  "showCost": true,
  "menuBarMetric": "requests",
  "chartHours": 24,
  "bucketMinutes": 60,
  "tokenMetric": "total",
  "models": null
}
```

`menuBarMetric`: `requests`, `tokens`, `compact`.
`tokenMetric`: `total`, `input`, `output`, `cached` (cache reads).
`models`: null/omitted means all including future models; [] means none; an
array of exact `provider/model` strings selects specific models.
`showAccounts` controls provider menu visibility; the provider tab remains accessible.
`hiddenProviders` lists provider IDs to hide, e.g. `["opencode-free", "mimo-free"]`.
`openai` controls the Codex account cards.

## Isolation and freshness

The local proxy requests are GETs `/healthz`, `/api/usage?range=today`, and
`/api/codex-auth/quota` at `http://127.0.0.1:10100`. It reads the local admin
token without copying/logging it, uses ephemeral HTTP sessions, rejects
redirects and applies a ten-second network timeout.
For a configured canonical OpenCode Go endpoint, it additionally GETs
`https://opencode.ai/zen/go/v1/usage`, using that provider’s existing plaintext
API key in memory. It does not refresh credentials or update routing quota
caches. Keychain/environment references are reported unavailable; no keychain
prompts or credential copies are created.

The graph reads `~/.opencodex/usage.jsonl` on a background task. To bound reads,
only the newest 128 MiB are scanned; truncation and invalid-row counts are
visible. Incomplete final lines are retried at the next refresh. Account names
come from a read-only projection of `~/.opencodex/config.json`.

The account list/probe endpoints are deliberately not called: they may refresh
credentials or reconcile plans. `/api/codex-auth/quota` reads cached observations
only. Remaining percentage is clamped `100 - usedPercent`; absent values say
unavailable, never zero. After a reset deadline passes, the UI waits for a new
observation rather than pretending the account has recovered to 100%.
An idle account may retain an old cached reading. Observation timestamps are not shown in the compact account UI.

No proxy routing, credential, account selection or CodexBar settings are changed.
The app has its own bundle ID, and quitting it leaves the proxy running.
Costs are estimates, not subscription charges or remaining quotas.

Self-checks cover config defaults/validation/round-trip, duplicate log revisions,
language selection/fallback, template preservation and migration,
cache accounting, attempt attribution, filters (including none), malformed and
partial log lines, absent quota data, percentage clamping and elapsed resets.

## Appearance and text templates

All customization applies after refresh. Existing visibility/filter settings are
preserved. Invalid dimensions/colors retain the last working config.

| Config key | Default | Meaning |
| --- | --- | --- |
| `menuWidth` | 500 | Whole menu width, 320–900 points |
| `menuGraphHeight` | 175 | Menu chart height excluding legend/padding, 100–500 |
| `dashboardGraphHeight` | 300 | Dashboard chart height, 150–800 |
| `graphLineWidth` | 2 | Plot line width, 1–6 |
| `textColor` | `primary` | Main text; semantic system color or `#RRGGBB` |
| `secondaryColor` | `secondary` | Captions and provider statistics |
| `quotaGoodColor` | `#32D74B` | Remaining quota bars |
| `quotaLowColor` | `#FF9F0A` | Remaining quota below 20% |
| `quotaUnknownColor` | `#8E8E93` | Unavailable/expired quota |
| `graphPalette` | six default colors | Cycle of graph colors; nonempty, maximum 24 |
| `modelColors` | `{}` | Exact `provider/model` ID → color override |
| `todayTitle` | localized “Today’s usage” | Custom summary heading |
| `todayLines` | three summary lines | Arbitrary text/line order; empty list hides all lines |
| `costLines` | estimated cost and excluded count | Custom lines controlled by `showCost` |
| `providerUsageTemplate` | localized today/requests/tokens | Provider summary |
| `menuBarTemplate` | null | Optional text overriding `menuBarMetric` |

Text templates are literal strings with placeholders, not executable Python.
`{{` and `}}` output literal braces. Unknown placeholders stay visible so typos
are discoverable. Newlines and Unicode are supported. Limit: 20 lines per list,
1,000 characters per template. Values are substituted once, never evaluated.

Available today/menu-bar values: `{requests}`, `{totalTokens}`, `{inputTokens}`,
`{outputTokens}`, `{unpricedRequests}`, `{unmeteredRequests}`,
`{excludedRequests}`, `{costUsd}` (two decimals or —), `{date}`.
Provider summaries support `{requests}` and `{totalTokens}`.
Integer fields also support `.raw`, `.formatted`, `.compact`, for example
`{totalTokens.raw}` → `25000000`, `{totalTokens.formatted}` → `25,000,000`,
`{totalTokens.compact}` → `25.0M` (separators follow system locale).

Example fragment to merge into your config:

```json
{
  "todayTitle": "내 오늘 기록 ({date})",
  "todayLines": [
    "요청 {requests}회  |  토큰 {totalTokens}",
    "입력 {inputTokens.formatted} / 출력 {outputTokens.formatted}"
  ],
  "costLines": ["추정 ${costUsd} · 누락 {excludedRequests}회"],
  "menuBarTemplate": "OCX {requests.compact} · {totalTokens}",
  "menuWidth": 440,
  "menuGraphHeight": 150,
  "dashboardGraphHeight": 320,
  "graphLineWidth": 2,
  "graphPalette": ["#64D2FF", "#FF9F0A", "#BF5AF2", "#30D158"],
  "modelColors": {},
  "quotaGoodColor": "#64D2FF"
}
```

Model legend labels omit provider prefixes only when unambiguous; the original
IDs still control series identity/color and remain available on hover. Graph
axes use k/M/B units. Today's summary uses readable text rather than disabled
menu items. Native menu backgrounds and standard action colors follow macOS.

## Chart type and grouping

Use the graph and grouping controls in display settings below Usage:

- `chartStyle`: `line` (default) or `stackedBar`. Stacked bars sum the colored
  series within each time bucket; they are not a running cumulative total.
- `chartGrouping`: `model` (default) combines equal model names across
  accounts/providers; `modelAccount` separates model + provider + recorded
  account label. Missing account attribution displays `계정 미상` and is never
  silently attributed to the currently active account.

The existing model filter applies to original provider/model IDs before
aggregation, so grouping does not invalidate saved selections. `modelColors`
first matches the exact legend series (e.g. `example-model` or
`example-model · openai/p1`), then the original provider/model ID, then the
palette. When several sources merge, the lexicographically first source is
used as the fallback color key. With `aggregation: "sum"`, both chart forms conserve the same token sum.

## Aggregation settings

The display controls below Usage expose `bucketMinutes` (integer 1–1440) and
`aggregation`: `sum` (default), `average`, or `max`.
Each bucket and legend series is calculated independently. Repeated attempts
of the same request/series are added first; average and maximum then operate
on these per-request totals. Missing token measurements are excluded from the
average denominator; empty buckets render zero. The selected token metric and
model filter apply before calculation. Today's summary is unchanged.

Buckets are fixed durations aligned to the Unix epoch, not local calendar days.
Stacked bars stack series values even for average/maximum: their total height
is not the average/maximum across all requests. The UI explains this distinction.

## Existing web dashboard integration

The local Monitor exposes its already-collected, credential-free snapshot on
`127.0.0.1:10101`. The matching OpenCodex web dashboard’s **Usage → Menu bar settings** section
(`#usage/monitor`) displays the graph, account/provider quotas, and display settings. Menu settings
open the existing web dashboard rather than a separate native settings window.
The monitor must remain running. The proxy process and its routing are unchanged.

The bridge accepts only the exact local dashboard origins
`http://127.0.0.1:10100` and `http://localhost:10100`, validates Host, limits
request sizes/connections, and disables caching. Config writes require JSON,
a custom request header, and a matching revision; they use the same validation
and atomic config save as the native monitor. No proxy keys or account tokens
are included in snapshots. These checks isolate browser origins, not other
processes already running as the local user.
