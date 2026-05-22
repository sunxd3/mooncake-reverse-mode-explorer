# Assemble a full debugger trace for one example + inputs + seed.
#
# Pipeline: generate the real forward / reverse IR with Mooncake, interpret both
# statement-by-statement with `run_traced`, render every per-statement snapshot,
# and package everything (IR stages + steps + result) as a JSON-friendly Dict.

# Short teaching note per statement kind. Data-driven: a new example reuses these.
const EXPLANATIONS = Dict{String,String}(
    "shared-data" => "Reads a value captured by the forward pass and shared with the reverse pass.",
    "wrap" => "Wraps a constant in a CoDual so it can flow through an rrule.",
    "rrule" => "Runs Mooncake's rrule for a primitive: produces the forward output CoDual and a pullback.",
    "getfield" => "Unpacks a tuple field — typically the output CoDual or the pullback from an rrule call.",
    "setfield" => "Writes a field — here, updating an rdata accumulator slot.",
    "typeassert" => "Asserts the inferred type of a CoDual; a no-op at runtime.",
    "tuple" => "Bundles the per-statement pullbacks so they can be pushed onto the tape.",
    "push" => "Pushes captured pullback data onto the tape (a stack shared with the reverse pass).",
    "pop" => "Pops the captured pullback data for this block back off the tape.",
    "increment" => "Accumulates an adjoint (rdata) into a gradient slot.",
    "pullback-call" => "Invokes a captured pullback: propagates the adjoint backwards through one primitive.",
    "rdata" => "Builds or instantiates reverse-data (rdata) — the value-like part of a gradient.",
    "new" => "Allocates a reverse-data accumulator (a mutable Ref initialised to zero).",
    "increment!!" => "Accumulates an adjoint into a gradient slot.",
    "return" => "Returns: the forward output CoDual, or the assembled input gradients.",
    "goto" => "Control flow between basic blocks.",
    "phi" => "A φ-node: selects a value based on the predecessor block.",
    "nop" => "A no-op (an elided bounds check).",
    "const" => "A constant value.",
    "call" => "A function call.",
    "other" => "",
)

struct ADInfoBundle
    spec::ExampleSpec
    sig::Type
    fwd_ir::Core.Compiler.IRCode
    rvs_ir::Core.Compiler.IRCode
    shared_data::Any
    inspection::Any
end

# `generate_ir` is deterministic per signature; cache the IR per example id.
const _IR_CACHE = Dict{String,ADInfoBundle}()

function ad_bundle(spec::ExampleSpec, arg)
    cached = get(_IR_CACHE, spec.id, nothing)
    cached === nothing || return cached
    interp = Mooncake.get_interpreter(Mooncake.ReverseMode)
    sig = example_signature(spec, arg)
    dri = Mooncake.generate_ir(interp, sig; do_inline=false, do_optimize=false)
    inspection = Mooncake.SkillUtils.inspect_ir(spec.func, arg; mode=:reverse)
    bundle = ADInfoBundle(spec, sig, dri.fwd_ir, dri.rvs_ir, dri.shared_data, inspection)
    _IR_CACHE[spec.id] = bundle
    return bundle
end

"""Collect every Float64 in a (possibly nested) gradient structure, in order."""
function flatten_numbers(x, acc=Float64[])
    if x isa AbstractFloat
        push!(acc, Float64(x))
    elseif x isa Tuple
        for e in x
            flatten_numbers(e, acc)
        end
    elseif x isa NamedTuple
        for k in keys(x)
            flatten_numbers(x[k], acc)
        end
    elseif x isa AbstractArray
        for e in x
            flatten_numbers(e, acc)
        end
    elseif x isa Mooncake.Tangent || x isa Mooncake.MutableTangent
        flatten_numbers(x.fields, acc)
    end
    return acc
end

"""Per-statement state snapshot, fully rendered to immutable JSON data."""
function make_snapshot(env, defined, argvals, shared_data, input_codual, arg_roles)
    ssa = Dict{String,Any}[]
    for i in eachindex(defined)
        defined[i] || continue
        push!(ssa, Dict{String,Any}("id" => "%$i", "value" => render_value(env[i])))
    end
    args = Dict{String,Any}[]
    for (i, v) in enumerate(argvals)
        push!(args, Dict{String,Any}(
            "id" => "_$i",
            "role" => get(arg_roles, i, ""),
            "value" => render_value(v),
        ))
    end
    tape = Dict{String,Any}[]
    for s in shared_data
        s isa Mooncake.Stack || continue
        push!(tape, render_value(s))
    end
    return Dict{String,Any}(
        "ssa" => ssa,
        "args" => args,
        "tape" => tape,
        "input" => render_value(input_codual),
    )
