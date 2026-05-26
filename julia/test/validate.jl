# Stage 1 acceptance gate: validate that the interpreter-produced trace is a
# faithful account of Mooncake's real reverse-mode AD.
#
# Layers (see artifacts/STAGE1_VALIDATION.md):
#   A independent ground truth (finite differences + analytic)
#   B same-IR equivalence    (compile the exact stepped IR, compare bit-exact)
#   C whole-pipeline         (compare to build_rrule / value_and_gradient!!)
#   D mutation / restore invariants
#   E trace structural invariants
#   F input independence of the IR
#   G seed linearity

import Pkg
Pkg.activate(joinpath(@__DIR__, ".."))
include(joinpath(@__DIR__, "..", "src", "MooncakeWalkthrough.jl"))
using .MooncakeWalkthrough
const MW = MooncakeWalkthrough
import Mooncake
using Test

# --- helpers ----------------------------------------------------------------

const NOSNAP = (a, b, c, d) -> nothing

"""Run reverse-mode AD via our statement interpreter, returning intermediate
results (no JSON, no snapshots). `ybar` is the output cotangent — a `Float64`
for a scalar output, a structured tangent otherwise."""
function interp_ad(f, arg, ybar)
    interp = Mooncake.get_interpreter(Mooncake.ReverseMode)
    sig = Tuple{typeof(f),typeof(arg)}
    dri = Mooncake.generate_ir(interp, sig; do_inline=false, do_optimize=false)
    cf = Mooncake.zero_fcodual(f)
    cx = Mooncake.zero_fcodual(arg)
    out, _ = MW.run_traced(dri.fwd_ir, Any[dri.shared_data, cf, cx], dri.shared_data, NOSNAP)
    post_fwd_primal = deepcopy(Mooncake.primal(cx))
    # Split the cotangent: fdata half into the output buffer, rdata half to _2.
    Mooncake.increment!!(Mooncake.tangent(out), Mooncake.fdata(ybar))
    rret, _ = MW.run_traced(dri.rvs_ir, Any[dri.shared_data, Mooncake.rdata(ybar)],
                            dri.shared_data, NOSNAP)
    grad = Mooncake.tangent(Mooncake.tangent(cx), rret[2])
    return (; primal=Mooncake.primal(out), grad, post_fwd_primal,
            restored_primal=deepcopy(Mooncake.primal(cx)), dri)
end

"""Compile OpaqueClosures from the *exact same un-inlined IR* the interpreter
steps, run them, and return the result. Fresh IR so the stacks don't collide."""
function oc_ad(f, arg, ybar)
    interp = Mooncake.get_interpreter(Mooncake.ReverseMode)
    sig = Tuple{typeof(f),typeof(arg)}
    dri = Mooncake.generate_ir(interp, sig; do_inline=false, do_optimize=false)
    fwd_oc = Mooncake.misty_closure(dri.fwd_ret_type, dri.fwd_ir, dri.shared_data...)
    rvs_oc = Mooncake.misty_closure(dri.rvs_ret_type, dri.rvs_ir, dri.shared_data...)
    cf = Mooncake.zero_fcodual(f)
    cx = Mooncake.zero_fcodual(arg)
    out = fwd_oc(cf, cx)
    Mooncake.increment!!(Mooncake.tangent(out), Mooncake.fdata(ybar))
    rret = rvs_oc(Mooncake.rdata(ybar))
    grad = Mooncake.tangent(Mooncake.tangent(cx), rret[2])
    return (; primal=Mooncake.primal(out), grad)
end

flat(x) = MW.flatten_numbers(x)

# --- example definitions (mirror src/examples.jl) ---------------------------

mutable struct Cell
    v::Float64
end
foo(x) = x[1] + sum(x[2])
bump!(c::Cell) = (c.v = c.v * c.v; c.v)
vpair(x::Vector{Float64}) = (copy(x), sum(x))

"""Central finite-difference gradient of a scalar-valued `f` over a flat list of
scalar inputs. `build(vals)` rebuilds the argument; `f` must not be observed
through mutation (a fresh argument is built per evaluation)."""
function fd_grad(f, build, vals; eps=1e-6)
    g = similar(vals)
    for i in eachindex(vals)
        hi = copy(vals); hi[i] += eps
        lo = copy(vals); lo[i] -= eps
        g[i] = (f(build(hi)) - f(build(lo))) / (2eps)
    end
    return g
end

