/**
 * The bunfig preload may not reach `bun:test`.
 *
 * `bunfig.toml` names `tests/preload.ts`, and Bun re-loads it for every test file: `--isolate`
 * gives each file its own realm and `reload_entry_point_for_test_runner` calls `load_preloads`
 * again each time. A 219-file Windows shard therefore evaluates that module graph 219 times in
 * one process, which makes the preload the single most re-entered graph in the repository and
 * the wrong place to name a runtime built-in.
 *
 * #4796 named one anyway — `import { afterAll } from "bun:test"`, to register temp-root cleanup
 * on the test lifecycle instead of on process exit. On the 67th re-load Bun dereferenced a dead
 * JSPromise inside its own module loader and took SIGSEGV:
 *
 *   panic(main thread): Segmentation fault at address 0x10
 *     JSC::JSPromise::status -> JSC::JSModuleLoader::loadModule -> JSC::moduleLoadTopSettled
 *     -> bun_runtime::jsc_hooks::load_preloads
 *
 * Windows shard 5/6 of dispatch runs 35087572377 and 35093667426 failed that way on both
 * attempts; Linux shards took the same fault as exit 139 at five unrelated batch boundaries,
 * where the batch runner hid it by re-running each file alone — one preload load never reaches
 * the second that faults, so singleton isolation always "passes".
 *
 * This guard is a static reach test, not a lint on one line: the edge that crashed the runtime
 * would do so just as well one hop away, inside `scripts/test.ts` or any helper the preload
 * pulls in. It shares `runtimeImportEdges`/`resolveSpec` with the other boundary guards for the
 * reason recorded in `tests/helpers/import-graph.ts` — a second copy of the matcher cannot fail
 * when the original drifts.
 */
import { describe, expect, test } from "bun:test";
import { mkdtempSync, readFileSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { resolveSpec, runtimeImportEdges, slashed } from "../helpers/import-graph";
import { removeTreeWithRetry } from "../helpers/remove-tree";
import { repoPath } from "../helpers/repo-root";

const PRELOAD = repoPath("tests", "preload.ts");

/** A specifier the walk could not resolve to a file — every built-in arrives this way. */
interface BareEdge {
  readonly specifier: string;
  /** Entry-first chain of slash-spelled paths ending at the file that names the specifier. */
  readonly chain: readonly string[];
}

function chainTo(previous: ReadonlyMap<string, string | null>, leaf: string): string[] {
  const chain: string[] = [];
  let node: string | null = leaf;
  while (node) {
    chain.push(slashed(node));
    node = previous.get(node) ?? null;
  }
  return chain.reverse();
}

/**
 * Every bare specifier reachable from `entry` over load-time edges.
 *
 * A dynamic `import()` is skipped for the same reason the Lab boundary skips it: a deferred
 * edge is only entered if that branch runs, and deferring is the remedy rather than the defect.
 */
function bareSpecifiersReachableFrom(entry: string): BareEdge[] {
  const previous = new Map<string, string | null>([[entry, null]]);
  const queue = [entry];
  const found: BareEdge[] = [];
  while (queue.length > 0) {
    const current = queue.shift()!;
    let source: string;
    try {
      source = readFileSync(current, "utf8");
    } catch {
      continue;
    }
    for (const edge of runtimeImportEdges(source)) {
      if (edge.dynamic) continue;
      const next = resolveSpec(edge.spec, current);
      if (next === null) {
        found.push({ specifier: edge.spec, chain: chainTo(previous, current) });
        continue;
      }
      if (previous.has(next)) continue;
      previous.set(next, current);
      queue.push(next);
    }
  }
  return found;
}

describe("the bunfig preload's module graph", () => {
  test("never reaches bun:test", () => {
    const offenders = bareSpecifiersReachableFrom(PRELOAD)
      .filter(edge => edge.specifier === "bun:test")
      .map(edge => edge.chain.join(" -> "));
    // Printed as the chain so a future violation names the hop that reintroduced it rather
    // than only reporting that something, somewhere, did.
    expect(offenders).toEqual([]);
  });

  test("the preload itself declares no bun:test import", () => {
    const specifiers = runtimeImportEdges(readFileSync(PRELOAD, "utf8")).map(edge => edge.spec);
    expect(specifiers).not.toContain("bun:test");
  });

  test("the walk catches a bun:test edge introduced one hop away", () => {
    // Attack the guard rather than trust it: without this, a walker that silently stopped at
    // the first file would report the repository clean for every possible violation.
    const directory = mkdtempSync(join(tmpdir(), "ocx-preload-graph-"));
    try {
      writeFileSync(join(directory, "entry.ts"), 'import { hook } from "./hop";\nexport { hook };\n');
      writeFileSync(join(directory, "hop.ts"), 'import { afterAll } from "bun:test";\nexport const hook = afterAll;\n');
      const offenders = bareSpecifiersReachableFrom(join(directory, "entry.ts"))
        .filter(edge => edge.specifier === "bun:test");
      expect(offenders).toHaveLength(1);
      expect(offenders[0]!.chain.map(path => path.split("/").at(-1))).toEqual(["entry.ts", "hop.ts"]);
    } finally {
      removeTreeWithRetry(directory);
    }
  });

  test("the preload still reclaims its temp root through a process exit listener", () => {
    // The crash is also curable by deleting the cleanup outright, which would hand #4762 its
    // leak back. Pin the surviving mechanism so that repair cannot pass as this one.
    const source = readFileSync(PRELOAD, "utf8");
    expect(source).toContain('process.on("exit", cleanupIsolatedRoot)');
    expect(source).toMatch(/isolated\.cleanup\(/);
  });
});
