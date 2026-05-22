// The output cotangent ȳ: an editable seed plus its fdata / rdata split.
//
// The split happens between the forward and reverse passes — Mooncake's
// `__value_and_pullback!!` does `increment!!(tangent(out), fdata(ȳ))` and then
// passes `rdata(ȳ)` to the reverse pass. It is not a statement in either
// stepped IR, so this panel surfaces it alongside the trace.
import type { CotangentSplit, ExampleManifest, RValue } from "../types";
import { ValueView } from "../lib/value";
import { EditableField } from "./fields";

export function SeedPanel({
  example,
  seed,
  setSeedInput,
  split,
}: {
  example: ExampleManifest;
  seed: Record<string, number | number[]>;
  setSeedInput: (name: string, value: number | number[]) => void;
  split: CotangentSplit;
}) {
  return (
    <div className="rounded-lg border border-border bg-surface-1 p-3">
      <h3 className="mb-2 text-[11px] font-semibold uppercase tracking-wide text-ink-3">
        Output cotangent ȳ
      </h3>

      <div className="space-y-2">
        {example.seedInputs.map((spec) => (
          <div key={spec.name} className="flex flex-col gap-1">
            <span className="text-[11px] font-medium text-ink-2">
              {spec.label}
            </span>
            <EditableField
              spec={spec}
              value={seed[spec.name]}
              onChange={(v) => setSeedInput(spec.name, v)}
            />
          </div>
        ))}
      </div>

      <div className="mt-3 border-t border-border-subtle pt-2">
        <p className="mb-1 text-[11px] leading-snug text-ink-3">
          <span className="font-mono text-ink-2">ȳ :: {split.outputType}</span>
          {" — "}like every Mooncake tangent, the cotangent splits into an{" "}
          <span className="font-medium text-accent">fdata</span> half (a buffer,
          address-like) and an{" "}
          <span className="font-medium text-reverse">rdata</span> half (a value).
        </p>
        <SplitRow
          tag="fdata"
          tagClass="bg-accent-soft text-accent"
          value={split.fdata}
          note="increment!! ▸ output CoDual's buffer"
        />
        <SplitRow
          tag="rdata"
          tagClass="bg-reverse-soft text-reverse"
          value={split.rdata}
          note="▸ passed to the reverse pass as _2"
        />
      </div>
    </div>
  );
}

function SplitRow({
  tag,
  tagClass,
  value,
  note,
}: {
  tag: string;
  tagClass: string;
  value: RValue;
  note: string;
}) {
  return (
    <div className="mt-1.5">
      <div className="flex items-baseline gap-1.5 text-xs">
        <span
          className={`shrink-0 rounded px-1 py-px text-[10px] font-semibold ${tagClass}`}
        >
          {tag}
        </span>
        <span className="break-all font-mono">
          <ValueView value={value} />
        </span>
      </div>
      <div className="ml-[2.6rem] text-[10px] text-ink-3">{note}</div>
    </div>
  );
}
