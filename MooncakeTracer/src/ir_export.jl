# Convert `IRCode` into a flat, JSON-friendly list of instructions for display.

"""Strip module qualifiers that just add noise to a rendered string."""
function strip_module_prefixes(s::AbstractString)
    replace(s, "Main.MooncakeTracer." => "", "MooncakeTracer." => "",
            "Mooncake.IntrinsicsWrappers." => "", "Mooncake.BasicBlockCode." => "",
            "Mooncake." => "", "Core.Compiler." => "", "Core." => "", "Base." => "")
end

"""Strip module qualifiers and truncate to fit a single IR-line cell."""
function clean_text(s::AbstractString)
    s = strip_module_prefixes(s)
    length(s) > 140 && (s = s[1:137] * "…")
    return s
end

_operand(x) = clean_text(string(x))

"""The callee name of a `:call` / `:invoke`, or `nothing`."""
function callee_name(stmt)
    stmt isa Expr || return nothing
    c = stmt.head === :call ? stmt.args[1] :
        stmt.head === :invoke ? stmt.args[2] : return nothing
    c isa GlobalRef && return string(c.name)
    c isa Core.SSAValue && return "%ssa"
    c isa Core.Argument && return "_arg"
    return string(nameof(typeof(c)) == :Function ? c : c)  # builtins: string is the name
end

"""Coarse classification used for styling and the explanation table."""
function classify(stmt, defines::Bool)
    stmt isa Core.ReturnNode && return "return"
    (stmt isa Core.GotoNode || stmt isa Core.GotoIfNot) && return "goto"
    stmt isa Core.PhiNode && return "phi"
    stmt isa Core.PiNode && return "pi"
    if stmt isa Expr
        stmt.head === :new && return "new"
        stmt.head === :boundscheck && return "nop"
        if stmt.head === :call || stmt.head === :invoke
            cn = callee_name(stmt)
            cn == "get_shared_data_field" && return "shared-data"
            cn == "rrule!!" && return "rrule"
            cn == "increment!!" && return "increment"
            (cn == "uninit_fcodual" || cn == "zero_fcodual") && return "wrap"
            cn == "getfield" && return "getfield"
            cn == "setfield!" && return "setfield"
            cn == "tuple" && return "tuple"
            cn == "typeassert" && return "typeassert"
            cn == "push!" && return "push"
            cn == "pop!" && return "pop"
            cn == "%ssa" && return "pullback-call"
            cn in ("__assemble_lazy_zero_rdata", "instantiate", "getindex",
                   "lazy_zero_rdata") && return "rdata"
            return "call"
        end
    end
    stmt === nothing && return "nop"
    stmt isa QuoteNode && return "const"
    return "other"
end

"""Human-readable one-line text for a statement."""
function statement_text(stmt, pc::Int, defines::Bool)
    body = if stmt isa Core.ReturnNode
        isdefined(stmt, :val) ? "return $(_operand(stmt.val))" : "unreachable"
    elseif stmt isa Core.GotoNode
        "goto #$(stmt.label)"
    elseif stmt isa Core.GotoIfNot
        "goto #$(stmt.dest) if not $(_operand(stmt.cond))"
    elseif stmt isa Core.PhiNode
        "φ " * join([(isassigned(stmt.values, i) ?
                      "#$(stmt.edges[i])→$(_operand(stmt.values[i]))" : "#$(stmt.edges[i])→—")
                     for i in eachindex(stmt.edges)], "  ")
    elseif stmt isa Core.PiNode
        "π($(_operand(stmt.val)))"
    elseif stmt === nothing
        "nop"
    elseif stmt isa Expr && stmt.head === :new
        "new $(clean_text(string(stmt.args[1])))(" *
        join([_operand(a) for a in @view stmt.args[2:end]], ", ") * ")"
    else
        clean_text(string(stmt))
    end
    return defines ? "%$pc = $body" : body
end

"""Export an `IRCode` as `Vector{Dict}` — one entry per statement."""
function export_ir(ir::Core.Compiler.IRCode)
    out = Dict{String,Any}[]
    for (bi, blk) in enumerate(ir.cfg.blocks)
        for pc in blk.stmts.start:blk.stmts.stop
            stmt = ir.stmts[pc][:stmt]
            defines = !(stmt isa Core.GotoNode || stmt isa Core.GotoIfNot ||
                        stmt isa Core.ReturnNode)
            push!(out, Dict{String,Any}(
                "index" => pc,
                "block" => bi,
                "blockStart" => pc == blk.stmts.start,
                "ssaId" => defines ? "%$pc" : nothing,
                "defines" => defines,
                "kind" => classify(stmt, defines),
                "text" => statement_text(stmt, pc, defines),
                "type" => clean_text(string(ir.stmts[pc][:type])),
            ))
        end
    end
    return out
end
