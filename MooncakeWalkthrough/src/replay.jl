# Replay an event stream back into per-step rendered worlds.
# Used only by the test suite — production tracing emits events; the browser
# (web/src/lib/replay.ts) replays them. This Julia replay mirrors that logic
# so tests can validate equivalence without a browser.

"""Replay an event stream into per-step rendered worlds (one world per
`step_marker`, in order)."""
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
