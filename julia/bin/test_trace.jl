# Stage 1 smoke test: build traces for both examples and check correctness.
import Pkg
Pkg.activate(joinpath(@__DIR__, ".."))
include(joinpath(@__DIR__, "..", "src", "MooncakeWalkthrough.jl"))
using .MooncakeWalkthrough
import JSON3

const ART = joinpath(@__DIR__, "..", "..", "artifacts")

function check(label, id, inputs, seed)
    println("\n", "="^70, "\n", label, "\n", "="^70)
    t = build_trace(id, inputs, seed)
    c = t["counts"]
    println("steps: forward=", c["forward"], " reverse=", c["reverse"], " total=", c["total"])
    println("primal value: ", t["result"]["primalValue"])
    println("gradient:     ", JSON3.write(t["result"]["gradient"]))
    for chk in t["result"]["checks"]
        println("check [", chk["passed"] ? "PASS" : "FAIL", "] ", chk["name"])
        haskey(chk, "got") && println("   got =", chk["got"], "  want=", chk["want"])
        haskey(chk, "error") && println("   error: ", chk["error"])
    end
    nrestore = count(s -> s["phase"] == "restore", t["steps"])
    println("restore-phase steps: ", nrestore)
    open(joinpath(ART, "trace_$(id).json"), "w") do io
        JSON3.write(io, t)
    end
    println("wrote artifacts/trace_$(id).json  (", filesize(joinpath(ART, "trace_$(id).json")), " bytes)")
    return t
end

t1 = check("Example 1: scalar-vector", "scalar-vector",
           Dict("x1" => 2.0, "x2" => [1.0, 3.0, 5.0]), Dict{String,Any}())
t2 = check("Example 2: mutation", "mutation", Dict("v" => 3.0), Dict{String,Any}())
t3 = check("Example 3: vector-pair", "vector-pair",
           Dict("x" => [1.0, 2.0, 3.0]), Dict{String,Any}())

# Show the first few forward steps of example 1.
println("\n", "-"^70, "\nfirst 6 forward steps of example 1:")
for s in t1["steps"][1:6]
    println("  #", s["index"], " [", s["phase"], "] ", s["text"])
end
println("\nlast 4 reverse steps of example 1:")
for s in t1["steps"][end-3:end]
    println("  #", s["index"], " [", s["phase"], "] ", s["text"])
end
println("\nrestore steps of example 2:")
for s in t2["steps"]
    s["phase"] == "restore" && println("  #", s["index"], " ", s["text"])
end
