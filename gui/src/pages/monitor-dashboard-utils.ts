export type MonitorPoint = { date: number; model: string; tokens: number };

export type MonitorSummaryFields = {
  requests?: number;
  totalTokens?: number;
  inputTokens?: number;
  outputTokens?: number;
  unpricedRequests?: number;
  unmeteredRequests?: number;
  estimatedCostUsd?: number;
};

/** Native-compatible single-pass replacement: {{ and }} are literal braces; unknown fields remain visible. */
export function monitorTemplate(text: string, fields: Record<string, string>): string {
  return text.replace(/\{\{|\}\}|\{([A-Za-z][A-Za-z0-9]*(?:\.[A-Za-z]+)?)\}/g, (token, name: string | undefined) => {
    if (token === "{{") return "{";
    if (token === "}}") return "}";
    return name === undefined ? token : fields[name] ?? token;
  });
}

function monitorInteger(value: number | undefined): number {
  return typeof value === "number" && Number.isFinite(value) ? Math.trunc(value) : 0;
}

function monitorCompact(value: number): string {
  if (value >= 1_000_000) return `${(value / 1_000_000).toFixed(1)}M`;
  if (value >= 1_000) return `${(value / 1_000).toFixed(1)}k`;
  return String(value);
}

/** Fields accepted by the native summary templates, including raw/compact/formatted variants. */
export function monitorNumberFields(summary: MonitorSummaryFields, locale: string): Record<string, string> {
  const fields: Record<string, string> = {};
  const values: Record<string, number> = {
    requests: monitorInteger(summary.requests),
    totalTokens: monitorInteger(summary.totalTokens),
    inputTokens: monitorInteger(summary.inputTokens),
    outputTokens: monitorInteger(summary.outputTokens),
    unpricedRequests: monitorInteger(summary.unpricedRequests),
    unmeteredRequests: monitorInteger(summary.unmeteredRequests),
  };
  values.excludedRequests = values.unpricedRequests + values.unmeteredRequests;
  const formatted = new Intl.NumberFormat(locale);
  for (const [name, value] of Object.entries(values)) {
    fields[name] = name.toLowerCase().includes("tokens") ? monitorCompact(value) : formatted.format(value);
    fields[`${name}.raw`] = String(value);
    fields[`${name}.compact`] = monitorCompact(value);
    fields[`${name}.formatted`] = formatted.format(value);
  }
  fields.costUsd = typeof summary.estimatedCostUsd === "number" && Number.isFinite(summary.estimatedCostUsd)
    ? summary.estimatedCostUsd.toFixed(2) : "—";
  fields.date = new Intl.DateTimeFormat(locale, { dateStyle: "medium" }).format(new Date());
  return fields;
}

/** SVG-ready paths for the monitor graph. Empty and zero-only series stay drawable. */
export function monitorSeriesPaths(points: MonitorPoint[], width = 720, height = 220, domain?: { start: number; end: number }): Array<{ name: string; path: string }> {
  const byName = new Map<string, MonitorPoint[]>();
  for (const point of points) {
    if (!Number.isFinite(point.date) || !Number.isFinite(point.tokens)) continue;
    const values = byName.get(point.model) ?? [];
    values.push(point);
    byName.set(point.model, values);
  }
  let start = Infinity;
  let end = -Infinity;
  let max = 1;
  for (const values of byName.values()) for (const point of values) {
    start = Math.min(start, point.date);
    end = Math.max(end, point.date);
    max = Math.max(max, point.tokens);
  }
  if (!Number.isFinite(start)) return [];
  if (domain && Number.isFinite(domain.start) && domain.end > domain.start) { start = domain.start; end = domain.end; }
  const x = (date: number) => end === start ? width / 2 : ((date - start) / (end - start)) * width;
  const y = (tokens: number) => height - Math.max(0, tokens) / max * height;
  return [...byName.entries()].map(([name, values]) => ({
    name,
    path: values.sort((a, b) => a.date - b.date).map((point, index) => `${index ? "L" : "M"}${x(point.date).toFixed(1)},${y(point.tokens).toFixed(1)}`).join(" "),
  }));
}

export function monitorPercent(value: unknown): number | null {
  return typeof value === "number" && Number.isFinite(value) ? Math.min(100, Math.max(0, value)) : null;
}

export function monitorStackedBars(points: MonitorPoint[], width = 720, height = 220, domain?: { start: number; end: number; bucketSeconds?: number }): Array<{ x: number; y: number; width: number; height: number; series: number }> {
  const buckets = new Map<number, MonitorPoint[]>();
  const names = new Map<string, number>();
  for (const point of points) {
    if (!Number.isFinite(point.date) || !Number.isFinite(point.tokens)) continue;
    const bucket = buckets.get(point.date) ?? [];
    bucket.push(point); buckets.set(point.date, bucket);
    if (!names.has(point.model)) names.set(point.model, names.size);
  }
  const dates = [...buckets.keys()].sort((a, b) => a - b);
  let max = 1;
  for (const date of dates) max = Math.max(max, buckets.get(date)!.reduce((sum, point) => sum + Math.max(0, point.tokens), 0));
  const timed = domain && Number.isFinite(domain.start) && domain.end > domain.start && (domain.bucketSeconds ?? 0) > 0 ? domain : undefined;
  const slot = timed ? width * timed.bucketSeconds! / (timed.end - timed.start) : width / Math.max(1, dates.length);
  const barWidth = slot * 0.85;
  return dates.flatMap((date, index) => {
    let bottom = height;
    return buckets.get(date)!.map(point => {
      const barHeight = Math.max(0, point.tokens) / max * height;
      bottom -= barHeight;
      const x = timed ? Math.max(0, (date - timed.start) / (timed.end - timed.start) * width) : index * slot;
      return { x, y: bottom, width: Math.max(0, Math.min(barWidth, width - x)), height: barHeight, series: names.get(point.model) ?? 0 };
    });
  });
}

export function monitorRemaining(used: unknown, reset?: number, now = Date.now() / 1000): number | null {
  const value = monitorPercent(used);
  return value === null || (reset !== undefined && reset <= now) ? null : 100 - value;
}

/** Give repeated user-authored lines stable identities without dropping duplicates. */
export function monitorTemplateRows(lines: string[]): Array<{ key: string; text: string }> {
  const counts = new Map<string, number>();
  return lines.map(text => {
    const occurrence = (counts.get(text) ?? 0) + 1;
    counts.set(text, occurrence);
    return { key: JSON.stringify([text, occurrence]), text };
  });
}
