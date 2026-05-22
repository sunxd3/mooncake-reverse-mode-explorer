// Editable numeric field widgets, shared by the input editor and the seed panel.
import { useEffect, useState } from "react";
import type { InputSpec } from "../types";

function parseVector(text: string): number[] | null {
  const trimmed = text.trim();
  if (trimmed === "") return [];
  const parts = trimmed.split(/[,\s]+/);
  const nums = parts.map(Number);
  return nums.some((n) => Number.isNaN(n)) ? null : nums;
}

export function ScalarField({
  value,
  onChange,
}: {
  value: number;
  onChange: (v: number) => void;
}) {
  return (
    <input
      type="number"
      step="any"
      value={value}
      onChange={(e) => onChange(Number(e.target.value))}
      className="w-20 rounded border border-border bg-surface-1 px-2 py-1 font-mono text-xs outline-none focus:border-accent"
    />
  );
}

export function VectorField({
  value,
  onChange,
}: {
  value: number[];
  onChange: (v: number[]) => void;
}) {
  const [text, setText] = useState(value.join(", "));
  const [bad, setBad] = useState(false);

  // Re-sync when the value changes externally (example switch / reset / a
  // server-coerced seed vector).
  useEffect(() => {
    setText(value.join(", "));
    setBad(false);
  }, [value]);

  return (
    <input
      value={text}
      onChange={(e) => {
        setText(e.target.value);
        const parsed = parseVector(e.target.value);
        if (parsed) {
          setBad(false);
          onChange(parsed);
        } else {
          setBad(true);
        }
      }}
      spellCheck={false}
      className={`w-44 rounded border bg-surface-1 px-2 py-1 font-mono text-xs outline-none focus:border-accent ${
        bad ? "border-bad" : "border-border"
      }`}
      placeholder="1, 2, 3"
    />
  );
}

/** Renders a scalar or vector field according to an `InputSpec`'s `kind`. */
export function EditableField({
  spec,
  value,
  onChange,
}: {
  spec: InputSpec;
  value: number | number[] | undefined;
  onChange: (v: number | number[]) => void;
}) {
  return spec.kind === "scalar" ? (
    <ScalarField value={(value as number) ?? 0} onChange={onChange} />
  ) : (
    <VectorField value={(value as number[]) ?? []} onChange={onChange} />
  );
}
