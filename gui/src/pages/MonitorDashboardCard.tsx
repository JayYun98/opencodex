import { useEffect, useRef, useState } from "react";
import { createBoundedFetch, type BoundedFetch } from "../bounded-fetch";
import { Select } from "../ui";
import { navigateHash } from "../hash-routing";
import { useI18n } from "../i18n/shared";
import { startVisibilityPoll } from "../visibility-poll";
import { monitorNumberFields, monitorTemplateRows, monitorTemplate, monitorRemaining, monitorSeriesPaths, monitorStackedBars, type MonitorPoint } from "./monitor-dashboard-utils";

const MONITOR_BASE = "http://127.0.0.1:10101";

type MonitorConfig = Record<string, unknown>;
type MonitorState = {
  config: MonitorConfig;
  revision: string;
  graph?: { start: number; end: number; points: MonitorPoint[]; availableModels?: string[]; seriesSources?: Record<string,string>; aggregation?: string; bucketSeconds?: number; missing?: number; skipped?: number; truncated?: boolean };
  usage?: { summary?: { requests?: number; totalTokens?: number; inputTokens?: number; outputTokens?: number; estimatedCostUsd?: number; unpricedRequests?: number; unmeteredRequests?: number }; models?: Array<{provider:string;model:string;requests:number;totalTokens:number}>; providers?: Array<{provider:string;requests:number;totalTokens:number}> };
  accounts?: Array<{ id: string; email?: string; alias?: string; logLabel?: string; plan?: string; name?: string }>;
  quotas?: Record<string, { weeklyPercent?: number; shortPercent?: number; weeklyResetAt?: number; shortResetAt?: number }>;
  providerNames?: string[];
  providerWindows?: Record<string, Array<{ label: string; used?: number; reset?: number }>>;
  providerErrors?: Record<string, unknown>;
  updated?: number;
  failure?: string;
  graphError?: string;
  quotaError?: string;
};

function themeColor(value: unknown): string | undefined {
  return value === "primary" ? "var(--text)" : value === "secondary" ? "var(--muted)" : typeof value === "string" && /^#[0-9a-f]{6}$/i.test(value) ? value : undefined;
}

function QuotaBar({ label, value, reset, config }: { label: string; value: number | undefined; reset?: number; config: MonitorConfig }) {
  const remaining = monitorRemaining(value, reset);
  return <div className="monitor-quota"><span>{label}</span><div className="monitor-bar"><i style={{ width: `${remaining ?? 0}%`, background: themeColor(config[remaining === null ? "quotaUnknownColor" : remaining < 20 ? "quotaLowColor" : "quotaGoodColor"]) }} /></div><b>{remaining === null ? "—" : `${Math.round(remaining)}%`}</b></div>;
}

function readMonitorTab() { return window.location.hash === "#monitor/providers" ? "providers" : "usage"; }

