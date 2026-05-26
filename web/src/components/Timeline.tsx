import { PHASE_META } from "../lib/phase";
import type { Trace } from "../types";

export function Timeline({
  trace,
  stepIndex,
  breakpoints,
  onGoto,
}: {
  trace: Trace;
  stepIndex: number;
  breakpoints: Set<number>;
  onGoto: (i: number) => void;
}) {
  const groups: { phase: Trace["steps"][number]["phase"]; start: number; end: number }[] = [];
  trace.steps.forEach((step, i) => {
    const last = groups[groups.length - 1];
    if (last && last.phase === step.phase) {
      last.end = i;
    } else {
      groups.push({ phase: step.phase, start: i, end: i });
    }
  });
  const current = trace.steps[stepIndex];

  return (
    <div className="space-y-1.5">
      <div className="flex items-center justify-between gap-3 text-[10px] font-medium text-ink-3">
        <div className="flex flex-wrap items-center gap-x-3 gap-y-1">
          {groups.map((g) => {
            const m = PHASE_META[g.phase];
            const count = g.end - g.start + 1;
            return (
              <span key={`${g.phase}-${g.start}`} className="flex items-center gap-1">
                <span className={`h-2 w-2 rounded-full ${m.dot}`} />
                {m.label} {g.start + 1}-{g.end + 1} ({count})
              </span>
            );
          })}
        </div>
        {current && (
          <div className="shrink-0 font-mono text-ink-2">
            step {stepIndex + 1} / {trace.steps.length} · {current.phase}
          </div>
        )}
      </div>
      <div className="flex h-6 overflow-hidden rounded border border-border-subtle bg-surface-2">
        {groups.map((g) => (
          <div
            key={`${g.phase}-${g.start}`}
            className="flex min-w-0 gap-px border-r border-surface-1 last:border-r-0"
            style={{ flexGrow: g.end - g.start + 1, flexBasis: 0 }}
          >
            {trace.steps.slice(g.start, g.end + 1).map((s, offset) => {
              const i = g.start + offset;
              const m = PHASE_META[s.phase];
              const active = i === stepIndex;
              return (
                <button
                  key={i}
                  onClick={() => onGoto(i)}
                  title={`#${s.index} · ${s.phase} · ${s.text}`}
                  className={`relative h-full min-w-0 flex-1 ${m.dot} transition-opacity ${
                    active
                      ? "z-10 opacity-100 ring-2 ring-inset ring-ink"
                      : "opacity-35 hover:opacity-70"
                  }`}
                >
                  {breakpoints.has(i) && (
                    <span className="absolute left-1/2 top-1 h-1 w-1 -translate-x-1/2 rounded-full bg-ink" />
                  )}
                </button>
              );
            })}
          </div>
        ))}
      </div>
    </div>
  );
}
