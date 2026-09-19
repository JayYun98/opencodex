import { expect, test } from "bun:test";
import { Window } from "happy-dom";
import { act } from "react";
import { createRoot } from "react-dom/client";
import { LanguageProvider } from "../src/i18n/provider";
import { UsageMonitorSection } from "../src/pages/UsageMonitorSection";

test("usage monitor stays idle when closed and opens from a native deep link", async () => {
  const keys = ["window", "document", "navigator", "fetch", "IS_REACT_ACT_ENVIRONMENT"] as const;
  const old = keys.map(key => Object.getOwnPropertyDescriptor(globalThis, key));
  const win = new Window({ url: "http://localhost/#usage" });
  let reads = 0;
  const values = [win, win.document, win.navigator, async () => { reads++; return Response.json({config:{},revision:"1"}); }, true];
  keys.forEach((key, index) => Object.defineProperty(globalThis, key, {configurable:true,writable:true,value:values[index]}));
  const host = win.document.createElement("div");
  win.document.body.append(host);
  const root = createRoot(host as unknown as HTMLElement);
  try {
    await act(async () => root.render(<LanguageProvider><UsageMonitorSection /></LanguageProvider>));
    expect(reads).toBe(0);
    expect(host.querySelector(".monitor-dashboard")).toBeNull();
    await act(async () => {
      win.history.replaceState(null, "", "#usage/monitor/providers");
      win.dispatchEvent(new win.Event("hashchange"));
    });
    expect(reads).toBe(1);
    expect(host.querySelector(".monitor-dashboard")).not.toBeNull();
    expect(host.querySelector('[role="tab"][aria-selected="true"]')?.id).toBe("monitor-tab-providers");
  } finally {
    await act(async () => root.unmount());
    win.happyDOM.abort();
    keys.forEach((key, index) => old[index] ? Object.defineProperty(globalThis, key, old[index]!) : Reflect.deleteProperty(globalThis, key));
  }
});
