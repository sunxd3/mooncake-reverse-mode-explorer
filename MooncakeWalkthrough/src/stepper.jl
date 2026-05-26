# A small statement-stepping interpreter over Mooncake's generated `IRCode`.
#
# It executes the real forward-pass / reverse-pass IR one statement at a time,
# dispatching every call to the real Julia / Mooncake runtime. The only thing it
# fakes is the OpaqueClosure capture slot `_1`: `get_shared_data_field(_1, n)` is
# intercepted and answered from the `shared_data` tuple. After every statement it
# calls `snapshot` so the caller can record a (rendered, immutable) state frame.

const CC = Core.Compiler

# Control-flow signals returned by `eval_stmt`.
struct Goto
    target::Int
end
struct Returned
    val::Any
end

"""A raw (un-rendered) execution step."""
struct RawStep
    pc::Int            # statement index within the IRCode
    block::Int         # basic-block number
    stmt::Any          # the IR statement
    defined::Bool      # whether this statement defines SSA value %pc
    value::Any         # value produced (undef sentinel if none)
    state::Any         # rendered snapshot produced by the caller's `snapshot`
end

const _UNDEF = gensym("undef")

resolve(x::Core.SSAValue, env, args) = env[x.id]
resolve(x::Core.Argument, env, args) = args[x.n]
resolve(x::GlobalRef, env, args) = getglobal(x.mod, x.name)
resolve(x::QuoteNode, env, args) = x.value
resolve(x, env, args) = x

# Faithful `Expr(:new, ...)`: bypasses constructors, like the compiler does.
function new_struct(@nospecialize(T), args::Vector{Any})
    return ccall(:jl_new_structv, Any, (Any, Ptr{Any}, UInt32), T, args, length(args))
end

function apply_call(@nospecialize(f), args::Vector{Any}, shared_data)
    # Intercept the OpaqueClosure capture access.
    if f === Mooncake.get_shared_data_field
        return shared_data[args[2]]
    end
    return f(args...)
end

function eval_expr(e::Expr, env, args, shared_data)
    h = e.head
    if h === :call
        f = resolve(e.args[1], env, args)
        as = Any[resolve(a, env, args) for a in @view e.args[2:end]]
        return apply_call(f, as, shared_data)
    elseif h === :invoke
        f = resolve(e.args[2], env, args)
        as = Any[resolve(a, env, args) for a in @view e.args[3:end]]
        return f(as...)
    elseif h === :new
        T = resolve(e.args[1], env, args)
        as = Any[resolve(a, env, args) for a in @view e.args[2:end]]
        return new_struct(T, as)
    elseif h === :boundscheck
        return true
    elseif h === :foreigncall || h === :gc_preserve_begin || h === :gc_preserve_end
        return nothing
    else
        error("unhandled Expr head in IR interpreter: :$h  ($e)")
    end
end

"""Evaluate one statement. Returns `(value, control)` where `control` is
`nothing`, a `Goto`, or a `Returned`."""
function eval_stmt(@nospecialize(stmt), env, args, shared_data, prev_block::Int)
    if stmt isa Core.ReturnNode
        isdefined(stmt, :val) || return (nothing, Returned(nothing))
        return (nothing, Returned(resolve(stmt.val, env, args)))
    elseif stmt isa Core.GotoNode
        return (nothing, Goto(stmt.label))
    elseif stmt isa Core.GotoIfNot
        cond = resolve(stmt.cond, env, args)
        return (nothing, cond === false ? Goto(stmt.dest) : nothing)
    elseif stmt isa Core.PhiNode
        for (i, e) in enumerate(stmt.edges)
            if Int(e) == prev_block && isassigned(stmt.values, i)
                return (resolve(stmt.values[i], env, args), nothing)
            end
        end
        return (nothing, nothing)
    elseif stmt isa Core.PiNode
        return (resolve(stmt.val, env, args), nothing)
    elseif stmt isa Expr
        return (eval_expr(stmt, env, args, shared_data), nothing)
    elseif stmt isa Core.SSAValue || stmt isa Core.Argument ||
           stmt isa GlobalRef || stmt isa QuoteNode
        return (resolve(stmt, env, args), nothing)
    else
        return (stmt, nothing)  # literal (incl. `nothing`)
    end
end

is_terminator(stmt) =
    stmt isa Core.GotoNode || stmt isa Core.GotoIfNot || stmt isa Core.ReturnNode

"""
    run_traced(ir, argvals, shared_data, snapshot) -> (return_value, steps)

Execute `ir` statement by statement. `argvals` are the values of `_1, _2, ...`.
`snapshot(env, defined, argvals, shared_data)` is called after each statement and
its result stored as that step's rendered state.
"""
function run_traced(ir::Core.Compiler.IRCode, argvals::Vector{Any}, shared_data, snapshot)
    nstmt = length(ir.stmts)
    env = Vector{Any}(undef, nstmt)
    defined = falses(nstmt)
    blocks = ir.cfg.blocks
    steps = RawStep[]

    bidx = 1
    prev_block = 0
    retval = nothing
    guard = 0
    while 1 <= bidx <= length(blocks)
        guard += 1
        guard > 100_000 && error("IR interpreter exceeded step budget (infinite loop?)")
        blk = blocks[bidx]
        next_block = bidx + 1            # default: fall through
        for pc in blk.stmts.start:blk.stmts.stop
            stmt = ir.stmts[pc][:stmt]
            (val, control) = eval_stmt(stmt, env, argvals, shared_data, prev_block)
            defines = !is_terminator(stmt)
            if defines
                env[pc] = val
                defined[pc] = true
            end
            push!(steps, RawStep(pc, bidx, stmt, defines,
                                  defines ? val : _UNDEF,
                                  snapshot(env, defined, argvals, shared_data)))
            if control isa Returned
                return control.val, steps
            elseif control isa Goto
                next_block = control.target
            end
        end
        prev_block = bidx
        bidx = next_block
    end
    return retval, steps
end
