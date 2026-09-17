import { describe, expect, test } from "bun:test";
import { createResponsesPassthroughAdapter as createResponsesPassthroughAdapterProduction } from "../../../src/adapters/openai-responses";
import { enrichProviderFromRegistry, providerConfigSeed } from "../../../src/providers/derive";
import { getProviderRegistryEntry } from "../../../src/providers/registry";
import { routedProviderConfig } from "../../../src/router";
import type { OcxProviderConfig } from "../../../src/types";
import { withTestTranslatorBudget } from "../../helpers/translator-budget";

const MODEL = "grok-4.6";

const createResponsesPassthroughAdapter = (
  ...args: Parameters<typeof createResponsesPassthroughAdapterProduction>
) => withTestTranslatorBudget(createResponsesPassthroughAdapterProduction(...args));

function xaiOauthResponses(overrides: Partial<OcxProviderConfig> = {}): OcxProviderConfig {
  return {
    adapter: "openai-responses",
    baseUrl: "https://api.x.ai/v1",
    authMode: "oauth",
    ...overrides,
  };
}

function buildBody(provider: OcxProviderConfig, rawBody: Record<string, unknown>): Record<string, unknown> {
  const built = createResponsesPassthroughAdapter(provider).buildRequest({
    modelId: MODEL,
    context: { messages: [] },
    stream: true,
    options: {},
    _rawBody: { model: MODEL, ...rawBody },
  } as Parameters<ReturnType<typeof createResponsesPassthroughAdapter>["buildRequest"]>[0], {
    headers: new Headers(),
  });
  return JSON.parse(String(built.body)) as Record<string, unknown>;
}

describe("xAI Responses tool-result adjacency", () => {
  test("the xAI registry entry seeds adjacency without marking the provider stateless", () => {
    const entry = getProviderRegistryEntry("xai")!;
    expect(entry.requiresAdjacentResponsesToolResults).toBe(true);
    expect(entry.statelessResponses).toBeUndefined();
    const seed = providerConfigSeed(entry);
    expect(seed.requiresAdjacentResponsesToolResults).toBe(true);
    expect(seed.statelessResponses).toBeUndefined();
  });

  test("a stale persisted xAI row is backfilled and repairs a dangling function_call on replay", () => {
    const stale: OcxProviderConfig = xaiOauthResponses();
    const routedStale = routedProviderConfig("xai", { ...stale });
    const call = { type: "function_call", call_id: "call_interrupted", name: "exec_command", arguments: "{}" };
    const nextTurn = {
      type: "message",
      role: "user",
      content: [{ type: "input_text", text: "continue" }],
    };

    expect(stale.requiresAdjacentResponsesToolResults).toBeUndefined();
    expect(routedStale.requiresAdjacentResponsesToolResults).toBe(true);
    enrichProviderFromRegistry("xai", stale);
    expect(stale.requiresAdjacentResponsesToolResults).toBe(true);
    expect(stale.statelessResponses).toBeUndefined();

    const body = buildBody(stale, {
      previous_response_id: "resp_xai_store",
      store: true,
      input: [call, nextTurn],
    });
    expect(body.previous_response_id).toBe("resp_xai_store");
    expect(body.store).toBe(true);
    const input = body.input as Array<Record<string, unknown>>;
    expect(input[0]).toMatchObject({ type: "function_call", call_id: "call_interrupted" });
    expect(input[1]).toMatchObject({ type: "function_call_output", call_id: "call_interrupted" });
    expect(String(input[1].output)).toContain("no tool result was recorded");
    expect(input[2]).toMatchObject({ type: "message", role: "user" });
  });

  test("moves a result next to its call while preserving an intervening developer message", () => {
    const provider = xaiOauthResponses({ requiresAdjacentResponsesToolResults: true });
    const call = { type: "function_call", call_id: "call_exec", name: "exec_command", arguments: "{}" };
    const injected = {
      type: "message",
      role: "developer",
      content: [{ type: "input_text", text: "[hook] LSP diagnostics: none" }],
    };
    const output = { type: "function_call_output", call_id: "call_exec", output: "ok" };
    const body = buildBody(provider, { input: [call, injected, output] });
    expect(body.input).toEqual([call, output, injected]);
  });

  test("keeps call_id pairing for two outstanding replayed calls and synthesizes only the missing output", () => {
    const provider = xaiOauthResponses({ requiresAdjacentResponsesToolResults: true });
    const callA = { type: "function_call", call_id: "call_a", name: "exec_command", arguments: "{}" };
    const callB = { type: "function_call", call_id: "call_b", name: "exec_command", arguments: "{}" };
    const injected = {
      type: "message",
      role: "developer",
      content: [{ type: "input_text", text: "[hook] replay diagnostics" }],
    };
    const outputB = { type: "function_call_output", call_id: "call_b", output: "B" };
    const body = buildBody(provider, { input: [callA, callB, injected, outputB] });
    const input = body.input as Array<Record<string, unknown>>;
    expect(input[0]).toMatchObject({ type: "function_call", call_id: "call_a" });
    expect(input[1]).toMatchObject({ type: "function_call", call_id: "call_b" });
    expect(input[2]).toMatchObject({ type: "function_call_output", call_id: "call_a" });
    expect(String(input[2].output)).toContain("no tool result was recorded");
    expect(input[3]).toMatchObject({ type: "function_call_output", call_id: "call_b", output: "B" });
    expect(input[4]).toMatchObject({ type: "message", role: "developer" });
  });

  test("forward-auth xAI replay still does not synthesize a dangling call", () => {
    const provider = xaiOauthResponses({
      authMode: "forward",
      requiresAdjacentResponsesToolResults: true,
      headers: { authorization: "Bearer xai-oauth" },
    });
    const call = { type: "function_call", call_id: "call_fwd", name: "exec_command", arguments: "{}" };
    const body = buildBody(provider, { input: [call] });
    const input = body.input as Array<Record<string, unknown>>;
    expect(input).toHaveLength(1);
    expect(input[0]).toMatchObject({ type: "function_call", call_id: "call_fwd" });
    expect(JSON.stringify(body)).not.toContain("no tool result was recorded");
  });
});
