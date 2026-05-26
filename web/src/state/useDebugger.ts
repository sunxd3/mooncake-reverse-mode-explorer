import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { fetchExamples, fetchTrace, fetchTraceFromUrl } from "../api";
import { buildWorlds, worldToDebuggerState } from "../lib/replay";
import type { DebuggerState, ExampleManifest, Trace, TraceStep } from "../types";

const PLAY_INTERVAL_MS = 850;

type Status = "init" | "loading" | "ready" | "error";

export interface DebuggerApi {
  examples: ExampleManifest[];
  example: ExampleManifest | null;
  exampleId: string;
  selectExample: (id: string) => void;

  trace: Trace | null;
  status: Status;
  error: string | null;
  /** Replace the current trace with a user-supplied one (drag-drop / URL). */
  loadTrace: (t: Trace, label?: string) => void;
  /** Display label for a user-loaded trace, or null when on a baked example. */
  loadedLabel: string | null;

  stepIndex: number;
  goto: (i: number) => void;
  step: TraceStep | null;
  state: DebuggerState | null;
  prevState: DebuggerState | null;
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

  const [trace, setTrace] = useState<Trace | null>(null);
  const [status, setStatus] = useState<Status>("init");
  const [error, setError] = useState<string | null>(null);
  const [loadedLabel, setLoadedLabel] = useState<string | null>(null);

  const [stepIndex, setStepIndex] = useState(0);
  const [isPlaying, setIsPlaying] = useState(false);
  const [breakpoints, setBreakpoints] = useState<Set<number>>(new Set());

  const example = useMemo(
    () => examples.find((e) => e.id === exampleId) ?? null,
    [examples, exampleId],
  );

  // --- load examples + optionally a trace from ?trace=<url> ----------------
  useEffect(() => {
    let cancelled = false;
    fetchExamples()
      .then((list) => {
        if (cancelled) return;
        setExamples(list);
        if (list.length > 0) setExampleId(list[0].id);
        const params = new URLSearchParams(window.location.search);
        const traceUrl = params.get("trace");
        if (traceUrl) {
          setStatus("loading");
          fetchTraceFromUrl(traceUrl)
            .then((t) => {
              if (cancelled) return;
              setTrace(t);
              setLoadedLabel(traceUrl);
              setStatus("ready");
              setError(null);
              setStepIndex(0);
            })
            .catch((e) => {
              if (cancelled) return;
              setStatus("error");
              setError(`?trace= load failed: ${e.message}`);
            });
        }
      })
      .catch((e) => {
        if (cancelled) return;
        setStatus("error");
        setError(e.message);
      });
    return () => {
      cancelled = true;
    };
  }, []);

  // --- switching example reloads its baked trace ---------------------------
  const selectExample = useCallback((id: string) => {
    setExampleId(id);
    setIsPlaying(false);
    setBreakpoints(new Set());
    setLoadedLabel(null);
  }, []);

  // --- load a user-supplied trace (drag-drop, file picker, ?trace=) -------
  const loadTrace = useCallback((t: Trace, label?: string) => {
    if (t.schemaVersion !== 1) {
      setStatus("error");
      setError(`Unsupported trace schemaVersion: ${t.schemaVersion}`);
      return;
    }
    setTrace(t);
    setLoadedLabel(label ?? t.exampleId);
    setStepIndex(0);
    setIsPlaying(false);
    setBreakpoints(new Set());
    setStatus("ready");
    setError(null);
  }, []);

  // --- fetch baked trace whenever the selected example changes -------------
  const reqId = useRef(0);
  useEffect(() => {
    if (!exampleId || loadedLabel) return;
    const myReq = ++reqId.current;
    const controller = new AbortController();
    setStatus("loading");
    fetchTrace(exampleId, controller.signal)
      .then((t) => {
        if (myReq !== reqId.current) return;
        setTrace(t);
        setStatus("ready");
        setError(null);
        setStepIndex((i) => Math.min(i, Math.max(0, t.steps.length - 1)));
      })
      .catch((e) => {
        if (myReq !== reqId.current || e.name === "AbortError") return;
        setStatus("error");
        setError(e.message);
      });
    return () => controller.abort();
  }, [exampleId, loadedLabel]);

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

  const worlds = useMemo(
    () => (trace ? buildWorlds(trace.initialState, trace.events) : null),
    [trace],
  );
  const state = worlds && total > 0 ? worldToDebuggerState(worlds[stepIndex]) : null;
  const prevState =
    worlds && stepIndex > 0 ? worldToDebuggerState(worlds[stepIndex - 1]) : null;

  return {
    examples,
    example,
    exampleId,
    selectExample,
    trace,
    status,
    error,
    loadTrace,
    loadedLabel,
    stepIndex,
    goto,
    step,
    state,
    prevState,
    stepForward,
    stepBack,
    reset,
    isPlaying,
    togglePlay,
    breakpoints,
    toggleBreakpoint,
  };
}
