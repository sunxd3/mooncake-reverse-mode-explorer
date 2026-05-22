# Start the Mooncake walkthrough trace server.
#   julia julia/bin/serve.jl [port]
import Pkg
Pkg.activate(joinpath(@__DIR__, ".."))
include(joinpath(@__DIR__, "..", "src", "MooncakeWalkthrough.jl"))
using .MooncakeWalkthrough

port = isempty(ARGS) ? 8754 : parse(Int, ARGS[1])

# Warm the IR cache so the first browser request is fast. An empty seed dict
# falls back to each example's default cotangent.
@info "warming trace cache…"
build_trace("scalar-vector", Dict("x1" => 2.0, "x2" => [1.0, 3.0, 5.0]), Dict{String,Any}())
build_trace("mutation", Dict("v" => 3.0), Dict{String,Any}())
build_trace("vector-pair", Dict("x" => [1.0, 2.0, 3.0]), Dict{String,Any}())
@info "ready"

serve(; port=port)
