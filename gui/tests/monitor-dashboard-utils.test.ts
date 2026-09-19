import { expect, test } from "bun:test";
import { monitorTemplateRows, monitorNumberFields, monitorRemaining, monitorPercent, monitorSeriesPaths, monitorStackedBars, monitorTemplate } from "../src/pages/monitor-dashboard-utils";

test("monitor graph paths preserve separate series and clamp quota percentages", () => {
  const paths = monitorSeriesPaths([
    { date: 20, model: "second", tokens: 10 },
    { date: 10, model: "first", tokens: 5 },
    { date: 10, model: "second", tokens: 0 },
  ]);
  expect(paths.map(path => path.name)).toEqual(["second", "first"]);
  expect(paths[0]?.path).toStartWith("M0.0,220.0 L720.0,0.0");
  expect(monitorPercent(-1)).toBe(0);
  expect(monitorPercent(120)).toBe(100);
  expect(monitorPercent("50")).toBeNull();
});

test("monitor templates retain unknown braces and never expand field values twice", () => {
  expect(monitorTemplate("{{ {requests} }} {missing} {nested}", { requests: "2", nested: "{requests}" }))
    .toBe("{ 2 } {missing} {requests}");
  const fields = monitorNumberFields({ requests: 1200, totalTokens: 2_500_000, unpricedRequests: 2, unmeteredRequests: 3, estimatedCostUsd: 1.2 }, "en-US");
  expect(fields.requests).toBe("1,200");
  expect(fields["requests.raw"]).toBe("1200");
  expect(fields["totalTokens.compact"]).toBe("2.5M");
  expect(fields.excludedRequests).toBe("5");
  expect(fields.costUsd).toBe("1.20");
});

test("dense stacked buckets remain inside the SVG domain", () => {
  const bars = monitorStackedBars(Array.from({ length: 10_080 }, (_, date) => ({ date, model: "m", tokens: 1 })));
  expect(bars).toHaveLength(10_080);
  expect(Math.max(...bars.map(bar => bar.x + bar.width))).toBeLessThanOrEqual(720);
});

test("elapsed quota observations are unknown instead of current remaining limits", () => {
  expect(monitorRemaining(12,100,101)).toBeNull();
  expect(monitorRemaining(12,102,101)).toBe(88);
  expect(monitorRemaining(undefined,102,101)).toBeNull();
});

 test("graph uses the requested time window including a partial final bucket", () => {
  const points = [{ date: 10, model: "m", tokens: 1 }, { date: 20, model: "m", tokens: 2 }];
  const domain = { start: 0, end: 25, bucketSeconds: 10 };
  expect(monitorSeriesPaths(points, 100, 100, domain)[0]?.path).toBe("M40.0,50.0 L80.0,0.0");
  const bars = monitorStackedBars(points, 100, 100, domain);
  expect(bars.map(bar => bar.x)).toEqual([40, 80]);
  expect(bars[1]!.x + bars[1]!.width).toBe(100);
});

test("template row identities preserve duplicates and survive unrelated insertions", () => {
  const before = monitorTemplateRows(["same", "same"]);
  const after = monitorTemplateRows(["new", "same", "same"]);
  expect(before).toEqual(after.slice(1));
  expect(new Set(before.map(row => row.key)).size).toBe(2);
});
