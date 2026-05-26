# One-off environment setup: instantiate the pinned dependencies.
import Pkg
Pkg.activate(@__DIR__)
Pkg.instantiate()
Pkg.precompile()
@info "julia/ environment ready"
