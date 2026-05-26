import { ValueView } from "../lib/value";
import type { RValue } from "../types";

export function SourcePane({
  source,
  input,
  primal,
}: {
  source: string;
  input: RValue;
  primal: RValue;
}) {
  const inputValue = input.kind === "codual" ? (input.primal as RValue) : input;
  const inputType = input.kind === "codual" ? String(input.primalType) : String(input.kind);

  return (
    <div className="rounded-lg border border-border-subtle bg-surface-1 p-3">
      <h3 className="mb-2 text-[11px] font-semibold uppercase tracking-wide text-ink-3">
        Program
      </h3>
      <dl className="space-y-1.5 text-[11px]">
        <div className="grid grid-cols-[3.5rem_minmax(0,1fr)] gap-2">
          <dt className="text-ink-3">function</dt>
          <dd className="overflow-x-auto rounded bg-surface-2 px-2 py-1.5 font-mono text-xs leading-snug text-ink">
            <pre className="whitespace-pre-wrap">{source.trimEnd()}</pre>
          </dd>
        </div>
        <div className="grid grid-cols-[3.5rem_minmax(0,1fr)] gap-2">
          <dt className="text-ink-3">input</dt>
          <dd className="break-all font-mono text-ink-2">
            <ValueView value={inputValue} />
          </dd>
        </div>
        <div className="grid grid-cols-[3.5rem_minmax(0,1fr)] gap-2">
          <dt className="text-ink-3">type</dt>
          <dd className="truncate whitespace-nowrap font-mono text-ink-2" title={inputType}>
            {inputType}
          </dd>
        </div>
        <div className="grid grid-cols-[3.5rem_minmax(0,1fr)] gap-2 border-t border-border-subtle pt-1.5">
          <dt className="text-ink-3">output</dt>
          <dd className="break-all font-mono">
            <ValueView value={primal} />
          </dd>
        </div>
      </dl>
    </div>
  );
}
