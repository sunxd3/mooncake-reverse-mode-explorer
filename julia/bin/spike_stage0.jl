# Stage 0 spike: dump real Mooncake IR for the two example functions.
import Pkg
Pkg.activate(@__DIR__)

using Mooncake
const SU = Mooncake.SkillUtils

# --- Example functions -------------------------------------------------------
foo(x) = x[1] + sum(x[2])

function f!(x)
    x .*= x
    return sum(x)
end

const ARTIFACTS = joinpath(@__DIR__, "..", "artifacts")
mkpath(ARTIFACTS)

function spike(label, f, arg)
    println("\n", "="^78)
    println("EXAMPLE: ", label, "   arg::", typeof(arg))
    println("="^78)
    ins = SU.inspect_ir(f, arg; mode=:reverse)
    println("stage_order = ", ins.stage_order)
    println("notes       = ", ins.notes)
    for s in ins.stage_order
        st = ins.stages[s]
        println("\n", "-"^60)
        println("STAGE :", st.name, "  (blocks=", st.meta.block_count,
                " insts=", st.meta.inst_count, " edges=", st.meta.edge_count, ")")
        println("-"^60)
        println(st.text)
    end
    SU.write_ir(ins, joinpath(ARTIFACTS, label))
    return ins
end

ins_foo = spike("foo", foo, (2.0, [1.0, 3.0, 5.0]))
ins_fbang = spike("f_bang", f!, [1.0, 2.0, 3.0])

# --- Inspect the IRCode object structure for the stepper design --------------
println("\n", "#"^78)
println("# IRCode object structure (forward stage of foo)")
println("#"^78)
fwd = ins_foo.stages[:fwd_ir].ir
println("typeof(fwd_ir.ir) = ", typeof(fwd))
println("fieldnames        = ", fieldnames(typeof(fwd)))
println("argtypes          = ", fwd.argtypes)
println("n statements      = ", length(fwd.stmts))
println("\nPer-statement (stmt :: type | line):")
for i in 1:length(fwd.stmts)
    st = fwd.stmts[i]
    println("  %", i, " = ", st[:stmt], "   ::", st[:type], "  [line ", st[:line], "]")
end
println("\ncfg.blocks = ", fwd.cfg.blocks)
