import type { RValue } from "../types";

/** Format a Julia number for display. */
export function fmtNum(value: unknown, isInt = false): string {
  if (typeof value === "string") return value; // Inf / NaN
  if (typeof value !== "number") return String(value);
  if (isInt) return String(value);
  if (Number.isInteger(value)) return `${value}.0`;
  const s = value.toPrecision(7);
  return s.includes(".") ? s.replace(/0+$/, "").replace(/\.$/, ".0") : s;
}

/** A compact one-line summary of a value (for dense rows / step headers). */
export function summarize(v: RValue | null | undefined): string {
  if (!v) return "—";
  switch (v.kind) {
    case "number":
      return fmtNum(v.value, v.int as boolean);
    case "bool":
      return String(v.value);
    case "nothing":
      return "nothing";
    case "none":
      return String(v.name);
    case "symbol":
      return `:${v.value}`;
    case "string":
      return `"${v.value}"`;
    case "type":
      return String(v.name);
    case "val":
      return `Val(${summarize(v.value as RValue)})`;
    case "fn":
      return String(v.name);
    case "codual":
      return `CoDual(${summarize(v.primal as RValue)})`;
    case "vector":
    case "array":
      return `[${(v.items as RValue[]).map(summarize).join(", ")}]`;
    case "tuple":
      return `(${(v.items as RValue[]).map(summarize).join(", ")})`;
    case "ref":
      return `Ref(${summarize(v.value as RValue)})`;
    case "stack":
      return `Stack[${v.size}]`;
    case "tangent":
      return `∂(${(v.fields as { name: string; value: RValue }[])
        .map((f) => `${f.name}=${summarize(f.value)}`)
        .join(", ")})`;
    case "pullback":
      return `↩ ${v.name ?? v.type}`;
    case "struct":
      return String(v.type);
    default:
      return v.kind;
  }
}

function Punct({ children }: { children: string }) {
  return <span className="text-ink-3">{children}</span>;
}

function FieldList({
  fields,
}: {
  fields: { name: string; value: RValue }[];
}) {
  return (
    <span>
      {fields.map((f, i) => (
        <span key={f.name}>
          {i > 0 && <Punct>, </Punct>}
          <span className="text-ink-2">{f.name}</span>
          <Punct>=</Punct>
          <ValueView value={f.value} />
        </span>
      ))}
    </span>
  );
}

/** Recursive renderer for a rendered Julia value. */
export function ValueView({ value: v }: { value: RValue }): React.ReactElement {
  switch (v.kind) {
    case "number":
      return (
        <span className="text-emerald-700">{fmtNum(v.value, v.int as boolean)}</span>
      );
    case "bool":
      return <span className="text-emerald-700">{String(v.value)}</span>;
    case "nothing":
      return <span className="text-ink-3 italic">nothing</span>;
    case "undef":
      return <span className="text-ink-3 italic">#undef</span>;
    case "none":
      return (
        <span className="text-ink-3 italic" title="a zero / empty gradient marker">
          {String(v.name)}
        </span>
      );
    case "symbol":
      return <span className="text-rose-700">:{String(v.value)}</span>;
    case "string":
      return <span className="text-amber-700">"{String(v.value)}"</span>;
    case "type":
      return <span className="text-sky-700">{String(v.name)}</span>;
    case "fn":
      return <span className="text-sky-700">{String(v.name)}</span>;
    case "val":
      return (
        <span>
          <span className="text-sky-700">Val</span>
          <Punct>(</Punct>
          <ValueView value={v.value as RValue} />
          <Punct>)</Punct>
        </span>
      );
    case "vector":
    case "array": {
      const items = v.items as RValue[];
      return (
        <span>
          <Punct>[</Punct>
          {items.map((it, i) => (
            <span key={i}>
              {i > 0 && <Punct>, </Punct>}
              <ValueView value={it} />
            </span>
          ))}
          <Punct>]</Punct>
        </span>
      );
    }
    case "tuple": {
      const items = v.items as RValue[];
      return (
        <span>
          <Punct>(</Punct>
          {items.map((it, i) => (
            <span key={i}>
              {i > 0 && <Punct>, </Punct>}
              <ValueView value={it} />
            </span>
          ))}
          <Punct>)</Punct>
        </span>
      );
    }
    case "namedtuple":
      return (
        <span>
          <Punct>(</Punct>
          <FieldList fields={v.fields as { name: string; value: RValue }[]} />
          <Punct>)</Punct>
        </span>
      );
    case "ref":
      return (
        <span>
          <span className="text-sky-700">Ref</span>
          <Punct>(</Punct>
          <ValueView value={v.value as RValue} />
          <Punct>)</Punct>
        </span>
      );
    case "codual":
      return (
        <span className="inline-flex items-baseline gap-1 rounded bg-surface-2 px-1">
          <span className="text-[10px] font-semibold tracking-wide text-ink-3">
            CoDual
          </span>
          <ValueView value={v.primal as RValue} />
          <span className="text-ink-3" title="tangent (fdata)">
            ·∂
          </span>
          <span className="text-accent">
            <ValueView value={v.tangent as RValue} />
          </span>
        </span>
      );
    case "tangent":
      return (
        <span>
          <span className="text-accent" title={v.mutable ? "mutable tangent" : "tangent"}>
            ∂
          </span>
          <Punct>(</Punct>
          <FieldList fields={v.fields as { name: string; value: RValue }[]} />
          <Punct>)</Punct>
        </span>
      );
    case "stack": {
      const items = v.items as RValue[];
      return (
        <span>
          <span className="text-sky-700" title="tape — a stack shared by both passes">
            Stack
          </span>
          <Punct>[</Punct>
          {items.length === 0 ? (
            <span className="text-ink-3 italic">empty</span>
          ) : (
            items.map((it, i) => (
              <span key={i}>
                {i > 0 && <Punct>, </Punct>}
                <ValueView value={it} />
              </span>
            ))
          )}
          <Punct>]</Punct>
        </span>
      );
    }
    case "pullback":
      return (
        <span
          className="rounded bg-reverse-soft px-1 text-reverse"
          title="a pullback closure captured on the tape"
        >
          ↩ {String(v.name ?? v.type)}
        </span>
      );
    case "struct":
      return (
        <span>
          <span className="text-sky-700">{String(v.type)}</span>
          <Punct>(</Punct>
          <FieldList fields={v.fields as { name: string; value: RValue }[]} />
          <Punct>)</Punct>
        </span>
      );
    case "elided":
      return <span className="text-ink-3" title={String(v.type)}>…</span>;
    case "opaque":
      return (
        <span className="text-ink-3" title={String(v.repr)}>
          {String(v.type)}
        </span>
      );
    default:
      return <span className="text-ink-3">{v.kind}</span>;
  }
}
