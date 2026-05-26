"""
    MooncakeWalkthrough

Generates real Mooncake reverse-mode AD traces for the interactive walkthrough.
Extracts the genuine forward / reverse `IRCode`, interprets it statement by
statement, and serialises a full debugger trace to JSON.
"""
module MooncakeWalkthrough

using Mooncake
import JSON3

include("examples.jl")
include("render.jl")
include("stepper.jl")
include("ir_export.jl")
include("trace.jl")

export build_trace, examples_manifest

end # module
