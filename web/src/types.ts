// Mirrors /schema/trace.v1.schema.json — the canonical trace format. Keep in
// sync. The Julia emitter (MooncakeWalkthrough/src/events.jl) implements the
// same spec.

/** A rendered Julia value — a tagged union produced by `render.jl`. */
export type RValue = { kind: string } & Record<string, unknown>;

export interface NamedValue {
  name: string;
  value: RValue;
}

/** One statement of a stepped IR stage. */
export interface IRStmt {
  index: number;
  block: number;
  blockStart: boolean;
  ssaId: string | null;
  defines: boolean;
  kind: string;
  text: string;
  type: string;
}

/** A single argument value with display metadata. Lives on `World.args` and
 * inside `pass_start` events. */
export interface ArgValue {
  id: string;
  role: string;
  value: RValue;
}

/** Per-step world reconstructed by replaying the event stream. Shape matches
 * what the snapshot model used to emit per step, so UI consumers see the same
 * data they did before linearization. */
export interface DebuggerState {
  ssa: { id: string; value: RValue }[];
  args: ArgValue[];
  tape: RValue[];
  input: RValue;
}

export type Phase = "forward" | "reverse" | "restore";

export interface TraceStep {
  index: number;
  phase: Phase;
  stage: "fwd_ir" | "rvs_ir";
  pc: number;
  block: number;
  ssaId: string | null;
  kind: string;
  text: string;
  type: string;
  mutatesPrimal: boolean;
  explanation: string;
  produced: RValue | null;
}

/** Identifies one of the four kinds of tracked roots an event can mutate. */
export type Root =
  | { kind: "input" }
  | { kind: "arg"; index: number }
  | { kind: "tape"; index: number }
  | { kind: "ssa"; pc: number };

/** Named field (string) or 0-based index (number) into the rendered tree. */
export type PathComponent = string | number;

export type TraceEvent =
  | { t: "pass_start"; pass: "forward" | "reverse"; args: ArgValue[] }
  | { t: "ssa_define"; pc: number; value: RValue }
  | { t: "mut_set"; root: Root; path: PathComponent[]; value: RValue }
  | { t: "stack_push"; root: Root; path: PathComponent[]; value: RValue }
  | { t: "stack_pop"; root: Root; path: PathComponent[] }
  | { t: "step_marker"; stepIndex: number };

export interface InitialState {
  input: RValue;
  tape: RValue[];
}

export interface IRStage {
  id: string;
  title: string;
  text: string;
  blockCount: number;
  instCount: number;
  stepped: boolean;
}

export interface TraceCheck {
  name: string;
  passed: boolean;
  got?: number[];
  want?: number[];
  error?: string;
}

export interface TraceResult {
  primalValue: RValue;
  gradient: RValue;
  checks: TraceCheck[];
}

/** Editable numeric fields, keyed by name — used for both inputs and the seed. */
export type ValueMap = Record<string, number | number[]>;

/**
 * The output cotangent ȳ and its decomposition. Every Mooncake tangent splits
 * into an fdata half (address-like, seeded into a buffer) and an rdata half
 * (value-like, passed to the reverse pass as `_2`).
 */
export interface CotangentSplit {
  outputType: string;
  output: RValue;
  fdata: RValue;
  rdata: RValue;
}

export interface Trace {
  schemaVersion: number;
  exampleId: string;
  title: string;
  description: string;
  source: string;
  signature: string;
  inputs: Record<string, unknown>;
  seed: ValueMap;
  cotangentSplit: CotangentSplit;
  irStages: IRStage[];
  steppedStages: { fwd_ir: IRStmt[]; rvs_ir: IRStmt[] };
  steps: TraceStep[];
  initialState: InitialState;
  events: TraceEvent[];
  counts: { forward: number; reverse: number; total: number };
  result: TraceResult;
}

export interface InputSpec {
  name: string;
  kind: "scalar" | "vector";
  label: string;
}

export interface ExampleManifest {
  id: string;
  title: string;
  description: string;
  source: string;
  defaultSeed: ValueMap;
  defaultInputs: ValueMap;
  inputs: InputSpec[];
  seedInputs: InputSpec[];
}
