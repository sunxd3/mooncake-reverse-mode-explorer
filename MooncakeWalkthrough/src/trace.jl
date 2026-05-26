# Orchestrate one full reverse-mode AD trace and assemble the JSON output.
#
# Pipeline: generate the real forward / reverse IR with Mooncake, interpret both
# statement-by-statement with `run_traced` (stepper.jl), let `EventEmitter`
# (events.jl) record state deltas, and package everything (IR stages + steps +
# result) as a JSON-friendly Dict matching /schema/trace.v1.schema.json.

const SCHEMA_VERSION = 1

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

"""Build the step metadata array (no `state` field). mutatesPrimal is computed
from the per-step rendered input primals captured by the emitter."""
function build_steps(raw_steps, ir_list, stage::String, base_phase::String,
                     start_index::Int, primals_per_step::Vector)
    steps = Dict{String,Any}[]
    for (k, rs) in enumerate(raw_steps)
        abs_idx = start_index + k - 1
        ir = ir_list[rs.pc]
        primal = primals_per_step[abs_idx]
        # mutatesPrimal compares to the previous absolute step (across both passes);
        # the first step has no predecessor and is never `mutates`.
        mutates = abs_idx > 1 && primal != primals_per_step[abs_idx - 1]
        phase = (base_phase == "reverse" && mutates) ? "restore" : base_phase
        push!(steps, Dict{String,Any}(
            "index" => abs_idx,
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
        ))
    end
    return steps
end

"""
    build_trace(example_id, inputs, seed) -> Dict

Run real Mooncake reverse-mode AD for one example and return the full trace as
an event stream."""
function build_trace(example_id::AbstractString, inputs::AbstractDict, seed::AbstractDict)
    spec = get_example(example_id)
    arg = spec.make_arg(inputs)
    bundle = ad_bundle(spec, arg)

    # CoDual arguments for the forward pass. `_1` is the captured shared data.
    codual_f = Mooncake.zero_fcodual(spec.func)
    codual_x = Mooncake.zero_fcodual(arg)
    fwd_args = Any[bundle.shared_data, codual_f, codual_x]
    fwd_roles = Dict(1 => "captures", 2 => "function", 3 => "differentiated argument")

    em = EventEmitter()
    # Initial state — rendered BEFORE any statement executes.
    em.initial_input = render_value(codual_x)
    em.initial_tape = render_tape(bundle.shared_data)
    em.prev_input = em.initial_input
    em.prev_tape = copy(em.initial_tape)

    # --- Forward pass --------------------------------------------------------
    emit_pass_start!(em, "forward", fwd_args, fwd_roles)
    fwd_step = Ref(0)
    fwd_snap = (env, def, av, sd) -> begin
        fwd_step[] += 1
        record_step!(em, env, def, av, sd, codual_x, fwd_step[])
        return nothing
    end
    out_codual, fwd_raw = run_traced(bundle.fwd_ir, fwd_args, bundle.shared_data, fwd_snap)

    # --- Between-pass: split the output cotangent ---------------------------
    # ȳ splits into fdata (address-like — increment into the output buffer) and
    # rdata (value-like — passed as `_2` to the reverse pass). Mooncake's own
    # `__value_and_pullback!!` does the same (see interface.jl).
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

    # Capture any state changes the increment caused (in tracked roots that
    # span passes: input, tape). Args don't carry over — they're rebuilt on
    # `pass_start "reverse"`.
    curr_input = render_value(codual_x)
    diff_rendered!(em.events, Dict{String,Any}("kind" => "input"),
                   em.prev_input, curr_input, Any[])
    em.prev_input = curr_input
    stack_idx = 0
    for s in bundle.shared_data
        s isa Mooncake.Stack || continue
        curr = render_value(s)
        diff_rendered!(em.events, Dict{String,Any}("kind" => "tape", "index" => stack_idx),
                       em.prev_tape[stack_idx + 1], curr, Any[])
        em.prev_tape[stack_idx + 1] = curr
        stack_idx += 1
    end

    # --- Reverse pass --------------------------------------------------------
    rvs_args = Any[bundle.shared_data, ybar_rdata]
    rvs_roles = Dict(1 => "captures", 2 => "output cotangent · rdata half")
    emit_pass_start!(em, "reverse", rvs_args, rvs_roles)
    rvs_step = Ref(length(fwd_raw))
    rvs_snap = (env, def, av, sd) -> begin
        rvs_step[] += 1
        record_step!(em, env, def, av, sd, codual_x, rvs_step[])
        return nothing
    end
    rvs_ret, rvs_raw = run_traced(bundle.rvs_ir, rvs_args, bundle.shared_data, rvs_snap)

    fwd_ir_list = export_ir(bundle.fwd_ir)
    rvs_ir_list = export_ir(bundle.rvs_ir)
    fwd_steps = build_steps(fwd_raw, fwd_ir_list, "fwd_ir", "forward", 1,
                            em.primals_per_step)
    rvs_steps = build_steps(rvs_raw, rvs_ir_list, "rvs_ir", "reverse",
                            length(fwd_steps) + 1, em.primals_per_step)

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
            "text" => strip_module_prefixes(st.text),
            "blockCount" => st.meta.block_count,
            "instCount" => st.meta.inst_count,
            "stepped" => s in (:fwd_ir, :rvs_ir),
        ))
    end

    return Dict{String,Any}(
        "schemaVersion" => SCHEMA_VERSION,
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
        "initialState" => Dict{String,Any}(
            "input" => em.initial_input,
            "tape" => em.initial_tape,
        ),
        "events" => em.events,
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

"""
    bake(out_dir = "web/public/traces") -> Nothing

Regenerate the manifest and per-example trace JSON files for the static viewer.
Writes `manifest.json` and `trace_<id>.json` for every example."""
function bake(out_dir::AbstractString =
              joinpath(@__DIR__, "..", "..", "web", "public", "traces"))
    out_dir = abspath(out_dir)
    mkpath(out_dir)
    manifest = examples_manifest()
    open(joinpath(out_dir, "manifest.json"), "w") do io
        JSON3.write(io, Dict("examples" => manifest))
    end
    @info "wrote manifest.json" examples = length(manifest)
    for ex in manifest
        id = ex["id"]
        inputs = Dict{String,Any}(ex["defaultInputs"])
        seed = Dict{String,Any}(ex["defaultSeed"])
        trace = build_trace(id, inputs, seed)
        path = joinpath(out_dir, "trace_$(id).json")
        open(path, "w") do io
            JSON3.write(io, trace)
        end
        @info "wrote trace_$(id).json" bytes = filesize(path) events = length(trace["events"])
    end
    return nothing
end
