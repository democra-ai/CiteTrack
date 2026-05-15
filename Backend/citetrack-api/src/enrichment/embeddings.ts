import type { Ai } from "@cloudflare/workers-types";

const EMBED_MODEL = "@cf/baai/bge-base-en-v1.5";
const BATCH_SIZE = 100;

export async function embedTexts(ai: Ai, texts: string[]): Promise<number[][]> {
  const results: number[][] = [];
  for (let i = 0; i < texts.length; i += BATCH_SIZE) {
    const batch = texts.slice(i, i + BATCH_SIZE);
    const cleaned = batch.map((t) => (t && t.trim().length > 0 ? t.slice(0, 2000) : "empty"));
    const resp = (await withTimeout(
      ai.run(EMBED_MODEL, { text: cleaned }),
      20000,
      "ai.run(embed)"
    )) as { data: number[][] };
    if (!resp?.data) {
      throw new Error("Embedding response missing data");
    }
    results.push(...resp.data);
  }
  return results;
}

function withTimeout<T>(p: Promise<T>, ms: number, label: string): Promise<T> {
  return new Promise<T>((resolve, reject) => {
    const timer = setTimeout(() => reject(new Error(`${label} timed out after ${ms}ms`)), ms);
    p.then((v) => {
      clearTimeout(timer);
      resolve(v);
    }).catch((e) => {
      clearTimeout(timer);
      reject(e);
    });
  });
}
