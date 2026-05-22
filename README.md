# Mooncake Reverse-Mode Walkthrough

An interactive, debugger-style webpage that steps through **real
[Mooncake.jl](https://github.com/chalk-lab/Mooncake.jl) reverse-mode AD** — the
genuine forward- and reverse-pass `IRCode` Mooncake generates, executed one
statement at a time.

This is not a teaching mock-up. A small interpreter walks the actual un-inlined
`fwd_ir` / `rvs_ir`, dispatching every call to the real Mooncake runtime
(`rrule!!`, `increment!!`, …). The web app is a viewer over the resulting trace.

## Layout

```
julia/      Julia trace service — extracts the IR, interprets it, serves JSON
  src/        examples · stepper (the interpreter) · ir_export · trace · server
  test/       validate.jl — 154-assertion correctness suite
web/        React + Vite debugger UI (light theme)
vendor/     Mooncake.jl v0.5.29 (vendored, pinned)
artifacts/  IR dumps, sample traces, validation notes
```

## Prerequisites

- **Julia 1.12+** (developed against 1.12.5)
- **Node 18+** / npm

## Setup (once)

```bash
npm run setup
```

This instantiates the Julia environment (develops the vendored Mooncake, adds
`HTTP`/`JSON3`) and installs the web dependencies.

## Run

```bash
npm run dev
```

Starts the Julia trace server and the Vite dev server together, then open
**http://localhost:5173**. The first request waits a few seconds while Julia
compiles Mooncake; the UI shows a notice until it is ready.

## Use

- Pick an example, edit the input values or the output seed `dy` — the trace
  re-runs through real Mooncake.
- Step with the controls or the keyboard: `→` / `←` step, `Space` play/pause,
  `R` reset. Click the timeline to scrub; click an IR line's gutter dot to set a
  breakpoint.
- The **Trace** tab is the program counter over the forward / reverse IR; the
  **IR pipeline** tab shows all seven real compilation stages.

## Examples

| Example | Function | Teaches |
|---|---|---|
| Mixed scalar + vector | `foo(x) = x[1] + sum(x[2])` | fdata (address-like) vs rdata (value-like) gradients |
| In-place mutation | `bump!(c) = (c.v = c.v*c.v; c.v)` | forward mutation, captured state, reverse restore |
| Vector + scalar output | `vpair(x) = (copy(x), sum(x))` | the output cotangent splitting into an fdata half and an rdata half |

## Validation

```bash
npm test
```

Runs `julia/test/validate.jl` — 154 assertions across 7 layers (finite-difference
ground truth, bit-exact same-IR OpaqueClosure equivalence, whole-pipeline
agreement, mutation/restore invariants, cotangent fdata/rdata splitting, …). See
[`artifacts/STAGE1_VALIDATION.md`](artifacts/STAGE1_VALIDATION.md).

## Adding an example

Add an `ExampleSpec` to `julia/src/examples.jl` — a function, a way to build its
argument and its output cotangent (seed) from named inputs, and defaults.
Everything else (IR extraction, interpretation, the UI) is data-driven.

---

Pinned to Julia 1.12.5 · Mooncake v0.5.29. `Mooncake.primal_ir` / `fwd_ir` /
`rvs_ir` are internal and not semver-stable, so the Mooncake version is vendored.
