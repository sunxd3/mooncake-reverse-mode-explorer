import { ValueView } from "../lib/value";
import type { RValue } from "../types";

export function SourcePane({
  source,
  signature,
  description,
  inputs,
  primal,
}: {
  source: string;
  signature: string;
  description: string;
  inputs: Record<string, unknown>;
  primal: RValue;
}) {
  return (
    <div className="rounded-lg border border-border bg-surface-1 p-3">
      <h3 className="mb-1.5 text-[11px] font-semibold uppercase tracking-wide text-ink-3">
        Program under differentiation
      </h3>
      <pre className="overflow-x-auto rounded bg-surface-2 p-2.5 font-mono text-xs leading-relaxed text-ink">
        {source}
      </pre>
      <p className="mt-2 text-xs leading-relaxed text-ink-2">{description}</p>
      <dl className="mt-2 space-y-1 border-t border-border-subtle pt-2 text-[11px]">
        <div className="flex gap-2">
          <dt className="shrink-0 text-ink-3">signature</dt>
          <dd className="break-all font-mono text-ink-2">{signature}</dd>
        </div>
        <div className="flex gap-2">
          <dt className="shrink-0 text-ink-3">inputs</dt>
          <dd className="break-all font-mono text-ink-2">{JSON.stringify(inputs)}</dd>
        </div>
        <div className="flex gap-2">
          <dt className="shrink-0 text-ink-3">output</dt>
          <dd className="font-mono">
            <ValueView value={primal} />
          </dd>
        </div>
      </dl>
    </div>
  );
}
