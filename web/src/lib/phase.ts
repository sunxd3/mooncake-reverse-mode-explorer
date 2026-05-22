import type { Phase } from "../types";

export const PHASE_META: Record<
  Phase,
  { label: string; text: string; bg: string; dot: string; border: string }
> = {
  forward: {
    label: "FORWARD",
    text: "text-forward",
    bg: "bg-forward-soft",
    dot: "bg-forward",
    border: "border-forward",
  },
  reverse: {
    label: "REVERSE",
    text: "text-reverse",
    bg: "bg-reverse-soft",
    dot: "bg-reverse",
    border: "border-reverse",
  },
  restore: {
    label: "RESTORE",
    text: "text-restore",
    bg: "bg-restore-soft",
    dot: "bg-restore",
    border: "border-restore",
  },
};

/** Tailwind class for the small coloured tag shown next to each IR-statement kind. */
export const KIND_LABEL: Record<string, string> = {
  rrule: "rrule",
  increment: "accumulate",
  "pullback-call": "pullback",
  "shared-data": "captures",
  wrap: "wrap",
  getfield: "unpack",
  setfield: "store",
  tuple: "bundle",
  push: "tape push",
  pop: "tape pop",
  typeassert: "assert",
  rdata: "rdata",
  new: "alloc",
  "return": "return",
  goto: "goto",
  phi: "φ",
  nop: "nop",
  const: "const",
  pi: "π",
  call: "call",
  other: "",
};