export function MonitorDashboardCard() {
  const { locale, t } = useI18n();
  const [tab, setTab] = useState(readMonitorTab);
  useEffect(() => {
    const sync = () => setTab(readMonitorTab());
    window.addEventListener("hashchange", sync);
    window.addEventListener("popstate", sync);
    return () => { window.removeEventListener("hashchange", sync); window.removeEventListener("popstate", sync); };
  }, []);
  const tabs = [{id:"usage",label:t("nav.usage")},{id:"providers",label:t("nav.providers")}];
  const selectTab = (id: string) => { setTab(id); navigateHash(id === "usage" ? "monitor" : `monitor/${id}`); };

  const [state, setState] = useState<MonitorState | null>(null);
  const [draft, setDraft] = useState("");
  const [dirty, setDirty] = useState(false);
  const [saving, setSaving] = useState(false);
  const [connectionError, setConnectionError] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const dirtyRef = useRef(false);
  const requestGeneration = useRef(0);
  const revisionRef = useRef<string | null>(null);
  const refreshRef = useRef<() => Promise<void>>(async () => undefined);

  useEffect(() => { dirtyRef.current = dirty; }, [dirty]);
  useEffect(() => {
    let cancelled = false;
    let inFlight = false;
    let active: BoundedFetch | null = null;
    const refresh = async () => {
      if (inFlight) return;
      inFlight = true;
      const generation = requestGeneration.current;
      const bounded = createBoundedFetch(4_000);
      active = bounded;
      try {
        const response = await fetch(`${MONITOR_BASE}/state`, { credentials: "omit", cache: "no-store", signal: bounded.signal });
        if (!response.ok) throw new Error(`HTTP ${response.status}`);
        const next = await response.json() as MonitorState;
        if (cancelled || generation !== requestGeneration.current) return;
        setState(next);
        setConnectionError(null);
        if (!dirtyRef.current) {
          revisionRef.current = next.revision;
          setDraft(JSON.stringify(next.config, null, 2));
        }
      } catch {
        if (!cancelled) setConnectionError(t("monitor.unavailable"));
      } finally {
        bounded.clear();
        if (active === bounded) active = null;
        inFlight = false;
      }
    };
    refreshRef.current = refresh;
    void refresh();
    const stop = startVisibilityPoll(() => void refresh(), 5_000);
    return () => { cancelled = true; active?.controller.abort(); active?.clear(); stop(); };
  }, [t]);

  const save = async () => {
    if (!state) return;
    let config: MonitorConfig;
    try { config = JSON.parse(draft) as MonitorConfig; if (!config || typeof config !== "object" || Array.isArray(config)) throw new Error(); }
    catch { setError(t("monitor.invalidConfig")); return; }
    requestGeneration.current += 1;
    setSaving(true); setError(null);
    const bounded = createBoundedFetch(6_000);
    try {
      const response = await fetch(`${MONITOR_BASE}/config`, { method: "POST", credentials: "omit", signal: bounded.signal, headers: { "Content-Type": "application/json", "X-Monitor-Request": "1" }, body: JSON.stringify({ config, revision: revisionRef.current ?? state.revision }) });
      if (response.status === 409) throw new Error(t("monitor.stale"));
      if (!response.ok) throw new Error(t("monitor.saveFailed"));
      const next = await response.json() as MonitorState | undefined;
      requestGeneration.current += 1;
      if (next?.config) { setState(next); revisionRef.current = next.revision; setDraft(JSON.stringify(next.config, null, 2)); }
      dirtyRef.current = false;
      setDirty(false);
      await refreshRef.current();
    } catch (cause) { setError(cause instanceof Error ? cause.message : t("monitor.saveFailed")); }
    finally { bounded.clear(); setSaving(false); }
  };

  let config = state?.config ?? {};
  try { const parsed: unknown = JSON.parse(draft); if (parsed && typeof parsed === "object" && !Array.isArray(parsed)) config = parsed as MonitorConfig; } catch { /* retain the last valid server config while editing malformed JSON */ }
  const setDraftConfig = (patch: MonitorConfig) => {
    let current = config;
    try { current = JSON.parse(draft) as MonitorConfig; } catch { /* preserve the raw invalid JSON for correction */ }
    setDraft(JSON.stringify({ ...current, ...patch }, null, 2));
    dirtyRef.current = true;
    setDirty(true);
  };
  const show = (key: string) => config[key] !== false;
  const chartHeight = typeof config.dashboardGraphHeight === "number" ? Math.min(800, Math.max(150, config.dashboardGraphHeight)) : 300;
  const palette = Array.isArray(config.graphPalette) ? config.graphPalette.filter((color): color is string => typeof color === "string") : [];
  const modelColors = typeof config.modelColors === "object" && config.modelColors ? config.modelColors as Record<string, unknown> : {};
  const colorFor = (name: string, index: number) => themeColor(modelColors[name] ?? modelColors[state?.graph?.seriesSources?.[name] ?? ""] ?? palette[index % palette.length]) ?? `var(--monitor-${index % 6})`;
  const selectedModels = Array.isArray(config.models) ? new Set(config.models) : null;
  const hiddenProviders = new Set(Array.isArray(config.hiddenProviders) ? config.hiddenProviders.filter((name): name is string => typeof name === "string") : []);
  const paths = monitorSeriesPaths(state?.graph?.points ?? [], 720, chartHeight, state?.graph);
  const bars = monitorStackedBars(state?.graph?.points ?? [], 720, chartHeight, state?.graph);
  const summary = state?.usage?.summary;
  const fields = monitorNumberFields(summary ?? {}, locale);
  const lines = (key: string) => Array.isArray(config[key]) ? (config[key] as unknown[]).filter((line): line is string => typeof line === "string") : [];
  const buckets = new Map<number, number>();
  let maximum = 1, start = Infinity, end = -Infinity;
  for (const point of state?.graph?.points ?? []) {
    start = Math.min(start, point.date); end = Math.max(end, point.date);
    maximum = Math.max(maximum, point.tokens);
    buckets.set(point.date, (buckets.get(point.date) ?? 0) + point.tokens);
  }
  if (config.chartStyle === "stackedBar") for (const total of buckets.values()) maximum = Math.max(maximum, total);
  if (state?.graph && Number.isFinite(state.graph.start) && state.graph.end > state.graph.start) { start = state.graph.start; end = state.graph.end; }
  else if (config.chartStyle === "stackedBar") end += state?.graph?.bucketSeconds ?? 0;
  const axisNumber = (value: number) => new Intl.NumberFormat(locale, {notation:"compact", maximumFractionDigits:1}).format(value);
  const timeLabel = (value: number) => new Date(value * 1000).toLocaleString(locale, {month:"numeric",day:"numeric",hour:"2-digit",minute:"2-digit"});

  return <>
    <div className="page-tabs" role="tablist" aria-label={t("nav.monitor")}>
      {tabs.map((item,index) => <button type="button" role="tab" key={item.id}
        id={`monitor-tab-${item.id}`} aria-controls={`monitor-panel-${item.id}`} aria-selected={tab === item.id}
        tabIndex={tab === item.id ? 0 : -1} className={`page-tab${tab === item.id ? " page-tab--active" : ""}`}
        onClick={() => selectTab(item.id)} onKeyDown={event => {
          const next = event.key === "ArrowRight" ? (index+1)%tabs.length : event.key === "ArrowLeft" ? (index+tabs.length-1)%tabs.length : event.key === "Home" ? 0 : event.key === "End" ? tabs.length-1 : -1;
          if (next < 0) return;
          event.preventDefault(); selectTab(tabs[next].id); document.getElementById(`monitor-tab-${tabs[next].id}`)?.focus();
        }}>{item.label}</button>)}
    </div>
    <section className="panel monitor-dashboard" role="tabpanel" id={`monitor-panel-${tab}`} aria-labelledby={`monitor-tab-${tab}`} tabIndex={0} style={{color: themeColor(config.textColor)}}>
    <div className="panel-head"><h3 className="panel-title">{tabs.find(item => item.id === tab)?.label}</h3><span className="muted">{state?.updated ? new Date(state.updated * 1000).toLocaleTimeString(locale) : t("common.loading")}</span></div>
    {connectionError && <p className="monitor-error" role="status">{connectionError}</p>}
    {[state?.failure, state?.graphError, state?.quotaError].filter(Boolean).map((message,index) => <p className="monitor-error" key={`${index}:${message}`}>{message}</p>)}
    {error && <p className="monitor-error" role="status">{error}</p>}
    {tab === "usage" && show("showToday") && <div className="monitor-today">
      <strong>{monitorTemplate(String(config.todayTitle ?? ""), fields)}</strong>
      <div className="monitor-today-lines">{monitorTemplateRows(lines("todayLines")).map(line => <span key={line.key}>{monitorTemplate(line.text, fields)}</span>)}</div>
      {show("showCost") && <div className="monitor-cost" style={{color:themeColor(config.secondaryColor)}}>{monitorTemplateRows(lines("costLines")).map(line => <span key={line.key}>{monitorTemplate(line.text, fields)}</span>)}</div>}
    </div>}
    {tab === "usage" && show("showChart") && <div className="monitor-graph" aria-label={t("monitor.graph")}>
      {paths.length ? <svg viewBox={`-65 -20 805 ${chartHeight + 65}`} style={{height:chartHeight + 65}} role="img"><title>{t("monitor.graph")}</title>{[0, 0.5, 1].map(ratio => <g key={ratio}><line className="monitor-axis" x1="0" x2="720" y1={chartHeight * (1-ratio)} y2={chartHeight * (1-ratio)} /><text className="monitor-axis-label" textAnchor="end" x="-8" y={chartHeight*(1-ratio)+4}>{axisNumber(maximum*ratio)}</text></g>)}{Number.isFinite(start) && [0,0.5,1].map(ratio => <text className="monitor-axis-label" textAnchor={ratio===0 ? "start" : ratio===1 ? "end" : "middle"} key={ratio} x={720*ratio} y={chartHeight+22}>{timeLabel(start+(end-start)*ratio)}</text>)}<line className="monitor-axis" x1="0" y1={chartHeight} x2="720" y2={chartHeight} /><line className="monitor-axis" x1="0" y1="0" x2="0" y2={chartHeight} /><text className="monitor-axis-label" x="0" y="-8">{t("monitor.tokensAxis")}</text><text className="monitor-axis-label" x="670" y={chartHeight + 42}>{t("monitor.timeAxis")}</text>{config.chartStyle === "stackedBar" ? bars.map((bar, index) => <rect key={index} x={bar.x} y={bar.y} width={bar.width} height={bar.height} fill={colorFor(paths[bar.series]?.name ?? "", bar.series)} />) : paths.map((series, index) => <path key={series.name} d={series.path} className="monitor-line" style={{ stroke: colorFor(series.name, index), strokeWidth: typeof config.graphLineWidth === "number" ? config.graphLineWidth : undefined }} />)}</svg> : <p className="muted">{t("monitor.empty")}</p>}
      {paths.length > 0 && <div className="monitor-legend">{paths.map((series, index) => <span key={series.name} title={series.name}><i style={{ background: colorFor(series.name, index) }} />{series.name}</span>)}</div>}
    </div>}
    {tab === "usage" && show("showChart") && state?.graph && state.graph.aggregation !== "sum" && <p className="muted">{t("monitor.averageNote")}</p>}
    {tab === "providers" && <div className="monitor-provider-settings"><label><input type="checkbox" checked={show("showAccounts")} disabled={saving} onChange={event => setDraftConfig({showAccounts:event.target.checked})}/>{t("monitor.showAccounts")}</label><div className="monitor-provider-toggles">{(state?.providerNames ?? []).map(name => <label key={name}><input type="checkbox" disabled={saving} checked={!hiddenProviders.has(name)} onChange={event => setDraftConfig({hiddenProviders: event.target.checked ? [...hiddenProviders].filter(value => value !== name) : [...hiddenProviders, name]})} />{name}</label>)}</div></div>}
    {tab === "providers" && <div className="monitor-quotas">
      {!hiddenProviders.has("openai") && (state?.accounts ?? []).map(account => { const quota = state?.quotas?.[account.id]; return <div className="monitor-account" key={account.id}><strong>{account.name ?? account.email ?? account.id}</strong>{(account.email || account.plan) && <small className="monitor-account-meta">{[account.email, account.plan].filter(Boolean).join(" · ")}</small>}<QuotaBar config={config} label={t("monitor.shortQuota")} value={quota?.shortPercent} reset={quota?.shortResetAt} /><QuotaBar config={config} label={t("monitor.weeklyQuota")} value={quota?.weeklyPercent} reset={quota?.weeklyResetAt} /></div>; })}
      {(state?.providerNames ?? []).filter(provider => provider !== "openai" && !hiddenProviders.has(provider)).map(provider => <div className="monitor-account" key={provider}><strong>{provider}</strong><small className="monitor-account-meta">{monitorTemplate(String(config.providerUsageTemplate ?? ""), monitorNumberFields(state?.usage?.providers?.find(item => item.provider === provider) ?? {}, locale))}</small>{typeof state?.providerErrors?.[provider] === "string" && <small className="monitor-error">{String(state.providerErrors[provider])}</small>}{(state?.providerWindows?.[provider] ?? []).map(window => <QuotaBar config={config} key={window.label} label={window.label} value={window.used} reset={window.reset} />)}</div>)}
    </div>}
    {tab === "usage" && show("showModels") && <div className="monitor-model-list">{(state?.usage?.models ?? []).map(model => <div key={`${model.provider}/${model.model}`}><span>{model.provider}/{model.model}</span><span>{monitorTemplate(String(config.providerUsageTemplate ?? ""),monitorNumberFields(model,locale))}</span></div>)}</div>}
    {tab === "usage" && <div className="monitor-settings"><h3 className="panel-title">{t("monitor.displaySettings")}</h3><fieldset disabled={saving || !state} className="monitor-controls">
      <div className="monitor-control"><span className="field-label">{t("monitor.chartStyle")}</span><Select label={t("monitor.chartStyle")} disabled={saving || !state} value={String(config.chartStyle ?? "line")} onChange={value => setDraftConfig({chartStyle:value})} options={[{value:"line",label:t("monitor.line")},{value:"stackedBar",label:t("monitor.stackedBar")}]} /></div>
      <div className="monitor-control"><span className="field-label">{t("monitor.grouping")}</span><Select label={t("monitor.grouping")} disabled={saving || !state} value={String(config.chartGrouping ?? "model")} onChange={value => setDraftConfig({chartGrouping:value})} options={[{value:"model",label:t("monitor.model")},{value:"modelAccount",label:t("monitor.modelAccount")}]} /></div>
      <div className="monitor-control"><span className="field-label">{t("monitor.hours")}</span><Select label={t("monitor.hours")} disabled={saving || !state} value={String(config.chartHours ?? 24)} onChange={value => setDraftConfig({chartHours:Number(value)})} options={[6,24,72,168].map(value => ({value:String(value),label:String(value)}))} /></div>
      <label>{t("monitor.bucket")}<input className="input" type="number" min="1" max="1440" value={typeof config.bucketMinutes === "number" ? config.bucketMinutes : 60} onChange={event => setDraftConfig({ bucketMinutes: Math.min(1440, Math.max(1, Number(event.target.value) || 1)) })} /></label>
      <div className="monitor-control"><span className="field-label">{t("monitor.aggregation")}</span><Select label={t("monitor.aggregation")} disabled={saving || !state} value={String(config.aggregation ?? "sum")} onChange={value => setDraftConfig({aggregation:value})} options={[{value:"sum",label:t("monitor.sum")},{value:"average",label:t("monitor.average")},{value:"max",label:t("monitor.max")}]} /></div>
      <div className="monitor-control"><span className="field-label">{t("monitor.metric")}</span><Select label={t("monitor.metric")} disabled={saving || !state} value={String(config.tokenMetric ?? "total")} onChange={value => setDraftConfig({tokenMetric:value})} options={[{value:"total",label:t("monitor.total")},{value:"input",label:t("monitor.input")},{value:"output",label:t("monitor.output")},{value:"cached",label:t("monitor.cached")}]} /></div>
      <div className="monitor-control"><span className="field-label">{t("monitor.display")}</span><Select label={t("monitor.display")} disabled={saving || !state} value={show("showChart") ? "on" : "off"} onChange={value => setDraftConfig({showChart:value === "on"})} options={[{value:"on",label:t("monitor.on")},{value:"off",label:t("monitor.off")}]} /></div>
    </fieldset><div className="monitor-provider-toggles">{([['showToday','monitor.showToday'],['showModels','monitor.showModels'],['showCost','monitor.showCost']] as const).map(([key,label]) => <label key={key}><input type="checkbox" checked={show(key)} disabled={saving} onChange={event => setDraftConfig({[key]:event.target.checked})}/>{t(label)}</label>)}</div><details className="monitor-filter"><summary>{t("monitor.modelFilter")}</summary><button className="btn btn-ghost" type="button" disabled={saving} onClick={() => setDraftConfig({models:null})}>{t("monitor.allModels")}</button><div className="monitor-provider-toggles">{(state?.graph?.availableModels ?? []).map(model => <label key={model}><input type="checkbox" disabled={saving} checked={selectedModels === null || selectedModels.has(model)} onChange={event => {const selected=Array.isArray(config.models) ? config.models as string[] : state?.graph?.availableModels ?? [];setDraftConfig({models:event.target.checked ? [...new Set([...selected,model])] : selected.filter(value => value!==model)});}}/>{model}</label>)}</div></details><details className="monitor-json"><summary>{t("monitor.config")}</summary><textarea aria-label={t("monitor.config")} id="monitor-config" className="input" disabled={saving} rows={14} value={draft} onChange={event => { dirtyRef.current = true; setDraft(event.target.value); setDirty(true); }} spellCheck={false} /></details></div>}
    {<div className="monitor-actions"><button type="button" className="btn btn-ghost" disabled={!dirty || saving} onClick={() => { dirtyRef.current=false;setDirty(false);setError(null);revisionRef.current=state?.revision ?? null;setDraft(JSON.stringify(state?.config ?? {},null,2)); }}>{t("common.discard")}</button><button type="button" className="btn btn-primary" onClick={() => void save()} disabled={!dirty || saving}>{saving ? t("common.saving") : t("common.save")}</button></div>}
  </section></>;
}
