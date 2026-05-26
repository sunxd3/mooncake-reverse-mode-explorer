# Render arbitrary Julia values (CoDuals, tangents, stacks, pullback closures,
# ...) into JSON-friendly tagged dictionaries for the web debugger.
#
# Every rendered value is a Dict with a "kind" tag so the front end can format
# it without guessing types.

const MAX_DEPTH = 6

"""Short, readable type name — strips module paths and Mooncake's gensym noise."""
function short_type(@nospecialize(T))
    s = string(T)
    s = replace(s, "Main.MooncakeTracer." => "", "MooncakeTracer." => "",
                "Mooncake." => "", "Core.Compiler." => "", "Core." => "", "Base." => "")
    # Pull a readable token out of gensym'd closure names like #sum_pb!!#rrule!!##128
    m = match(r"#([A-Za-z_][\w!]*)", s)
    m !== nothing && (s = string(m.captures[1], occursin("{", s) ? "{…}" : ""))
    length(s) > 60 && (s = s[1:57] * "…")
    return s
end

"""Readable name for a pullback closure / struct."""
function pullback_name(@nospecialize(x))
    nm = string(nameof(typeof(x)))
    m = match(r"#([A-Za-z_][\w!]*)", nm)
    return m !== nothing ? String(m.captures[1]) : nm
end

fn_name(@nospecialize(x)) =
    try
        string(nameof(typeof(x)))
    catch
        replace(string(x), r"^.*\." => "")
    end

is_none(@nospecialize(x)) =
    x isa Mooncake.NoFData || x isa Mooncake.NoRData ||
    x isa Mooncake.NoTangent || x isa Mooncake.ZeroRData

none_name(@nospecialize(x)) = string(nameof(typeof(x)))

looks_like_pullback(@nospecialize(T)) = occursin(r"pb!!|pullback|_pb|rrule", string(T))

render_value(@nospecialize(x)) = render_value(x, 0)

function render_value(@nospecialize(x), depth::Int)
    if depth > MAX_DEPTH
        return Dict{String,Any}("kind" => "elided", "type" => short_type(typeof(x)))
    end
    d1 = depth + 1

    if x === nothing
        return Dict{String,Any}("kind" => "nothing")
    elseif x isa Bool
        return Dict{String,Any}("kind" => "bool", "value" => x)
    elseif x isa Integer
        return Dict{String,Any}("kind" => "number", "value" => Int(x), "int" => true)
    elseif x isa AbstractFloat
        v = Float64(x)
        return Dict{String,Any}("kind" => "number", "value" => isfinite(v) ? v : string(v))
    elseif x isa Symbol
        return Dict{String,Any}("kind" => "symbol", "value" => string(x))
    elseif x isa AbstractString
        return Dict{String,Any}("kind" => "string", "value" => String(x))
    elseif is_none(x)
        return Dict{String,Any}("kind" => "none", "name" => none_name(x))
    elseif x isa Val
        return Dict{String,Any}("kind" => "val",
                                "value" => render_value(typeof(x).parameters[1], d1))
    elseif x isa Type
        return Dict{String,Any}("kind" => "type", "name" => short_type(x))
    elseif x isa Mooncake.CoDual
        return Dict{String,Any}(
            "kind" => "codual",
            "primalType" => short_type(typeof(Mooncake.primal(x))),
            "primal" => render_value(Mooncake.primal(x), d1),
            "tangent" => render_value(Mooncake.tangent(x), d1),
        )
    elseif x isa Mooncake.Tangent || x isa Mooncake.MutableTangent
        flds = x.fields
        return Dict{String,Any}(
            "kind" => "tangent",
            "mutable" => x isa Mooncake.MutableTangent,
            "fields" => [Dict{String,Any}("name" => string(k),
                                          "value" => render_value(getfield(flds, k), d1))
                         for k in keys(flds)],
        )
    elseif x isa Mooncake.Stack
        n = x.position
        items = [render_value(x.memory[i], d1) for i in 1:n]
        return Dict{String,Any}("kind" => "stack", "size" => n, "items" => items)
    elseif x isa Base.RefValue
        return Dict{String,Any}(
            "kind" => "ref",
            "refType" => short_type(eltype(typeof(x))),
            "value" => isassigned(x) ? render_value(x[], d1) :
                       Dict{String,Any}("kind" => "undef"),
        )
    elseif x isa Tuple
        return Dict{String,Any}("kind" => "tuple",
                                "items" => [render_value(e, d1) for e in x])
    elseif x isa NamedTuple
        return Dict{String,Any}(
            "kind" => "namedtuple",
            "fields" => [Dict{String,Any}("name" => string(k),
                                          "value" => render_value(x[k], d1))
                         for k in keys(x)],
        )
    elseif x isa AbstractVector && eltype(x) <: Number
        return Dict{String,Any}(
            "kind" => "vector",
            "items" => [render_value(e, d1) for e in x],
        )
    elseif x isa AbstractArray
        return Dict{String,Any}(
            "kind" => "array",
            "items" => [render_value(e, d1) for e in vec(collect(x))],
        )
    elseif x isa Function || x isa Core.Builtin
        # Pullback closures are `<:Function`; surface them as pullbacks.
        if x isa Function && looks_like_pullback(typeof(x))
            return Dict{String,Any}("kind" => "pullback", "name" => pullback_name(x))
        end
        return Dict{String,Any}("kind" => "fn", "name" => fn_name(x))
    else
        # Generic struct: pullback structs, LazyZeroRData, Cell, …
        T = typeof(x)
        if isstructtype(T)
            if looks_like_pullback(T)
                return Dict{String,Any}("kind" => "pullback",
                                        "name" => pullback_name(x))
            end
            fns = fieldnames(T)
            return Dict{String,Any}(
                "kind" => "struct",
                "type" => short_type(T),
                "fields" => [Dict{String,Any}(
                                 "name" => string(fn),
                                 "value" => isdefined(x, fn) ?
                                            render_value(getfield(x, fn), d1) :
                                            Dict{String,Any}("kind" => "undef"))
                             for fn in fns],
            )
        end
        return Dict{String,Any}("kind" => "opaque", "type" => short_type(T),
                                "repr" => first(string(x), 80))
    end
end
