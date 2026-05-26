# Bake all examples to static JSON for the GH-Pages build.
# Writes web/public/traces/{manifest,trace_*}.json from the current Mooncake code.

include(joinpath(@__DIR__, "..", "src", "MooncakeWalkthrough.jl"))
using .MooncakeWalkthrough
import JSON3

const OUT_DIR = abspath(joinpath(@__DIR__, "..", "..", "web", "public", "traces"))
mkpath(OUT_DIR)

manifest = examples_manifest()
open(joinpath(OUT_DIR, "manifest.json"), "w") do io
    JSON3.write(io, Dict("examples" => manifest))
end
println("wrote manifest.json ($(length(manifest)) examples)")

for ex in manifest
    id = ex["id"]
    inputs = Dict{String,Any}(ex["defaultInputs"])
    seed = Dict{String,Any}(ex["defaultSeed"])
    trace = build_trace(id, inputs, seed)
    fname = "trace_$(id).json"
    open(joinpath(OUT_DIR, fname), "w") do io
        JSON3.write(io, trace)
    end
    println("wrote $fname ($(filesize(joinpath(OUT_DIR, fname))) bytes, " *
            "$(length(trace["events"])) events)")
end
