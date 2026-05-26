// Replay an event stream into per-step worlds.
//
// The trace JSON ships an `initialState` and a flat `events` list (see
// `julia/src/trace.jl`). One world is captured at every `step_marker`. Worlds
// use structural sharing: a `mut_set` rebuilds only the spine of the mutated
// path, so unchanged subtrees keep their object identity across steps. That
// makes `JSON.stringify(prev.X) === JSON.stringify(curr.X)` cheap for the
// cell-flash highlighting in `StateInspector`/`TapeInspector`.

import type {
  ArgValue,
  DebuggerState,
  InitialState,
  PathComponent,
  RValue,
  Root,
  TraceEvent,
} from "../types";

export interface World {
  ssa: ReadonlyMap<number, RValue>;
  args: readonly ArgValue[];
  tape: readonly RValue[];
  input: RValue;
}

export function buildWorlds(initial: InitialState, events: TraceEvent[]): World[] {
  let input: RValue = initial.input;
  let tape: readonly RValue[] = initial.tape;
  let args: readonly ArgValue[] = [];
  let ssa: ReadonlyMap<number, RValue> = new Map();
  const worlds: World[] = [];

  for (const e of events) {
    switch (e.t) {
      case "pass_start":
        args = e.args;
        ssa = new Map();
        break;
      case "ssa_define": {
        const next = new Map(ssa);
        next.set(e.pc, e.value);
        ssa = next;
        break;
      }
      case "mut_set": {
        const value = e.value;
        ({ input, args, tape, ssa } = applyAtRoot(
          { input, args, tape, ssa },
          e.root,
          e.path,
          () => value,
        ));
        break;
      }
      case "stack_push": {
        const item = e.value;
        ({ input, args, tape, ssa } = applyAtRoot(
          { input, args, tape, ssa },
          e.root,
          e.path,
          (stk) => {
            const items = (stk.items as RValue[]).concat([item]);
            return { kind: "stack", size: items.length, items };
          },
        ));
        break;
      }
      case "stack_pop":
        ({ input, args, tape, ssa } = applyAtRoot(
          { input, args, tape, ssa },
          e.root,
          e.path,
          (stk) => {
            const items = (stk.items as RValue[]).slice(0, -1);
            return { kind: "stack", size: items.length, items };
          },
        ));
        break;
      case "step_marker":
        worlds.push({ ssa, args, tape, input });
        break;
    }
  }
  return worlds;
}

/** Project a World into the legacy DebuggerState shape consumed by the UI. */
export function worldToDebuggerState(w: World): DebuggerState {
  const ssa = Array.from(w.ssa.entries())
    .sort(([a], [b]) => a - b)
    .map(([pc, value]) => ({ id: `%${pc}`, value }));
  return {
    ssa,
    args: w.args.map((a) => ({ id: a.id, role: a.role, value: a.value })),
    tape: w.tape.slice(),
    input: w.input,
  };
}

interface MutableWorld {
  input: RValue;
  args: readonly ArgValue[];
  tape: readonly RValue[];
  ssa: ReadonlyMap<number, RValue>;
}

function applyAtRoot(
  w: MutableWorld,
  root: Root,
  path: PathComponent[],
  f: (prev: RValue) => RValue,
): MutableWorld {
  switch (root.kind) {
    case "input":
      return { ...w, input: setAtPath(w.input, path, f) };
    case "arg": {
      const args = w.args.slice();
      const old = args[root.index];
      args[root.index] = { ...old, value: setAtPath(old.value, path, f) };
      return { ...w, args };
    }
    case "tape": {
      const tape = w.tape.slice();
      tape[root.index] = setAtPath(tape[root.index], path, f);
      return { ...w, tape };
    }
    case "ssa": {
      const ssa = new Map(w.ssa);
      const old = ssa.get(root.pc);
      if (old !== undefined) ssa.set(root.pc, setAtPath(old, path, f));
      return { ...w, ssa };
    }
  }
}

function setAtPath(value: RValue, path: PathComponent[], f: (prev: RValue) => RValue): RValue {
  if (path.length === 0) return f(value);
  const [head, ...rest] = path;
  if (typeof head === "string") {
    const k = value.kind;
    if (k === "codual") {
      const inner = value[head] as RValue;
      return { ...value, [head]: setAtPath(inner, rest, f) };
    }
    if (k === "tangent" || k === "namedtuple" || k === "struct") {
      const fields = (value.fields as { name: string; value: RValue }[]).map((fld) =>
        fld.name === head ? { name: fld.name, value: setAtPath(fld.value, rest, f) } : fld,
      );
      return { ...value, fields };
    }
    if (k === "ref") {
      const inner = value.value as RValue;
      return { ...value, value: setAtPath(inner, rest, f) };
    }
    throw new Error(`unexpected string path component '${head}' for kind '${k}'`);
  }
  const items = (value.items as RValue[]).slice();
  items[head] = setAtPath(items[head], rest, f);
  return { ...value, items };
}
