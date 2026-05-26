# Assemble a full debugger trace for one example + inputs + seed.
#
# Pipeline: generate the real forward / reverse IR with Mooncake, interpret both
# statement-by-statement with `run_traced`, emit an event stream that records
# every change to tracked state (input CoDual, arguments, tape stacks, defined
# SSAs), and package everything (IR stages + steps + result) as a JSON-friendly
# Dict.
#
# Trace shape (schemaVersion 1):
#   {steps[] — metadata only, no `state`,
#    initialState: {input, tape},
#    events: [...]}
# The frontend reconstructs per-step state by replaying events.

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

# --- event-stream emitter ---------------------------------------------------

"""Captures everything needed to emit, and later replay, the per-step state
deltas of one trace."""
mutable struct EventEmitter
    events::Vector{Dict{String,Any}}
    primals_per_step::Vector{Any}     # rendered input.primal at each step; for mutatesPrimal
    initial_input::Any                # rendered input CoDual before any statement
    initial_tape::Vector{Any}         # rendered tape stacks before any statement
    # Working state — updated as events are emitted.
    prev_input::Any
    prev_args::Vector{Any}            # reset on pass_start
    prev_tape::Vector{Any}
    prev_ssa::Dict{Int,Any}           # pc -> rendered value; reset on pass_start
end

EventEmitter() = EventEmitter(Dict{String,Any}[], Any[], nothing, Any[],
                              nothing, Any[], Any[], Dict{Int,Any}())

"""Diff a stack RValue. Mooncake.Stack is append/pop-only at the top, so growth
emits `stack_push` events and shrinkage emits `stack_pop`. Items below the new
size are assumed unchanged (this invariant is checked by the replay-equivalence
test, not at runtime)."""
function diff_stack!(events, root, path, prev, curr)
    psize, csize = prev["size"], curr["size"]
    if csize > psize
        for i in (psize+1):csize
            push!(events, Dict{String,Any}("t" => "stack_push",
                                           "root" => root,
                                           "path" => copy(path),
                                           "value" => curr["items"][i]))
        end
    elseif csize < psize
        for _ in 1:(psize - csize)
            push!(events, Dict{String,Any}("t" => "stack_pop",
                                           "root" => root,
                                           "path" => copy(path)))
        end
    end
end

"""Recursive structural differ over two rendered RValue trees. Emits mut_set /
stack_push / stack_pop events into `events`. Kind mismatch ⇒ whole-subtree
replace. Container length mismatch ⇒ whole-container replace."""
function diff_rendered!(events, root, prev, curr, path)
    prev === curr && return
    if !(prev isa Dict) || !(curr isa Dict) || prev["kind"] != curr["kind"]
        if prev != curr
            push!(events, Dict{String,Any}("t" => "mut_set", "root" => root,
                                           "path" => copy(path), "value" => curr))
        end
        return
    end
    k = curr["kind"]
    if k == "stack"
        diff_stack!(events, root, path, prev, curr)
    elseif k == "codual"
        diff_rendered!(events, root, prev["primal"], curr["primal"],
                       push!(copy(path), "primal"))
        diff_rendered!(events, root, prev["tangent"], curr["tangent"],
                       push!(copy(path), "tangent"))
    elseif k == "tangent" || k == "namedtuple" || k == "struct"
        pf, cf = prev["fields"], curr["fields"]
        if length(pf) != length(cf)
            push!(events, Dict{String,Any}("t" => "mut_set", "root" => root,
                                           "path" => copy(path), "value" => curr))
            return
        end
        for i in eachindex(cf)
            pname = pf[i]["name"]
            cname = cf[i]["name"]
            if pname != cname
                push!(events, Dict{String,Any}("t" => "mut_set", "root" => root,
                                               "path" => copy(path), "value" => curr))
                return
            end
            diff_rendered!(events, root, pf[i]["value"], cf[i]["value"],
                           push!(copy(path), cname))
        end
    elseif k == "ref"
        diff_rendered!(events, root, prev["value"], curr["value"],
                       push!(copy(path), "value"))
    elseif k == "tuple" || k == "vector" || k == "array"
        pi, ci = prev["items"], curr["items"]
        if length(pi) != length(ci)
            push!(events, Dict{String,Any}("t" => "mut_set", "root" => root,
                                           "path" => copy(path), "value" => curr))
        else
            for i in eachindex(ci)
                diff_rendered!(events, root, pi[i], ci[i],
                               push!(copy(path), i - 1))  # 0-based for JS
            end
        end
    else
        # Leaf kinds (number, bool, string, symbol, nothing, type, val, fn,
        # pullback, none, elided, opaque, undef) — compare structurally.
        if prev != curr
            push!(events, Dict{String,Any}("t" => "mut_set", "root" => root,
                                           "path" => copy(path), "value" => curr))
        end
    end
