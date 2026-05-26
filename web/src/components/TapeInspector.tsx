import { useState } from "react";
import { ChevronDown, ChevronRight, Layers } from "lucide-react";
import { ValueView } from "../lib/value";
import type { DebuggerState, RValue } from "../types";

export function TapeInspector({
  state,
  prevState,
}: {
  state: DebuggerState;
  prevState: DebuggerState | null;
}) {
  const [expanded, setExpanded] = useState(false);
  const tape = state.tape;
  const prevTape = prevState?.tape ?? [];
  const depths = tape.map((stack) => (stack.size as number) ?? 0);
  const totalDepth = depths.reduce((acc, n) => acc + n, 0);

  return (
    <div>
      <button
        onClick={() => setExpanded((v) => !v)}
        className="flex w-full items-center justify-between gap-2 text-left"
        title="Show captured pullback stacks"
      >
        <span className="flex items-center gap-1.5 text-[11px] font-semibold uppercase tracking-wide text-ink-3">
          <Layers size={12} />
          Tape
        </span>
        <span className="flex items-center gap-1.5 text-[11px] text-ink-3">
          {tape.length} stack{tape.length === 1 ? "" : "s"} · depth {totalDepth}
          {expanded ? <ChevronDown size={13} /> : <ChevronRight size={13} />}
        </span>
      </button>
      {tape.length === 0 && (
        <div className="mt-1 text-xs italic text-ink-3">no stacks</div>
      )}
      {!expanded && tape.length > 0 && (
        <div className="mt-1 truncate font-mono text-[11px] text-ink-3">
          {depths.map((depth, i) => `s${i + 1}:${depth}`).join(" · ")}
        </div>
      )}
      {expanded && (
        <div className="mt-2 space-y-1.5">
          {tape.map((stack: RValue, i) => {
            const size = (stack.size as number) ?? 0;
            const changed =
              prevState !== null &&
              JSON.stringify(stack) !== JSON.stringify(prevTape[i]);
            return (
              <div
                key={i}
                className={`rounded border px-2 py-1.5 ${
                  changed
                    ? "border-forward/30 bg-forward-soft"
                    : "border-border-subtle bg-surface-0"
                }`}
              >
                <div className="mb-0.5 text-[10px] font-medium text-ink-3">
                  stack {i + 1} · depth {size}
                </div>
                <div className="break-all font-mono text-xs">
                  <ValueView value={stack} />
                </div>
              </div>
            );
          })}
        </div>
      )}
    </div>
  );
}
