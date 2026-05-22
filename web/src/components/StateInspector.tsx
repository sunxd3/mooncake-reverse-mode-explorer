import { ValueView } from "../lib/value";
import type { RValue, TraceStep } from "../types";

function Row({
  label,
  sub,
  value,
  changed,
  stepIndex,
  emphasis = false,
}: {
  label: string;
  sub?: string;
  value: RValue;
  changed: boolean;
  stepIndex: number;
  emphasis?: boolean;
}) {
  return (
    <div
      key={changed ? `${label}@${stepIndex}` : label}
      className={`flex gap-2 rounded px-1.5 py-1 ${changed ? "cell-flash" : ""} ${
        emphasis ? "bg-surface-2" : ""
      }`}
    >
      <span className="w-9 shrink-0 font-mono text-xs font-semibold text-ink-3">
        {label}
      </span>
      <div className="min-w-0 flex-1">
        {sub && <div className="text-[10px] text-ink-3">{sub}</div>}
        <div className="break-all font-mono text-xs leading-relaxed">
          <ValueView value={value} />
        </div>
      </div>
    </div>
  );
}

function Section({ title, children }: { title: string; children: React.ReactNode }) {
  return (
    <div>
      <h3 className="mb-1 text-[11px] font-semibold uppercase tracking-wide text-ink-3">
        {title}
      </h3>
      <div className="space-y-0.5">{children}</div>
    </div>
  );
}

export function StateInspector({
  step,
  prevStep,
  stepIndex,
}: {
  step: TraceStep;
  prevStep: TraceStep | null;
  stepIndex: number;
}) {
  const prevSsa = new Map(
    (prevStep?.state.ssa ?? []).map((e) => [e.id, JSON.stringify(e.value)]),
  );
  const prevInput = prevStep ? JSON.stringify(prevStep.state.input) : null;

  return (
    <div className="space-y-4">
      <Section title="Differentiated argument — CoDual">
        <Row
          label="x"
          sub="primal value · ∂ tangent (fdata)"
          value={step.state.input}
          changed={prevInput !== null && prevInput !== JSON.stringify(step.state.input)}
          stepIndex={stepIndex}
          emphasis
        />
      </Section>

      <Section title="IR arguments">
        {step.state.args.map((a) => (
          <Row
            key={a.id}
            label={a.id}
            sub={a.role}
            value={a.value}
            changed={false}
            stepIndex={stepIndex}
          />
        ))}
      </Section>

      <Section title={`SSA registers · ${step.state.ssa.length}`}>
        {step.state.ssa.length === 0 && (
          <div className="px-1.5 text-xs italic text-ink-3">none defined yet</div>
        )}
        {step.state.ssa.map((e) => {
          const now = JSON.stringify(e.value);
          const before = prevSsa.get(e.id);
          return (
            <Row
              key={e.id}
              label={e.id}
              value={e.value}
              changed={before === undefined || before !== now}
              stepIndex={stepIndex}
            />
          );
        })}
      </Section>
    </div>
  );
}