@testset "Mooncake walkthrough — trace validation" begin

    # =====================================================================
    @testset "Example 1: foo  (scalar + vector)" begin
        cases = [
            (2.0, [1.0, 3.0, 5.0]), (0.0, [0.0, 0.0]), (-1.5, [2.0]),
            (3.25, Float64[]), (1.0, [1.0, 2.0, 3.0, 4.0, 5.0, 6.0]),
        ]
        for (x1, x2) in cases
            arg = (x1, x2)
            r = interp_ad(foo, arg, 1.0)

            # A — analytic + finite difference
            @test r.primal == foo(arg)
            @test flat(r.grad) == vcat(1.0, ones(length(x2)))          # analytic
            fdvals = vcat(x1, x2)
            fd = fd_grad(foo, v -> (v[1], v[2:end]), fdvals)
            @test isapprox(flat(r.grad), fd; rtol=1e-4, atol=1e-6)     # independent

            # C — whole pipeline
            cache = Mooncake.prepare_gradient_cache(foo, arg)
            _, vg = Mooncake.value_and_gradient!!(cache, foo, (x1, copy(x2)))
            @test flat(r.grad) == flat(vg[2])

            # D — non-mutating: primal never moves
            @test r.post_fwd_primal == arg
            @test r.restored_primal == arg
        end

        # B — same-IR OpaqueClosure equivalence (bit-exact)
        for (x1, x2) in cases
            arg = (x1, x2)
            ir = interp_ad(foo, arg, 1.0)
            oc = oc_ad(foo, arg, 1.0)
            @test ir.primal === oc.primal
            @test flat(ir.grad) == flat(oc.grad)
        end

        # G — seed linearity
        g1 = interp_ad(foo, (2.0, [1.0, 3.0, 5.0]), 1.0).grad
        g2 = interp_ad(foo, (2.0, [1.0, 3.0, 5.0]), 2.5).grad
        @test isapprox(flat(g2), 2.5 .* flat(g1); rtol=1e-12)
    end

    # =====================================================================
    @testset "Example 2: bump!  (in-place mutation)" begin
        for v in [3.0, 0.0, -2.0, 100.0, 0.5]
            r = interp_ad(bump!, Cell(v), 1.0)

            # A — analytic + finite difference
            @test r.primal == v * v
            @test flat(r.grad) == [2v]
            fd = fd_grad(c -> bump!(c), x -> Cell(x[1]), [v])
            @test isapprox(flat(r.grad), fd; rtol=1e-4, atol=1e-6)

            # C — whole pipeline
            cache = Mooncake.prepare_gradient_cache(bump!, Cell(v))
            _, vg = Mooncake.value_and_gradient!!(cache, bump!, Cell(v))
            @test flat(r.grad) == flat(vg[2])

            # D — mutation invariants: squared after forward, restored after reverse
            @test r.post_fwd_primal.v == v * v
            @test r.restored_primal.v == v
        end

        # B — same-IR OpaqueClosure equivalence (bit-exact)
        for v in [3.0, 0.0, -2.0, 100.0]
            ir = interp_ad(bump!, Cell(v), 1.0)
            oc = oc_ad(bump!, Cell(v), 1.0)
            @test ir.primal === oc.primal
            @test flat(ir.grad) == flat(oc.grad)
        end

        # G — seed linearity
        g1 = interp_ad(bump!, Cell(3.0), 1.0).grad
        g2 = interp_ad(bump!, Cell(3.0), -4.0).grad
        @test isapprox(flat(g2), -4.0 .* flat(g1); rtol=1e-12)
    end

    # =====================================================================
    @testset "Example 3: vpair  (vector + scalar output)" begin
        # The output cotangent ȳ = (ȳv, ȳs) splits: ȳv is fdata, ȳs is rdata.
        @test Mooncake.fdata((ones(3), 1.0)) == (ones(3), Mooncake.NoFData())
        @test Mooncake.rdata((ones(3), 1.0)) == (Mooncake.NoRData(), 1.0)

        for x in [[1.0, 2.0, 3.0], [0.0], [-1.0, 4.0], [2.0, 2.0, 2.0, 2.0, 2.0]]
            n = length(x)
            r = interp_ad(vpair, copy(x), (ones(n), 1.0))

            # A — analytic: d/dx (ȳv·copy(x) + ȳs·sum(x)) = ȳv .+ ȳs
            @test r.primal == vpair(x)
            @test flat(r.grad) == ones(n) .+ 1.0

            # C — whole pipeline. value_and_gradient!! assumes a scalar output,
            # so cross-check with value_and_pullback!! and the same cotangent.
            rule = Mooncake.build_rrule(vpair, copy(x))
            _, vg = Mooncake.value_and_pullback!!(rule, (ones(n), 1.0), vpair, copy(x))
            @test flat(r.grad) == flat(vg[2])

            # D — non-mutating: the input primal never moves
            @test r.post_fwd_primal == x
            @test r.restored_primal == x
        end

        # B — same-IR OpaqueClosure equivalence (value-exact; the output tuple
        # holds a freshly-`copy`d vector, so compare by value not identity)
        for x in [[1.0, 2.0, 3.0], [-1.0, 4.0]]
            n = length(x)
            ir = interp_ad(vpair, copy(x), (ones(n), 1.0))
            oc = oc_ad(vpair, copy(x), (ones(n), 1.0))
            @test ir.primal == oc.primal
            @test flat(ir.grad) == flat(oc.grad)
        end

        # G — pullback linear in the cotangent (fdata and rdata halves both)
        g1 = interp_ad(vpair, [1.0, 2.0, 3.0], (ones(3), 1.0)).grad
        g2 = interp_ad(vpair, [1.0, 2.0, 3.0], (fill(2.5, 3), 2.5)).grad
        @test isapprox(flat(g2), 2.5 .* flat(g1); rtol=1e-12)
    end

    # =====================================================================
    @testset "E: trace structural invariants" begin
        for (id, inputs) in [("scalar-vector", Dict("x1" => 2.0, "x2" => [1.0, 3.0, 5.0])),
                             ("mutation", Dict("v" => 3.0)),
                             ("vector-pair", Dict("x" => [1.0, 2.0, 3.0]))]
            t = build_trace(id, inputs, Dict{String,Any}())
            steps = t["steps"]
            @test !isempty(steps)
            @test t["counts"]["total"] == length(steps)
            @test all(s -> s["passed"], t["result"]["checks"])

            # indices are 1..N and contiguous
            @test [s["index"] for s in steps] == collect(1:length(steps))

            # SSA-defined count is monotonically non-decreasing within a stage.
            # State is reconstructed by replaying the event stream.
            worlds = MW.replay_worlds(t["initialState"], t["events"])
            @test length(worlds) == length(steps)
            for stage in ("fwd_ir", "rvs_ir")
                counts = [length(worlds[i]["ssa"]) for (i, s) in enumerate(steps)
                          if s["stage"] == stage]
                @test issorted(counts)
            end

            # the forward pass ends with `return`, and the returned output
            # CoDual's primal is the primal value of the function
            fwd = filter(s -> s["stage"] == "fwd_ir", steps)
            @test startswith(fwd[end]["text"], "return")
            @test any(s -> s["produced"] !== nothing &&
                           get(s["produced"], "kind", "") == "codual" &&
                           s["produced"]["primal"] == t["result"]["primalValue"], fwd)

            # every restore step is a reverse step that moves the primal
            for s in steps
                if s["phase"] == "restore"
                    @test s["stage"] == "rvs_ir"
                    @test s["mutatesPrimal"] == true
                end
            end
        end

        # foo and vpair have no restores; bump! has at least one
        @test count(s -> s["phase"] == "restore",
                    build_trace("scalar-vector",
                                Dict("x1" => 2.0, "x2" => [1.0, 3.0]),
                                Dict{String,Any}())["steps"]) == 0
        @test count(s -> s["phase"] == "restore",
                    build_trace("vector-pair", Dict("x" => [1.0, 2.0, 3.0]),
                                Dict{String,Any}())["steps"]) == 0
        @test count(s -> s["phase"] == "restore",
                    build_trace("mutation", Dict("v" => 3.0),
                                Dict{String,Any}())["steps"]) >= 1
    end

    # =====================================================================
    @testset "F: IR is input-independent (per signature)" begin
        # The stepped IR depends only on the type signature: same text + step
        # count for every numeric input — the assumption editable inputs rely on.
        t_ref = build_trace("scalar-vector",
                            Dict("x1" => 2.0, "x2" => [1.0, 3.0, 5.0]), Dict{String,Any}())
        for inputs in [Dict("x1" => -9.0, "x2" => [4.0]),
                       Dict("x1" => 0.0, "x2" => Float64[]),
                       Dict("x1" => 7.0, "x2" => [1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0])]
            t = build_trace("scalar-vector", inputs, Dict{String,Any}())
            @test t["counts"] == t_ref["counts"]
            @test [i["text"] for i in t["steppedStages"]["fwd_ir"]] ==
                  [i["text"] for i in t_ref["steppedStages"]["fwd_ir"]]
            @test [i["text"] for i in t["steppedStages"]["rvs_ir"]] ==
                  [i["text"] for i in t_ref["steppedStages"]["rvs_ir"]]
        end

        # vector-pair: IR identical for any input vector length (the editable
        # cotangent vector tracks that length, so the UI relies on this too).
        vp_ref = build_trace("vector-pair", Dict("x" => [1.0, 2.0]), Dict{String,Any}())
        for x in [[3.0], Float64[], [1.0, 2.0, 3.0, 4.0, 5.0]]
            t = build_trace("vector-pair", Dict("x" => x), Dict{String,Any}())
            @test t["counts"] == vp_ref["counts"]
            @test [i["text"] for i in t["steppedStages"]["fwd_ir"]] ==
                  [i["text"] for i in vp_ref["steppedStages"]["fwd_ir"]]
            @test [i["text"] for i in t["steppedStages"]["rvs_ir"]] ==
                  [i["text"] for i in vp_ref["steppedStages"]["rvs_ir"]]
        end
    end
end
