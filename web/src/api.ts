import type { ExampleManifest, Trace } from "./types";

const STATIC_BASE = `${import.meta.env.BASE_URL}traces`;

/** Fetch the example manifest baked into web/public/traces/manifest.json. */
export async function fetchExamples(): Promise<ExampleManifest[]> {
  const res = await fetch(`${STATIC_BASE}/manifest.json`);
  if (!res.ok) throw new Error(`Could not load examples (HTTP ${res.status}).`);
  const data = await res.json();
  return data.examples as ExampleManifest[];
}

/** Fetch a baked trace by example id. */
export async function fetchTrace(exampleId: string, signal?: AbortSignal): Promise<Trace> {
  const res = await fetch(`${STATIC_BASE}/trace_${exampleId}.json`, { signal });
  if (!res.ok) throw new Error(`Trace not found (HTTP ${res.status}).`);
  return (await res.json()) as Trace;
}

/** Load a trace from an arbitrary URL (used by ?trace=<url>). */
export async function fetchTraceFromUrl(url: string, signal?: AbortSignal): Promise<Trace> {
  const res = await fetch(url, { signal });
  if (!res.ok) throw new Error(`Could not load trace from ${url} (HTTP ${res.status}).`);
  return (await res.json()) as Trace;
}
