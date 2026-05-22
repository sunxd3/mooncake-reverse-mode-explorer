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
  return (
    <div className="flex items-center gap-3">
      <div className="flex flex-1 items-stretch gap-px overflow-hidden rounded">
        {trace.steps.map((s, i) => {
          const m = PHASE_META[s.phase];
          const active = i === stepIndex;
          return (
            <button
              key={i}
              onClick={() => onGoto(i)}
              title={`#${s.index} · ${s.phase} · ${s.text}`}
              className={`relative h-6 flex-1 ${m.dot} transition-opacity ${
                active ? "opacity-100" : "opacity-35 hover:opacity-70"
              }`}
            >
              {active && (
                <span className="absolute inset-x-0 -top-1 mx-auto h-1.5 w-1.5 rounded-full bg-ink" />
              )}
              {breakpoints.has(i) && (
                <span className="absolute left-1/2 top-0.5 h-1 w-1 -translate-x-1/2 rounded-full bg-ink" />
              )}
            </button>
          );
        })}
      </div>
      <div className="flex shrink-0 items-center gap-3 text-[10px] font-medium text-ink-3">
        {(["forward", "reverse", "restore"] as const).map((p) => (
          <span key={p} className="flex items-center gap-1">
            <span className={`h-2 w-2 rounded-full ${PHASE_META[p].dot}`} />
            {PHASE_META[p].label}
          </span>
        ))}
      </div>
    </div>
  );
}
