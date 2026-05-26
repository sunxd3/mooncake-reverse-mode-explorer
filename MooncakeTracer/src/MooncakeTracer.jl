"""
    MooncakeTracer

Produces Mooncake reverse-mode AD traces as JSON event streams. Extracts the
forward / reverse `IRCode`, interprets it statement by statement, and emits a
trace consumed by the Mooncake Explorer web viewer (or any other consumer of
the schema).

Format spec: `/schema/trace.v1.schema.json`. The emitter in `src/events.jl` and
the TypeScript replay in `web/src/lib/replay.ts` both implement this spec by
hand — keep them in sync.

Public API:
- [`build_trace`](@ref) — run AD for one example, return the trace Dict
- [`examples_manifest`](@ref) — list the baked examples + their defaults
- [`bake`](@ref) — regenerate the static traces under `web/public/traces/`
"""
module MooncakeTracer

using Mooncake
import JSON3

include("examples.jl")
include("ir_export.jl")
include("stepper.jl")
include("render.jl")
include("events.jl")
include("replay.jl")
include("trace.jl")

export build_trace, examples_manifest, bake

end # module
