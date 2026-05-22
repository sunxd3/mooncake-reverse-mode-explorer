import type { ExampleManifest, Trace, ValueMap } from "./types";

export async function fetchExamples(): Promise<ExampleManifest[]> {
  const res = await fetch("/api/examples");
  if (!res.ok) throw new Error(`Could not load examples (HTTP ${res.status}).`);
  const data = await res.json();
  return data.examples as ExampleManifest[];
}

export async function fetchTrace(
  exampleId: string,
  inputs: Record<string, unknown>,
  seed: ValueMap,
  signal?: AbortSignal,
): Promise<Trace> {
  const res = await fetch("/api/trace", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ exampleId, inputs, seed }),
    signal,
  });
  const data = await res.json();
  if (!res.ok) {
    throw new Error(data?.error ?? `Trace request failed (HTTP ${res.status}).`);
  }
  return data as Trace;
}