end

"""Render the per-arg list shown in the UI (id, role, value)."""
function render_args(argvals, arg_roles)
    [Dict{String,Any}("id" => "_$i",
                      "role" => get(arg_roles, i, ""),
                      "value" => render_value(v))
     for (i, v) in enumerate(argvals)]
end

"""Render the tape (just the Stacks in `shared_data`, in order)."""
render_tape(shared_data) = Any[render_value(s) for s in shared_data if s isa Mooncake.Stack]

"""Emit pass_start. Resets the SSA env and arg tracking; tape and input carry
across passes (same Julia objects)."""
function emit_pass_start!(em::EventEmitter, pass::String, argvals, arg_roles)
    push!(em.events, Dict{String,Any}("t" => "pass_start", "pass" => pass,
                                       "args" => render_args(argvals, arg_roles)))
    em.prev_args = Any[render_value(v) for v in argvals]
    em.prev_ssa = Dict{Int,Any}()
end

"""Emit all events for one executed IR statement: new ssa_define(s), then
mut_set / stack_push / stack_pop for every tracked root that changed, then
step_marker. Called after each statement by run_traced."""
function record_step!(em::EventEmitter, env, defined, argvals, shared_data,
                     input_codual, step_index::Int)
    # 1. SSA defines — anything in `defined` not yet in prev_ssa is new.
    for pc in eachindex(defined)
        if defined[pc] && !haskey(em.prev_ssa, pc)
            val = render_value(env[pc])
            push!(em.events, Dict{String,Any}("t" => "ssa_define",
                                              "pc" => pc, "value" => val))
            em.prev_ssa[pc] = val
        end
    end

    # 2. Mutations to existing SSAs via aliasing (e.g. push! on a stack-typed SSA).
    for (pc, prev_val) in em.prev_ssa
        curr_val = render_value(env[pc])
        if curr_val != prev_val
            diff_rendered!(em.events, Dict{String,Any}("kind" => "ssa", "pc" => pc),
                           prev_val, curr_val, Any[])
            em.prev_ssa[pc] = curr_val
        end
    end

    # 3. Mutations to the input CoDual (primal updates, tangent buffer fills).
    curr_input = render_value(input_codual)
    diff_rendered!(em.events, Dict{String,Any}("kind" => "input"),
                   em.prev_input, curr_input, Any[])
    em.prev_input = curr_input
    push!(em.primals_per_step, curr_input["primal"])

    # 4. Mutations to args.
    for (i, v) in enumerate(argvals)
        curr = render_value(v)
        diff_rendered!(em.events, Dict{String,Any}("kind" => "arg", "index" => i - 1),
                       em.prev_args[i], curr, Any[])
        em.prev_args[i] = curr
    end

    # 5. Mutations to tape stacks.
    stack_idx = 0
    for s in shared_data
        s isa Mooncake.Stack || continue
        curr = render_value(s)
        diff_rendered!(em.events, Dict{String,Any}("kind" => "tape", "index" => stack_idx),
                       em.prev_tape[stack_idx + 1], curr, Any[])
        em.prev_tape[stack_idx + 1] = curr
        stack_idx += 1
    end

    # 6. Step boundary.
    push!(em.events, Dict{String,Any}("t" => "step_marker", "stepIndex" => step_index))
end

# --- replay (used by tests) -------------------------------------------------

