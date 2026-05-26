# Mooncake Reverse-Mode Explorer

A static, debugger-style webpage that steps through
[Mooncake.jl](https://github.com/chalk-lab/Mooncake.jl) reverse-mode AD — the
forward- and reverse-pass `IRCode` Mooncake generates, executed one statement
at a time.

A small interpreter walks the un-inlined `fwd_ir` / `rvs_ir`, dispatching every
call to the Mooncake runtime (`rrule!!`, `increment!!`, …). The result is
captured as an event-stream JSON trace, replayed in the browser. No Julia runs
at view-time.

The repo has two parts:

- **`MooncakeTracer/`** — a Julia package that takes a function and a type
  signature, runs Mooncake reverse-mode AD on it, and emits a JSON trace.
- **`web/`** — a static React frontend that loads a trace and replays the
  steps with their per-step state.

The two sides agree on **`schema/trace.v1.schema.json`** — the trace format.

## Run

```bash
npm install && npm run dev      # vite dev server at http://localhost:5173
```

The page loads the baked traces from `web/public/traces/`.

## Regenerate traces

```bash
npm run setup    # one-time: instantiates the Julia env
npm run bake     # rewrites web/public/traces/ from MooncakeTracer
```

Re-run `bake` after adding an example in `MooncakeTracer/src/examples.jl` or
upgrading Mooncake.

## Test

```bash
npm test
```

## Deploy

Pushes to `main` build and deploy via `.github/workflows/pages.yml`. Hosted at
`https://<owner>.github.io/mooncake-explorer/`.
