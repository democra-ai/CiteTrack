import type { Ai } from "@cloudflare/workers-types";

// Cloudflare Workers AI pricing (USD per 1M tokens), 2026.
const PRICE = {
  // @cf/meta/llama-3.3-70b-instruct-fp8-fast
  llamaInputPerM: 0.293,
  llamaOutputPerM: 2.253,
  // @cf/baai/bge-base-en-v1.5
  bgeInputPerM: 0.067,
};

export interface UsageSummary {
  llmCalls: number;
  embedCalls: number;
  llmPromptTokens: number;
  llmCompletionTokens: number;
  embedTokens: number;
  costUSD: number;
  costInputUSD: number;
  costOutputUSD: number;
  costEmbedUSD: number;
}

interface AiRunUsage {
  prompt_tokens?: number;
  completion_tokens?: number;
  total_tokens?: number;
}

/**
 * Transparent wrapper around the Workers AI binding that accumulates token
 * usage and computes cost. Tools call `.run()` exactly as before.
 */
export class TrackedAi {
  llmCalls = 0;
  embedCalls = 0;
  llmPromptTokens = 0;
  llmCompletionTokens = 0;
  embedTokens = 0;

  constructor(private readonly ai: Ai) {}

  // Mirrors Ai.run — tools only use this method.
  run = async (model: string, options: Record<string, unknown>): Promise<unknown> => {
    const resp = (await (this.ai as unknown as { run: (m: string, o: unknown) => Promise<unknown> }).run(
      model,
      options
    )) as { usage?: AiRunUsage } | undefined;

    const isEmbed = model.includes("bge") || model.includes("embed");
    const usage = resp?.usage;

    if (isEmbed) {
      this.embedCalls++;
      if (usage?.prompt_tokens) {
        this.embedTokens += usage.prompt_tokens;
      } else {
        // bge often omits usage — estimate from input text length (~4 chars/token).
        const text = (options as { text?: string | string[] }).text;
        const chars = Array.isArray(text)
          ? text.reduce((s, t) => s + (t?.length ?? 0), 0)
          : (text?.length ?? 0);
        this.embedTokens += Math.ceil(chars / 4);
      }
    } else {
      this.llmCalls++;
      this.llmPromptTokens += usage?.prompt_tokens ?? 0;
      this.llmCompletionTokens += usage?.completion_tokens ?? 0;
    }
    return resp;
  };

  summary(): UsageSummary {
    const costInputUSD = (this.llmPromptTokens / 1_000_000) * PRICE.llamaInputPerM;
    const costOutputUSD = (this.llmCompletionTokens / 1_000_000) * PRICE.llamaOutputPerM;
    const costEmbedUSD = (this.embedTokens / 1_000_000) * PRICE.bgeInputPerM;
    return {
      llmCalls: this.llmCalls,
      embedCalls: this.embedCalls,
      llmPromptTokens: this.llmPromptTokens,
      llmCompletionTokens: this.llmCompletionTokens,
      embedTokens: this.embedTokens,
      costInputUSD: round6(costInputUSD),
      costOutputUSD: round6(costOutputUSD),
      costEmbedUSD: round6(costEmbedUSD),
      costUSD: round6(costInputUSD + costOutputUSD + costEmbedUSD),
    };
  }

  /** Cast to the Ai type for passing into tools that expect the binding. */
  asAi(): Ai {
    return this as unknown as Ai;
  }
}

function round6(n: number): number {
  return Math.round(n * 1_000_000) / 1_000_000;
}
