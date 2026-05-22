import { useEffect, useState } from "react";
import type { IRStage } from "../types";

export function IRStageViewer({
  stages,
  activeStage,
}: {
  stages: IRStage[];
  /** the stage currently being stepped — selected by default */
  activeStage: "fwd_ir" | "rvs_ir";
}) {
  const [selected, setSelected] = useState<string>(activeStage);

  useEffect(() => {
    setSelected(activeStage);
  }, [activeStage]);

  const stage = stages.find((s) => s.id === selected) ?? stages[0];

  return (
    <div className="flex h-full flex-col">
      <div className="mb-2 flex flex-wrap gap-1">
        {stages.map((s) => (
          <button
            key={s.id}
            onClick={() => setSelected(s.id)}
            title={`${s.blockCount} blocks · ${s.instCount} statements`}
            className={`rounded px-2 py-1 text-[11px] font-medium transition-colors ${
              s.id === selected
                ? "bg-accent text-white"
                : s.stepped
                  ? "bg-accent-soft text-accent hover:bg-surface-3"
                  : "bg-surface-2 text-ink-2 hover:bg-surface-3"
            }`}
          >
            {s.title}
          </button>
        ))}
      </div>
      {stage && (
        <>
          <div className="mb-1 text-[11px] text-ink-3">
            {stage.blockCount} basic blocks · {stage.instCount} statements
            {stage.stepped && " · stepped in the debugger"}
          </div>
          <pre className="flex-1 overflow-auto rounded border border-border-subtle bg-surface-2 p-2.5 font-mono text-[11px] leading-relaxed text-ink">
            {stage.text}
          </pre>
        </>
      )}
    </div>
  );
}
