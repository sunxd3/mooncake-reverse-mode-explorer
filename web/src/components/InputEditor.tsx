import { RotateCcw } from "lucide-react";
import type { ExampleManifest } from "../types";
import { EditableField } from "./fields";

export function InputEditor({
  example,
  inputs,
  setInput,
  onReset,
}: {
  example: ExampleManifest;
  inputs: Record<string, number | number[]>;
  setInput: (name: string, value: number | number[]) => void;
  onReset: () => void;
}) {
  return (
    <div className="flex flex-wrap items-center gap-x-4 gap-y-2">
      {example.inputs.map((spec) => (
        <label key={spec.name} className="flex items-center gap-1.5 text-xs">
          <span className="font-medium text-ink-2">{spec.label}</span>
          <EditableField
            spec={spec}
            value={inputs[spec.name]}
            onChange={(v) => setInput(spec.name, v)}
          />
        </label>
      ))}
      <button
        onClick={onReset}
        title="Reset inputs and seed to defaults"
        className="flex items-center gap-1 rounded border border-border bg-surface-1 px-2 py-1 text-xs text-ink-2 hover:bg-surface-2"
      >
        <RotateCcw size={12} />
        Defaults
      </button>
    </div>
  );
}
