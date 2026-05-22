import { Check, X } from "lucide-react";
import { ValueView } from "../lib/value";
import type { Trace } from "../types";

export function ResultPanel({ trace }: { trace: Trace }) {
  const r = trace.result;
  return (
    <div className="rounded-lg border border-border bg-surface-1 p-3">
      <h3 className="mb-2 text-[11px] font-semibold uppercase tracking-wide text-ink-3">
        Result
      </h3>
      <dl className="space-y-1.5 text-xs">
        <div className="flex items-baseline gap-2">
          <dt className="w-24 shrink-0 text-ink-3">primal output</dt>
          <dd className="font-mono">
            <ValueView value={r.primalValue} />
          </dd>
        </div>
        <div className="flex items-baseline gap-2">
          <dt className="w-24 shrink-0 font-semibold text-ink">gradient</dt>
          <dd className="break-all rounded bg-accent-soft px-1.5 py-0.5 font-mono font-medium">
            <ValueView value={r.gradient} />
          </dd>
        </div>
      </dl>

      <div className="mt-3 space-y-1 border-t border-border-subtle pt-2">
        {r.checks.map((c, i) => (
          <div key={i} className="flex items-start gap-1.5 text-[11px]">
            {c.passed ? (
              <Check size={13} className="mt-px shrink-0 text-ok" />
            ) : (
              <X size={13} className="mt-px shrink-0 text-bad" />
            )}
            <span className={c.passed ? "text-ink-2" : "text-bad"}>
              {c.name}
              {c.error && <span className="block font-mono">{c.error}</span>}
            </span>
          </div>
        ))}
      </div>
    </div>
  );
}
