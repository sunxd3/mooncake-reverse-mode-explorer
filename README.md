# Mooncake Reverse-Mode Walkthrough

A static, debugger-style webpage that steps through **real
[Mooncake.jl](https://github.com/chalk-lab/Mooncake.jl) reverse-mode AD** — the
genuine forward- and reverse-pass `IRCode` Mooncake generates, executed one
statement at a time.

This is not a teaching mock-up. A small interpreter walks the actual un-inlined
`fwd_ir` / `rvs_ir`, dispatching every call to the real Mooncake runtime
(`rrule!!`, `increment!!`, …). The result is captured as an event-stream JSON
trace, replayed in the browser. No Julia runs at view-time.

## Layout

```
julia/      Build-time trace generator (Julia + Mooncake)
  src/        examples · stepper · ir_export · render · trace
  bin/        bake_static.jl — regenerates web/public/traces/*.json
  test/       validate.jl — 157-assertion correctness suite
web/
  src/        React + Vite viewer · lib/replay.ts reconstructs state from events
  public/
    traces/   Baked manifest + per-example event-stream JSON (served as-is)
artifacts/  IR pipeline dumps, validation notes
```

## Prerequisites

- **Node 18+** / npm (always)
- **Julia 1.10+** (only if you want to regenerate traces or run the test suite)

## Setup

```bash
npm install            # web deps only — enough to view + build the site
npm run setup          # also instantiates the Julia env (needed for bake/test)
```

## Run (static viewer)

```bash
npm run dev            # vite dev server at http://localhost:5173
```

The page loads the baked traces from `web/public/traces/`. No Julia involved.

## Regenerate traces (build-time)

```bash
npm run bake           # runs julia/bin/bake_static.jl
```

Writes `manifest.json` + `trace_*.json` to `web/public/traces/` from the current
Julia code. Re-run after adding an example or upgrading Mooncake.

## Build & deploy

```bash
BASE_PATH=/mooncake-walkthrough/ npm run build
# → web/dist/ is a fully static bundle. Drop it on GitHub Pages, Netlify, …
```

`BASE_PATH` is the public URL prefix (omit for root-served sites).

## Use

- Pick an example from the dropdown.
- Step with the controls or the keyboard: `→` / `←` step, `Space` play/pause,
  `R` reset. Click the timeline to scrub; click an IR line's gutter dot to set
  a breakpoint.
- **Load trace…** in the header (or drag-drop a JSON file onto the page) loads
  any trace JSON produced by `build_trace` — your own or someone else's.
- **?trace=<url>** query param fetches a trace from any URL and shows it.
- The **Trace** tab is the program counter over the forward / reverse IR; the
  **IR pipeline** tab shows all seven real compilation stages.

## Examples

| Example | Function | Teaches |
|---|---|---|
| Mixed scalar + vector | `foo(x) = x[1] + sum(x[2])` | fdata (address-like) vs rdata (value-like) gradients |
| In-place mutation | `bump!(c) = (c.v = c.v*c.v; c.v)` | forward mutation, captured state, reverse restore |
| Vector + scalar output | `vpair(x) = (copy(x), sum(x))` | the output cotangent splitting into an fdata half and an rdata half |

## Trace format

`{schemaVersion: 1, steps[], initialState, events[], ...}`. Steps carry
metadata only; the browser reconstructs per-step state by replaying events
(`pass_start`, `ssa_define`, `mut_set`, `stack_push`, `stack_pop`,
`step_marker`). See `web/src/types.ts` and `web/src/lib/replay.ts`.

## Validation

```bash
npm test
```

Runs `julia/test/validate.jl` — 157 assertions across 7 layers (finite-difference
ground truth, bit-exact same-IR OpaqueClosure equivalence, whole-pipeline
agreement, mutation/restore invariants, cotangent fdata/rdata splitting, …). See
[`artifacts/STAGE1_VALIDATION.md`](artifacts/STAGE1_VALIDATION.md).

## Adding an example

1. Add an `ExampleSpec` to `julia/src/examples.jl` — a function, a way to build
   its argument and its output cotangent (seed), and defaults.
2. `npm run bake` to regenerate the static traces + manifest.
3. `npm run dev` to verify.

---

Pinned to Mooncake `=0.5.29` via `julia/Project.toml`. `Mooncake.primal_ir` /
`fwd_ir` / `rvs_ir` are internal and not semver-stable, so the version is
hard-pinned.
