import { BadgeCheck } from "lucide-react";

export function NotesPanel() {
  return (
    <div className="rounded-lg border border-border bg-surface-1 p-3 text-xs leading-relaxed text-ink-2">
      <h3 className="mb-1.5 flex items-center gap-1.5 text-[11px] font-semibold uppercase tracking-wide text-ink-3">
        <BadgeCheck size={13} />
        About this trace
      </h3>
      <p>
        This is <strong className="text-ink">real Mooncake IR</strong>, not a
        teaching mock-up. The forward and reverse passes are the genuine
        un-inlined <code className="font-mono">IRCode</code> Mooncake generates
        for reverse-mode AD, executed one statement at a time by an interpreter
        that dispatches every call to the real Mooncake runtime
        (<code className="font-mono">rrule!!</code>,{" "}
        <code className="font-mono">increment!!</code>, …).
      </p>
      <p className="mt-1.5">
        Every step's gradient is cross-checked against Mooncake's own{" "}
        <code className="font-mono">value_and_gradient!!</code>. Pinned to Julia
        1.12.5 · Mooncake v0.5.29.
      </p>
      <div className="mt-2 flex flex-wrap gap-x-3 gap-y-1 border-t border-border-subtle pt-2 text-[11px] text-ink-3">
        <span>
          <kbd className="font-mono text-ink-2">→</kbd> step
        </span>
        <span>
          <kbd className="font-mono text-ink-2">←</kbd> back
        </span>
        <span>
          <kbd className="font-mono text-ink-2">Space</kbd> play/pause
        </span>
        <span>
          <kbd className="font-mono text-ink-2">R</kbd> reset
        </span>
      </div>
    </div>
  );
}