"""Replay an event stream into per-step rendered worlds (matches the shape
`render_state` produces). Returns a Vector indexed by step (1-based)."""
function replay_worlds(initial_state::AbstractDict, events::AbstractVector)
    worlds = Dict{String,Any}[]
    input = deepcopy(initial_state["input"])
    tape = Any[deepcopy(s) for s in initial_state["tape"]]
    args = Any[]
    ssa = Dict{Int,Any}()
    for ev in events
        t = ev["t"]
        if t == "pass_start"
            args = Any[Dict{String,Any}("id" => a["id"], "role" => a["role"],
                                         "value" => deepcopy(a["value"]))
                       for a in ev["args"]]
            ssa = Dict{Int,Any}()
        elseif t == "ssa_define"
            ssa[ev["pc"]] = deepcopy(ev["value"])
        elseif t == "mut_set"
            _apply_root!(input, args, tape, ssa, ev["root"], ev["path"],
                         _ -> deepcopy(ev["value"]))
        elseif t == "stack_push"
            _apply_root!(input, args, tape, ssa, ev["root"], ev["path"],
                         stk -> Dict{String,Any}("kind" => "stack",
                                                  "size" => stk["size"] + 1,
                                                  "items" => vcat(stk["items"], [deepcopy(ev["value"])])))
        elseif t == "stack_pop"
            _apply_root!(input, args, tape, ssa, ev["root"], ev["path"],
                         stk -> Dict{String,Any}("kind" => "stack",
                                                  "size" => stk["size"] - 1,
                                                  "items" => stk["items"][1:end-1]))
        elseif t == "step_marker"
            world_ssa = Dict{String,Any}[Dict{String,Any}("id" => "%$pc",
                                                          "value" => deepcopy(ssa[pc]))
                                         for pc in sort(collect(keys(ssa)))]
            push!(worlds, Dict{String,Any}(
                "ssa" => world_ssa,
                "args" => Any[Dict{String,Any}("id" => a["id"], "role" => a["role"],
                                                "value" => deepcopy(a["value"]))
                              for a in args],
                "tape" => Any[deepcopy(s) for s in tape],
                "input" => deepcopy(input),
            ))
        end
    end
    return worlds
end

# Apply f to the value at root+path. The four roots have different shapes, so
# the dispatch lives here; `_set_at_path` handles the path-walk.
function _apply_root!(input, args, tape, ssa, root, path, f)
    rk = root["kind"]
    if rk == "input"
        new_val = _set_at_path(input, path, f)
        # `input` is a Dict — rebuild contents (cannot reassign in caller via this fn).
        empty!(input); merge!(input, new_val)
    elseif rk == "arg"
        i = root["index"] + 1
        new_inner = _set_at_path(args[i]["value"], path, f)
        args[i] = Dict{String,Any}("id" => args[i]["id"], "role" => args[i]["role"],
                                    "value" => new_inner)
    elseif rk == "tape"
        i = root["index"] + 1
        tape[i] = _set_at_path(tape[i], path, f)
    elseif rk == "ssa"
        pc = root["pc"]
        ssa[pc] = _set_at_path(ssa[pc], path, f)
    end
end

# Returns a NEW value with the leaf at `path` replaced by `f(prev_leaf)`.
function _set_at_path(value, path, f)
    if isempty(path)
        return f(value)
    end
    component = path[1]
    rest = path[2:end]
    if component isa AbstractString
        k = value["kind"]
        if k == "codual"
            new_inner = _set_at_path(value[component], rest, f)
            return merge(value, Dict{String,Any}(component => new_inner))
        elseif k == "tangent" || k == "namedtuple" || k == "struct"
            new_fields = Any[]
            for fld in value["fields"]
                if fld["name"] == component
                    push!(new_fields, Dict{String,Any}("name" => fld["name"],
                                                       "value" => _set_at_path(fld["value"], rest, f)))
                else
                    push!(new_fields, fld)
                end
            end
            return merge(value, Dict{String,Any}("fields" => new_fields))
        elseif k == "ref"
            new_inner = _set_at_path(value["value"], rest, f)
            return merge(value, Dict{String,Any}("value" => new_inner))
        else
            error("unexpected string path component '$component' for kind '$k'")
        end
    else  # number, 0-based
        i = component + 1
        new_items = copy(value["items"])
        new_items[i] = _set_at_path(new_items[i], rest, f)
        return merge(value, Dict{String,Any}("items" => new_items))
    end
end

# --- step metadata ----------------------------------------------------------

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

# --- trace assembly ---------------------------------------------------------

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
            "text" => st.text,
            "blockCount" => st.meta.block_count,
            "instCount" => st.meta.inst_count,
            "stepped" => s in (:fwd_ir, :rvs_ir),
        ))
    end

    result = Dict{String,Any}(
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
    return result
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
