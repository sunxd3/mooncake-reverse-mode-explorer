import { ArrowRight, Pencil } from "lucide-react";
import { PhaseBadge } from "./PhaseBadge";
import { ValueView } from "../lib/value";
import { KIND_LABEL, PHASE_META } from "../lib/phase";
import type { TraceStep } from "../types";

export function InstructionPane({ step }: { step: TraceStep }) {
  const m = PHASE_META[step.phase];
  const stageName = step.stage === "fwd_ir" ? "forward-pass IR" : "reverse-pass IR";
  const kindLabel = KIND_LABEL[step.kind] ?? step.kind;

  return (
    <div
      className={`rounded-lg border border-l-4 border-border bg-surface-1 shadow-sm ${m.border}`}
    >
      <div className="flex flex-wrap items-center gap-2 px-4 pt-3">
        <PhaseBadge phase={step.phase} />
        <span className="font-mono text-xs text-ink-3">
          step {step.index} · {stageName} · %pc {step.pc}
        </span>
        {kindLabel && (
          <span className={`rounded px-1.5 py-0.5 text-[10px] font-semibold ${m.bg} ${m.text}`}>
            {kindLabel}
          </span>
        )}
        {step.mutatesPrimal && (
          <span className="flex items-center gap-1 rounded bg-restore-soft px-1.5 py-0.5 text-[10px] font-semibold text-restore">
            <Pencil size={10} />
            mutates primal
          </span>
        )}
      </div>

      <div className="px-4 py-3">
        <code className="block break-all font-mono text-[17px] font-medium leading-snug text-ink">
          {step.text}
        </code>
      </div>

      {step.explanation && (
        <p className="px-4 pb-3 text-sm leading-relaxed text-ink-2">
          {step.explanation}
        </p>
      )}

      {step.produced && (
        <div className="flex items-center gap-2 border-t border-border-subtle px-4 py-2.5 font-mono text-sm">
          <ArrowRight size={14} className="shrink-0 text-ink-3" />
          {step.ssaId && <span className="text-ink-3">{step.ssaId} =</span>}
          <span className="break-all">
            <ValueView value={step.produced} />
          </span>
        </div>
      )}
    </div>
  );
}
