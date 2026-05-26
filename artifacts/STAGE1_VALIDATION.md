# Stage 1 Validation

The explorer teaches from 100+ intermediate steps, so validating only the
final gradient is not enough. `julia/test/validate.jl` runs **154 assertions**
across 7 layers, over all three examples and a spread of inputs.

| Layer | What it checks | Why it matters |
|---|---|---|
| **A** Independent ground truth | central finite differences + hand-derived analytic gradients (`foo`→`(1,ones)`, `bump!`→`2v`) | the math is actually right — not just "agrees with Mooncake" |
| **B** Same-IR equivalence | compile OpaqueClosures (`misty_closure`) from the **exact un-inlined IR the interpreter steps**, run them, compare **bit-exact** | isolates interpreter bugs from any inlining question |
| **C** Whole-pipeline | compare to the real `build_rrule` / `value_and_pullback!!` (the pullback API works for any output shape) | un-inlined IR is semantically equal to the optimised rule |
| **D** Mutation / restore | post-forward `Cell.v == v²`; post-reverse `Cell.v == v`; `foo`/`vpair` primals never move | the trace's mutation story is real |
| **E** Trace structure | contiguous step indices; SSA count monotonic; output CoDual carries `f(x)`; every `restore` step is a primal-moving reverse step | snapshot + classification correctness |
| **F** Input independence | IR text + step counts identical for every numeric input of a signature | the assumption editable inputs rely on |
| **G** Seed linearity | `seed=k` gradient `== k ×` `seed=1` gradient | seed handling |

**Layer B is the keystone.** `misty_closure` successfully compiles the same
un-inlined `fwd_ir`/`rvs_ir` the interpreter walks; the interpreter's output is
bit-identical to that compiled closure's. Any interpreter bug (operand
resolution, CFG/φ handling, `:new`, the `get_shared_data_field` intercept) would
surface here with no "but inlining" escape hatch.

**Example 3 (`vpair`) exercises the output-side cotangent split.** Its output
is a `Tuple{Vector{Float64}, Float64}`, so the cotangent ȳ has a non-trivial
fdata half (the vector) *and* rdata half (the scalar). `fdata(ȳ)` / `rdata(ȳ)`
are asserted directly, and the interpreter seeds the fdata half into the output
CoDual's buffer with `increment!!` — exactly as Mooncake's own
`__value_and_pullback!!` does — before running the reverse pass on `rdata(ȳ)`.

Run: `julia julia/test/validate.jl` — exits non-zero on any failure, so it works
as the Stage 1 acceptance gate.
