import { Layers } from "lucide-react";
import { ValueView } from "../lib/value";
import type { DebuggerState, RValue } from "../types";

export function TapeInspector({
  state,
  prevState,
}: {
  state: DebuggerState;
  prevState: DebuggerState | null;
}) {
  const tape = state.tape;
  const prevTape = prevState?.tape ?? [];

  return (
    <div>
      <h3 className="mb-1 flex items-center gap-1.5 text-[11px] font-semibold uppercase tracking-wide text-ink-3">
        <Layers size={12} />
        Tape — captured pullback stacks
      </h3>
      {tape.length === 0 && (
        <div className="text-xs italic text-ink-3">no stacks</div>
      )}
      <div className="space-y-1.5">
        {tape.map((stack: RValue, i) => {
          const size = (stack.size as number) ?? 0;
          const changed = JSON.stringify(stack) !== JSON.stringify(prevTape[i]);
          return (
            <div
              key={i}
              className={`rounded border border-border-subtle bg-surface-2 px-2 py-1.5 ${
                changed ? "cell-flash" : ""
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
    </div>
  );
}