end

"""Turn `RawStep`s into JSON trace steps.

`base_phase` is `"forward"` or `"reverse"`. A reverse step that moves the
differentiated argument's *primal* is reclassified `"restore"`. `prev_primal` is
threaded across both passes so primal mutation is detected continuously."""
function package_steps(raw_steps, ir_list, stage::String, base_phase::String,
                       start_index::Int, prev_primal::Ref)
    steps = Dict{String,Any}[]
    for (k, rs) in enumerate(raw_steps)
        ir = ir_list[rs.pc]
        primal = rs.state["input"]["primal"]
        mutates = prev_primal[] !== nothing && primal != prev_primal[]
        prev_primal[] = primal
        phase = (base_phase == "reverse" && mutates) ? "restore" : base_phase
        push!(steps, Dict{String,Any}(
            "index" => start_index + k - 1,
            "phase" => phase,
            "stage" => stage,
            "pc" => rs.pc,
            "block" => rs.block,
            "ssaId" => ir["ssaId"],
            "kind" => ir["kind"],
            "text" => ir["text"],
            "type" => ir["type"],
            "mutatesPrimal" => mutates,
            "explanation" => get(EXPLANATIONS, ir["kind"], ""),
            "produced" => rs.defined ? render_value(rs.value) : nothing,
            "state" => rs.state,
        ))
    end
    return steps
end

