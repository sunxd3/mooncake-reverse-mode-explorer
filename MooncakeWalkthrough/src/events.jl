# Diff rendered states and emit the event stream consumed by the browser.
# Schema: /schema/trace.v1.schema.json.
#
# The emitter renders every tracked root (input CoDual, args, tape stacks,
# defined SSAs) after each statement, structurally compares against the prior
# render, and pushes minimal-delta events:
#   pass_start, ssa_define, mut_set, stack_push, stack_pop, step_marker.
# The browser (web/src/lib/replay.ts) reconstructs per-step worlds by replay.

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
size are assumed unchanged."""
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
