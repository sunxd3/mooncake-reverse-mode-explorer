import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { fetchExamples, fetchTrace } from "../api";
import type { ExampleManifest, Trace, TraceStep } from "../types";

const PLAY_INTERVAL_MS = 850;

type Status = "init" | "loading" | "ready" | "error";
type Inputs = Record<string, number | number[]>;

export interface DebuggerApi {
  examples: ExampleManifest[];
  example: ExampleManifest | null;
  exampleId: string;
  selectExample: (id: string) => void;

  inputs: Inputs;
  setInput: (name: string, value: number | number[]) => void;
  seed: Inputs;
  setSeedInput: (name: string, value: number | number[]) => void;
  resetInputs: () => void;

  trace: Trace | null;
  status: Status;
  error: string | null;

  stepIndex: number;
  goto: (i: number) => void;
  step: TraceStep | null;
  stepForward: () => void;
  stepBack: () => void;
  reset: () => void;

  isPlaying: boolean;
  togglePlay: () => void;

  breakpoints: Set<number>;
  toggleBreakpoint: (i: number) => void;
}

export function useDebugger(): DebuggerApi {
  const [examples, setExamples] = useState<ExampleManifest[]>([]);
  const [exampleId, setExampleId] = useState<string>("");
  const [inputs, setInputs] = useState<Inputs>({});
  // The output cotangent (seed), keyed like `inputs`. For a scalar output it is
  // a single `dy`; for a structured output it has one field per cotangent leaf.
  const [seed, setSeed] = useState<Inputs>({});

  const [trace, setTrace] = useState<Trace | null>(null);
  const [status, setStatus] = useState<Status>("init");
  const [error, setError] = useState<string | null>(null);

  const [stepIndex, setStepIndex] = useState(0);
  const [isPlaying, setIsPlaying] = useState(false);
  const [breakpoints, setBreakpoints] = useState<Set<number>>(new Set());

  const example = useMemo(
    () => examples.find((e) => e.id === exampleId) ?? null,
    [examples, exampleId],
  );

  // --- load the example manifest once (retry while Julia is still booting) --
  useEffect(() => {
    let cancelled = false;
    const load = (attempt: number) => {
      fetchExamples()
        .then((list) => {
          if (cancelled) return;
          setExamples(list);
          if (list.length > 0) {
            setExampleId(list[0].id);
            setInputs({ ...list[0].defaultInputs });
            setSeed({ ...list[0].defaultSeed });
          }
        })
        .catch((e) => {
          if (cancelled) return;
          if (attempt < 40) {
            window.setTimeout(() => load(attempt + 1), 2000);
          } else {
            setStatus("error");
            setError(`${e.message} — is the Julia trace server running?`);
          }
        });
    };
    load(0);
    return () => {
      cancelled = true;
    };
  }, []);

  // --- switching example resets its inputs ---------------------------------
  const selectExample = useCallback(
    (id: string) => {
      const ex = examples.find((e) => e.id === id);
      if (!ex) return;
      setExampleId(id);
      setInputs({ ...ex.defaultInputs });
      setSeed({ ...ex.defaultSeed });
      setIsPlaying(false);
      setBreakpoints(new Set());
    },
    [examples],
  );

  const resetInputs = useCallback(() => {
    if (example) {
      setInputs({ ...example.defaultInputs });
      setSeed({ ...example.defaultSeed });
    }
  }, [example]);

  const setInput = useCallback((name: string, value: number | number[]) => {
    setInputs((prev) => ({ ...prev, [name]: value }));
  }, []);

  const setSeedInput = useCallback((name: string, value: number | number[]) => {
    setSeed((prev) => ({ ...prev, [name]: value }));
  }, []);

  // --- (debounced) trace fetch when example / inputs / seed change ---------
  const reqId = useRef(0);
  const inputsKey = JSON.stringify(inputs);
  // Order-insensitive: avoids spurious refetches if key order ever differs.
  const seedKey = JSON.stringify(seed, Object.keys(seed).sort());
  useEffect(() => {
    if (!example) return;
    // Skip transient states where inputs / seed don't yet match the example.
    if (!example.inputs.every((spec) => spec.name in inputs)) return;
    if (!example.seedInputs.every((spec) => spec.name in seed)) return;

    const myReq = ++reqId.current;
    const controller = new AbortController();
    const timer = window.setTimeout(() => {
      setStatus("loading");
      fetchTrace(example.id, inputs, seed, controller.signal)
        .then((t) => {
          if (myReq !== reqId.current) return;
          setTrace(t);
          setStatus("ready");
          setError(null);
          setStepIndex((i) => Math.min(i, Math.max(0, t.steps.length - 1)));
          // The server may coerce the seed (e.g. resize a cotangent vector to
          // match the input vector). Adopt its effective seed so the editor
          // stays in sync; this settles in one extra fetch (the fit is idempotent).
          if (JSON.stringify(t.seed, Object.keys(t.seed).sort()) !== seedKey) {
            setSeed(t.seed);
          }
        })
        .catch((e) => {
          if (myReq !== reqId.current || e.name === "AbortError") return;
          setStatus("error");
          setError(e.message);
        });
    }, 280);
    return () => {
      window.clearTimeout(timer);
      controller.abort();
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [example, inputsKey, seedKey]);

  // --- stepping ------------------------------------------------------------
  const total = trace?.steps.length ?? 0;
  const goto = useCallback(
    (i: number) => setStepIndex(Math.max(0, Math.min(i, Math.max(0, total - 1)))),
    [total],
  );
  const stepForward = useCallback(
    () => setStepIndex((i) => Math.min(i + 1, Math.max(0, total - 1))),
    [total],
  );
  const stepBack = useCallback(() => setStepIndex((i) => Math.max(0, i - 1)), []);
  const reset = useCallback(() => {
    setStepIndex(0);
    setIsPlaying(false);
  }, []);
  const togglePlay = useCallback(() => {
    if (total === 0) return;
    setIsPlaying((p) => {
      if (!p && stepIndex >= total - 1) setStepIndex(0);
      return !p;
    });
  }, [total, stepIndex]);

  // --- play loop (one timeout per step; stops at end / breakpoints) --------
  useEffect(() => {
    if (!isPlaying || total === 0) return;
    if (stepIndex >= total - 1) {
      setIsPlaying(false);
      return;
    }
    const id = window.setTimeout(() => {
      const next = stepIndex + 1;
      setStepIndex(next);
      if (breakpoints.has(next)) setIsPlaying(false);
    }, PLAY_INTERVAL_MS);
    return () => window.clearTimeout(id);
  }, [isPlaying, stepIndex, total, breakpoints]);

  const toggleBreakpoint = useCallback((i: number) => {
    setBreakpoints((prev) => {
      const next = new Set(prev);
      next.has(i) ? next.delete(i) : next.add(i);
      return next;
    });
  }, []);

  // --- keyboard shortcuts --------------------------------------------------
  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      const el = e.target as HTMLElement;
      if (el && (el.tagName === "INPUT" || el.tagName === "TEXTAREA")) return;
      if (e.key === "ArrowRight") {
        e.preventDefault();
        stepForward();
      } else if (e.key === "ArrowLeft") {
        e.preventDefault();
        stepBack();
      } else if (e.key === " ") {
        e.preventDefault();
        togglePlay();
      } else if (e.key === "r" || e.key === "R") {
        e.preventDefault();
        reset();
      }
    };
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [stepForward, stepBack, togglePlay, reset]);

  const step = trace && total > 0 ? trace.steps[stepIndex] : null;

  return {
    examples,
    example,
    exampleId,
    selectExample,
    inputs,
    setInput,
    seed,
    setSeedInput,
    resetInputs,
    trace,
    status,
    error,
    stepIndex,
    goto,
    step,
    stepForward,
    stepBack,
    reset,
    isPlaying,
    togglePlay,
    breakpoints,
    toggleBreakpoint,
  };
}