"""
    build_trace(example_id, inputs, seed) -> Dict

Run real Mooncake reverse-mode AD for one example and return the full trace.
"""
function build_trace(example_id::AbstractString, inputs::AbstractDict, seed::AbstractDict)
    spec = get_example(example_id)
    arg = spec.make_arg(inputs)
    bundle = ad_bundle(spec, arg)

    # CoDual arguments for the forward pass. `_1` is the captured shared data.
    codual_f = Mooncake.zero_fcodual(spec.func)
    codual_x = Mooncake.zero_fcodual(arg)
    fwd_args = Any[bundle.shared_data, codual_f, codual_x]
    fwd_roles = Dict(1 => "captures", 2 => "function", 3 => "differentiated argument")

    fwd_snap = (env, def, av, sd) ->
        make_snapshot(env, def, av, sd, codual_x, fwd_roles)
    out_codual, fwd_raw = run_traced(bundle.fwd_ir, fwd_args, bundle.shared_data, fwd_snap)

    # The output cotangent ȳ. Like every Mooncake tangent it splits into an
    # fdata half (address-like — seeded into the output CoDual's buffer with
    # `increment!!`) and an rdata half (value-like — passed to the reverse pass
    # as `_2`). For a scalar output the fdata half is `NoFData` and ȳ is all
    # rdata; that is the original scalar-seed behaviour, now the degenerate case.
    # This mirrors Mooncake's own `__value_and_pullback!!` (see interface.jl).
    full_seed = merge(spec.default_seed, Dict{String,Any}(seed))
    ybar, eff_seed = spec.make_cotangent(full_seed, arg)
    ybar_fdata = Mooncake.fdata(ybar)
    ybar_rdata = Mooncake.rdata(ybar)
    cotangent_split = Dict{String,Any}(
        "outputType" => clean_text(string(typeof(ybar))),
        "output" => render_value(ybar),
        "fdata" => render_value(ybar_fdata),
        "rdata" => render_value(ybar_rdata),
    )
    Mooncake.increment!!(Mooncake.tangent(out_codual), ybar_fdata)

    # Reverse pass: `_2` is the rdata half of the output cotangent.
    rvs_args = Any[bundle.shared_data, ybar_rdata]
    rvs_roles = Dict(1 => "captures", 2 => "output cotangent · rdata half")
    rvs_snap = (env, def, av, sd) ->
        make_snapshot(env, def, av, sd, codual_x, rvs_roles)
    rvs_ret, rvs_raw = run_traced(bundle.rvs_ir, rvs_args, bundle.shared_data, rvs_snap)

    fwd_ir_list = export_ir(bundle.fwd_ir)
    rvs_ir_list = export_ir(bundle.rvs_ir)
    prev_primal = Ref{Any}(nothing)
    fwd_steps = package_steps(fwd_raw, fwd_ir_list, "fwd_ir", "forward", 1, prev_primal)
    rvs_steps = package_steps(rvs_raw, rvs_ir_list, "rvs_ir", "reverse",
                              length(fwd_steps) + 1, prev_primal)

    # Reconstruct the input gradient from the interpreter's own outputs.
    grad_x = Mooncake.tangent(Mooncake.tangent(codual_x), rvs_ret[2])

    # Cross-check against Mooncake's public pullback API. `value_and_pullback!!`
    # takes the same cotangent ȳ and works for any output shape (unlike
    # `value_and_gradient!!`, which assumes a scalar output).
    checks = Dict{String,Any}[]
    try
        vp_arg = spec.make_arg(inputs)
        vp_ybar, _ = spec.make_cotangent(full_seed, vp_arg)
        rule = Mooncake.build_rrule(spec.func, vp_arg)
        _, vg = Mooncake.value_and_pullback!!(rule, vp_ybar, spec.func, vp_arg)
        got = flatten_numbers(grad_x)
        want = flatten_numbers(vg[2])
        ok = length(got) == length(want) && all(isapprox.(got, want; atol=1e-8, rtol=1e-6))
        push!(checks, Dict{String,Any}(
            "name" => "gradient matches Mooncake.value_and_pullback!!",
            "passed" => ok,
            "got" => got,
            "want" => want,
        ))
    catch err
        push!(checks, Dict{String,Any}(
            "name" => "gradient cross-check", "passed" => false,
            "error" => sprint(showerror, err)))
    end

    stage_titles = Dict(
        :raw => "Raw IR", :normalized => "Normalised",
        :bbcode => "BBCode", :fwd_ir => "Forward IR", :rvs_ir => "Reverse IR",
        :optimized_fwd => "Optimised Forward", :optimized_rvs => "Optimised Reverse")
    ir_stages = Dict{String,Any}[]
    for s in bundle.inspection.stage_order
        st = bundle.inspection.stages[s]
        push!(ir_stages, Dict{String,Any}(
            "id" => string(s),
            "title" => get(stage_titles, s, string(s)),
            "text" => st.text,
            "blockCount" => st.meta.block_count,
            "instCount" => st.meta.inst_count,
            "stepped" => s in (:fwd_ir, :rvs_ir),
        ))
    end

    return Dict{String,Any}(
        "exampleId" => spec.id,
        "title" => spec.title,
        "description" => spec.description,
        "source" => spec.source,
        "signature" => clean_text(string(bundle.sig)),
        "inputs" => inputs,
        "seed" => eff_seed,
        "cotangentSplit" => cotangent_split,
        "irStages" => ir_stages,
        "steppedStages" => Dict{String,Any}(
            "fwd_ir" => fwd_ir_list, "rvs_ir" => rvs_ir_list),
        "steps" => vcat(fwd_steps, rvs_steps),
        "counts" => Dict{String,Any}(
            "forward" => length(fwd_steps), "reverse" => length(rvs_steps),
            "total" => length(fwd_steps) + length(rvs_steps)),
        "result" => Dict{String,Any}(
            "primalValue" => render_value(Mooncake.primal(out_codual)),
            "gradient" => render_value(grad_x),
            "checks" => checks,
        ),
    )
end

"""Metadata for every example — drives the front-end example picker / input editor."""
function examples_manifest()
    return [Dict{String,Any}(
        "id" => e.id, "title" => e.title, "description" => e.description,
        "source" => e.source, "defaultSeed" => e.default_seed,
        "defaultInputs" => e.default_inputs,
        "inputs" => [Dict{String,Any}("name" => s.name, "kind" => s.kind,
                                      "label" => s.label) for s in e.input_specs],
        "seedInputs" => [Dict{String,Any}("name" => s.name, "kind" => s.kind,
                                          "label" => s.label) for s in e.seed_specs],
    ) for e in EXAMPLES]
end
