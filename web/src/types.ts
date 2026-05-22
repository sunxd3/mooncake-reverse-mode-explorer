// Types mirroring the JSON emitted by the Julia trace service.

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

export interface DebuggerState {
  ssa: { id: string; value: RValue }[];
  args: { id: string; role: string; value: RValue }[];
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
  state: DebuggerState;
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
