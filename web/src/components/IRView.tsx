import { useEffect, useRef } from "react";
import { PHASE_META } from "../lib/phase";
import type { Trace } from "../types";

export function IRView({
  trace,
  stage,
  stepIndex,
  breakpoints,
  onGoto,
  onToggleBreakpoint,
}: {
  trace: Trace;
  stage: "fwd_ir" | "rvs_ir";
  stepIndex: number;
  breakpoints: Set<number>;
  onGoto: (i: number) => void;
  onToggleBreakpoint: (i: number) => void;
}) {
  const steps = trace.steps.filter((s) => s.stage === stage);
  const activeRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    activeRef.current?.scrollIntoView({ block: "nearest", behavior: "smooth" });
  }, [stepIndex, stage]);

  let prevBlock = -1;

  return (
    <div className="font-mono text-xs">
      {steps.map((s) => {
        const gi = s.index - 1; // global step-array index
        const active = gi === stepIndex;
        const done = gi < stepIndex;
        const m = PHASE_META[s.phase];
        const newBlock = s.block !== prevBlock;
        prevBlock = s.block;
        return (
          <div key={s.index}>
            {newBlock && (
              <div className="mt-1 px-2 pb-0.5 pt-1 text-[10px] font-semibold uppercase tracking-wide text-ink-3">
                block #{s.block}
              </div>
            )}
            <div
              ref={active ? activeRef : undefined}
              onClick={() => onGoto(gi)}
              className={`flex cursor-pointer items-start gap-1 rounded px-1 py-[3px] ${
                active
                  ? `${m.bg} ${m.text} font-medium`
                  : done
                    ? "text-ink-2 hover:bg-surface-2"
                    : "text-ink-3 hover:bg-surface-2"
              }`}
            >
              <button
                onClick={(e) => {
                  e.stopPropagation();
                  onToggleBreakpoint(gi);
                }}
                title="Toggle breakpoint"
                className="mt-[1px] flex h-3.5 w-3.5 shrink-0 items-center justify-center"
              >
                <span
                  className={`h-2 w-2 rounded-full ${
                    breakpoints.has(gi)
                      ? "bg-bad"
                      : "bg-transparent ring-1 ring-border hover:ring-ink-3"
                  }`}
                />
              </button>
              <span className="w-3 shrink-0 select-none text-center">
                {active ? "▸" : ""}
              </span>
              <code className="whitespace-pre-wrap break-all">{s.text}</code>
            </div>
          </div>
        );
      })}
    </div>
  );
}
