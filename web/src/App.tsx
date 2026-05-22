import { useState } from "react";
import { AlertTriangle, Loader2 } from "lucide-react";
import { useDebugger } from "./state/useDebugger";
import { ExamplePicker } from "./components/ExamplePicker";
import { InputEditor } from "./components/InputEditor";
import { DebuggerControls } from "./components/DebuggerControls";
import { Timeline } from "./components/Timeline";
import { InstructionPane } from "./components/InstructionPane";
import { IRView } from "./components/IRView";
import { SourcePane } from "./components/SourcePane";
import { StateInspector } from "./components/StateInspector";
import { TapeInspector } from "./components/TapeInspector";
import { SeedPanel } from "./components/SeedPanel";
import { ResultPanel } from "./components/ResultPanel";
import { IRStageViewer } from "./components/IRStageViewer";
import { NotesPanel } from "./components/NotesPanel";

export function App() {
  const dbg = useDebugger();
  const [leftTab, setLeftTab] = useState<"trace" | "pipeline">("trace");

  const { trace, step, stepIndex } = dbg;
  const prevStep =
    trace && stepIndex > 0 ? trace.steps[stepIndex - 1] : null;
  const activeStage: "fwd_ir" | "rvs_ir" = step?.stage ?? "fwd_ir";

  return (
    <div className="flex h-screen flex-col overflow-hidden">
      {/* ---- header ---- */}
      <header className="flex items-center justify-between border-b border-border bg-surface-1 px-4 py-2.5">
        <div className="flex items-baseline gap-3">
          <h1 className="text-sm font-semibold text-ink">
            Mooncake Reverse-Mode Walkthrough
          </h1>
          <span className="text-xs text-ink-3">
            stepping real Mooncake AD IR
          </span>
        </div>
        {dbg.examples.length > 0 && (
          <ExamplePicker
            examples={dbg.examples}
            current={dbg.exampleId}
            onSelect={dbg.selectExample}
          />
        )}
      </header>

      {/* ---- toolbar ---- */}
      <div className="flex flex-wrap items-center justify-between gap-3 border-b border-border bg-surface-1 px-4 py-2">
        {dbg.example && (
          <InputEditor
            example={dbg.example}
            inputs={dbg.inputs}
            setInput={dbg.setInput}
            onReset={dbg.resetInputs}
          />
        )}
        <div className="flex items-center gap-3">
          {dbg.status === "loading" && (
            <span className="flex items-center gap-1 text-xs text-ink-3">
              <Loader2 size={12} className="animate-spin" />
              re-running Mooncake…
            </span>
          )}
          <DebuggerControls
            stepIndex={dbg.stepIndex}
            total={trace?.steps.length ?? 0}
            isPlaying={dbg.isPlaying}
            onReset={dbg.reset}
            onBack={dbg.stepBack}
            onForward={dbg.stepForward}
            onTogglePlay={dbg.togglePlay}
          />
        </div>
      </div>

      {/* ---- timeline ---- */}
      {trace && (
        <div className="border-b border-border bg-surface-1 px-4 py-2">
          <Timeline
            trace={trace}
            stepIndex={dbg.stepIndex}
            breakpoints={dbg.breakpoints}
            onGoto={dbg.goto}
          />
        </div>
      )}

      {/* ---- error banner ---- */}
      {dbg.status === "error" && (
        <div className="flex items-center gap-2 border-b border-bad bg-red-50 px-4 py-2 text-sm text-bad">
          <AlertTriangle size={15} />
          {dbg.error}
        </div>
      )}

      {/* ---- main ---- */}
      {!trace || !step ? (
        <div className="flex flex-1 items-center justify-center text-sm text-ink-3">
          {dbg.status === "error" ? (
            "Could not load a trace."
          ) : (
            <span className="flex items-center gap-2">
              <Loader2 size={16} className="animate-spin" />
              Generating the first trace — the Julia server is compiling
              Mooncake…
            </span>
          )}
        </div>
      ) : (
        <main className="grid flex-1 grid-cols-[20rem_minmax(0,1fr)_22rem] gap-3 overflow-hidden p-3">
          {/* left column */}
          <div className="flex min-h-0 flex-col gap-3 overflow-hidden">
            <SourcePane
              source={trace.source}
              signature={trace.signature}
              description={trace.description}
              inputs={trace.inputs}
              primal={trace.result.primalValue}
            />
            <div className="flex min-h-0 flex-1 flex-col rounded-lg border border-border bg-surface-1">
              <div className="flex gap-1 border-b border-border-subtle p-1.5">
                <TabButton
                  active={leftTab === "trace"}
                  onClick={() => setLeftTab("trace")}
                >
                  Trace ({activeStage === "fwd_ir" ? "forward" : "reverse"})
                </TabButton>
                <TabButton
                  active={leftTab === "pipeline"}
                  onClick={() => setLeftTab("pipeline")}
                >
                  IR pipeline
                </TabButton>
              </div>
              <div className="min-h-0 flex-1 overflow-auto p-2">
                {leftTab === "trace" ? (
                  <IRView
                    trace={trace}
                    stage={activeStage}
                    stepIndex={dbg.stepIndex}
                    breakpoints={dbg.breakpoints}
                    onGoto={dbg.goto}
                    onToggleBreakpoint={dbg.toggleBreakpoint}
                  />
                ) : (
                  <IRStageViewer
                    stages={trace.irStages}
                    activeStage={activeStage}
                  />
                )}
              </div>
            </div>
          </div>

          {/* center column */}
          <div className="flex min-h-0 flex-col gap-3 overflow-y-auto pr-1">
            <InstructionPane step={step} />
            <div className="rounded-lg border border-border bg-surface-1 p-3">
              <StateInspector
                step={step}
                prevStep={prevStep}
                stepIndex={dbg.stepIndex}
              />
            </div>
          </div>

          {/* right column */}
          <div className="flex min-h-0 flex-col gap-3 overflow-y-auto pr-1">
            <div className="rounded-lg border border-border bg-surface-1 p-3">
              <TapeInspector step={step} prevStep={prevStep} />
            </div>
            {dbg.example && (
              <SeedPanel
                example={dbg.example}
                seed={dbg.seed}
                setSeedInput={dbg.setSeedInput}
                split={trace.cotangentSplit}
              />
            )}
            <ResultPanel trace={trace} />
            <NotesPanel />
          </div>
        </main>
      )}
    </div>
  );
}

function TabButton({
  active,
  onClick,
  children,
}: {
  active: boolean;
  onClick: () => void;
  children: React.ReactNode;
}) {
  return (
    <button
      onClick={onClick}
      className={`rounded px-2.5 py-1 text-xs font-medium transition-colors ${
        active ? "bg-accent text-white" : "text-ink-2 hover:bg-surface-2"
      }`}
    >
      {children}
    </button>
  );
}
