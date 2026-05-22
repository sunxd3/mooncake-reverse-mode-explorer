# Stage 0 Findings — Real Mooncake IR Extraction

Environment: Julia 1.12.5, Mooncake v0.5.29 (vendored at `vendor/Mooncake.jl`).

## IR extraction works

`Mooncake.SkillUtils.inspect_ir(f, args...; mode=:reverse)` yields all 7 stages:
`:raw → :normalized → :bbcode → :fwd_ir → :rvs_ir → :optimized_fwd → :optimized_rvs`.

The step-worthy IR is the **un-inlined** `fwd_ir` / `rvs_ir`, obtained directly via:

```julia
interp = Mooncake.get_interpreter(Mooncake.ReverseMode)
dri = Mooncake.generate_ir(interp, sig; do_inline=false, do_optimize=false)
# dri.fwd_ir :: IRCode, dri.rvs_ir :: IRCode, dri.shared_data :: Tuple
```

`optimized_*` stages explode (loops/rules inlined: foo → 148/46, etc.) — show them
in the IR-stage viewer, but **step through the un-inlined `fwd_ir`/`rvs_ir`**.

## Final example functions

| Example | Function | Signature | fwd_ir | rvs_ir | Teaches |
|---|---|---|---|---|---|
| 1 | `foo(x) = x[1] + sum(x[2])` | `Tuple{typeof(foo), Tuple{Float64,Vector{Float64}}}` | 34 | 67 | fdata vs rdata |
| 2 | `bump!(c) = (c.v = c.v*c.v; c.v)` | `Tuple{typeof(bump!), Cell}` | 37 | 79 | mutation / capture / restore |

**Example 2 changed from the spec's `f!(x) = (x .*= x; sum(x))`.** The spec said
"something like". Array broadcast and even explicit `setindex!` inline into huge IR
on Julia 1.12 (`x .*= x` → 600–700 stmts; `x[1]=x[1]*x[1]` → 466). A scalar field on
a `mutable struct Cell` keeps the IR tiny (raw = 6 stmts) while still showing the
full mutation story: forward `lsetfield!`, captured old value, reverse restore.

## Gradients (ground truth — assert against these)

- `foo((2.0,[1.0,3.0,5.0]))` = 11.0, grad = `(NoTangent, (1.0, [1.0,1.0,1.0]))`
- `bump!(Cell(3.0))` = 9.0, grad on `c.v` = 6.0. **`c.v` is restored to 3.0** after
  the reverse pass — Mooncake genuinely undoes the mutation. The `restore` phase is real.

## Interpreter design (Stage 1)

A statement-walking interpreter over `IRCode`:
- SSA env (`Vector{Any}`), argument values, program counter, block fallthrough/goto.
- `_1` = shared-data sentinel: intercept `Mooncake.get_shared_data_field(_1, n)` →
  `dri.shared_data[n]`. All other calls dispatch to the **real** Julia/Mooncake
  functions (`rrule!!`, `increment!!`, `uninit_fcodual`, builtins, intrinsics).
- `Expr(:new, T, args...)` → `ccall(:jl_new_structv, ...)`.
- fwd args: `_2 = zero_fcodual(f)`, `_3 = zero_fcodual(x)`. rvs args: `_2 = seed rdata`.
- `dri.shared_data` is shared (same object) across fwd then rvs — it holds the
  pullback/block stacks the fwd pass `push!`es and the rvs pass `pop!`s.
- Both examples have a single primal block ⇒ the AD IR control flow is linear
  (unconditional `goto`s); `PhiNode`/`GotoIfNot` handled generically for safety.
- Final gradient = combine the input CoDual's accumulated fdata with the rdata
  tuple returned by `rvs_ir`; cross-check against `value_and_gradient!!`.
