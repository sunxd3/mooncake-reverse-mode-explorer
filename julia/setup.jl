# One-off environment setup: develop the vendored Mooncake and instantiate deps.
import Pkg
Pkg.activate(@__DIR__)
Pkg.develop(; path=joinpath(@__DIR__, "..", "vendor", "Mooncake.jl"))
Pkg.add(["JSON3", "HTTP"])
Pkg.instantiate()
Pkg.precompile()
@info "julia/ environment ready"
