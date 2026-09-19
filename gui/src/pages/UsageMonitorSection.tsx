import { useEffect, useRef, useState } from "react";
import { useI18n } from "../i18n/shared";
import { MonitorDashboardCard } from "./MonitorDashboardCard";

function isMonitorLink() {
  return window.location.hash === "#usage/monitor" || window.location.hash.startsWith("#usage/monitor/");
}

/** Optional local companion: no loopback requests until the usage section is opened. */
export function UsageMonitorSection() {
  const { t } = useI18n();
  const [open, setOpen] = useState(isMonitorLink);
  const section = useRef<HTMLElement>(null);
  useEffect(() => {
    const sync = () => {
      if (isMonitorLink()) {
        setOpen(true);
        section.current?.scrollIntoView?.({ block: "start" });
      }
    };
    const observer = typeof IntersectionObserver === "undefined" ? null : new IntersectionObserver(entries => {
      if (entries.some(entry => entry.isIntersecting)) { setOpen(true); observer?.disconnect(); }
    });
    if (section.current) observer?.observe(section.current);
    sync();
    window.addEventListener("hashchange", sync);
    window.addEventListener("popstate", sync);
    return () => { observer?.disconnect(); window.removeEventListener("hashchange", sync); window.removeEventListener("popstate", sync); };
  }, []);
  return <section ref={section} aria-label={t("monitor.menuBarSettings")} style={{minHeight:160}}>
    <h3 className="panel-title">{t("monitor.menuBarSettings")}</h3>
    {open ? <MonitorDashboardCard /> : <button className="btn btn-ghost" type="button" onClick={() => setOpen(true)}>{t("monitor.settings")}</button>}
  </section>;
}
