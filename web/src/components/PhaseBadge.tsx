import { PHASE_META } from "../lib/phase";
import type { Phase } from "../types";

export function PhaseBadge({
  phase,
  size = "md",
}: {
  phase: Phase;
  size?: "sm" | "md";
}) {
  const m = PHASE_META[phase];
  return (
    <span
      className={`inline-flex items-center gap-1.5 rounded-full font-semibold tracking-wide ${m.bg} ${m.text} ${
        size === "sm" ? "px-2 py-0.5 text-[10px]" : "px-3 py-1 text-xs"
      }`}
    >
      <span className={`h-1.5 w-1.5 rounded-full ${m.dot}`} />
      {m.label}
    </span>
  );
}
