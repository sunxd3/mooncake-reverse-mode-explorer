# Example functions whose Mooncake reverse-mode AD we trace.
#
# Each example is baked into a static JSON trace using its default inputs and
# output seed. The un-inlined IR depends on the type signature, while executed
# steps may differ for examples with value-dependent control flow.
#
# To add an example: define the function and append an `ExampleSpec` to
# `EXAMPLES` below — a way to build the argument from baked inputs and the
# output cotangent from the baked seed. Then `npm run bake` to regenerate
# `web/public/traces/`.

"""A mutable cell — used by the mutation example so the in-place update has a
small, readable IR (a vector `.*=` inlines to a 600-statement loop)."""
mutable struct Cell
    v::Float64
end

# --- Example 1: non-mutating, mixed scalar/vector (teaches fdata vs rdata) ----
foo(x) = x[1] + sum(x[2])

# --- Example 2: in-place mutation of a struct field (teaches capture/restore) -
bump!(c::Cell) = (c.v = c.v * c.v; c.v)

# --- Example 3: non-scalar output (teaches the output-side fdata/rdata split) -
# `copy` and `sum` are both Mooncake primitives, so the un-inlined IR stays
# small (fwd 23 / rvs 56) — a vector built with broadcast or `setindex!` would
# inline into hundreds of statements on Julia 1.12.
vpair(x::Vector{Float64}) = (copy(x), sum(x))

# --- Example 4: value-dependent control flow (teaches the block stack) -------
branchy(x::Float64) = x > 0 ? x * x : sin(x)

"""Pad with `1.0` / truncate `v` to length `n` — keeps a cotangent vector
consistent with the input vector length."""
function fit_vector(v::Vector{Float64}, n::Int)
    length(v) == n && return v
    length(v) > n && return v[1:n]
    return vcat(v, fill(1.0, n - length(v)))
end

"""
    ExampleSpec

Static description of one example: how to build its argument and its output
cotangent (seed) from baked inputs, plus display metadata.
"""
struct ExampleSpec
    id::String
    title::String
    description::String
    source::String
    func::Any
    make_arg::Any          # Dict{String,Any} -> argument value
    input_specs::Vector{NamedTuple}
    default_inputs::Dict{String,Any}
    seed_specs::Vector{NamedTuple}     # fields of the output cotangent
    default_seed::Dict{String,Any}
    # (seed_dict, arg) -> (cotangent, effective_seed_dict). The cotangent is a
    # valid Mooncake tangent of the output; the effective dict echoes back any
    # coercion (e.g. a cotangent vector resized to the input vector).
    make_cotangent::Any
end

const EXAMPLES = ExampleSpec[
    ExampleSpec(
        "scalar-vector",
        "Mixed scalar + vector",
        "foo(x) = x[1] + sum(x[2]). The argument is a tuple of a scalar and a " *
        "vector. Watch the scalar gradient travel as rdata (a value, returned) " *
        "while the vector gradient travels as fdata (a buffer, accumulated in place).",
        "foo(x) = x[1] + sum(x[2])",
        foo,
        function (inp)
            x1 = Float64(inp["x1"])
            x2 = Vector{Float64}(inp["x2"])
            return (x1, x2)
        end,
        NamedTuple[
            (name="x1", kind="scalar", label="x[1] (scalar)"),
            (name="x2", kind="vector", label="x[2] (vector)"),
        ],
        Dict{String,Any}("x1" => 2.0, "x2" => [1.0, 3.0, 5.0]),
        NamedTuple[(name="dy", kind="scalar", label="dy (output cotangent)")],
        Dict{String,Any}("dy" => 1.0),
        function (s, arg)
            d = Float64(s["dy"])
            return (d, Dict{String,Any}("dy" => d))
        end,
    ),
    ExampleSpec(
        "mutation",
        "In-place mutation",
        "bump!(c) = (c.v = c.v * c.v; c.v). The field c.v is squared in place. " *
        "The forward pass captures the old value; the reverse pass propagates " *
        "the adjoint through the mutation and then restores c.v.",
        "mutable struct Cell\n    v::Float64\nend\n\nbump!(c::Cell) = (c.v = c.v * c.v; c.v)",
        bump!,
        inp -> Cell(Float64(inp["v"])),
        NamedTuple[(name="v", kind="scalar", label="c.v (scalar field)")],
        Dict{String,Any}("v" => 3.0),
        NamedTuple[(name="dy", kind="scalar", label="dy (output cotangent)")],
        Dict{String,Any}("dy" => 1.0),
        function (s, arg)
            d = Float64(s["dy"])
            return (d, Dict{String,Any}("dy" => d))
        end,
    ),
    ExampleSpec(
        "vector-pair",
        "Vector + scalar output",
        "vpair(x) = (copy(x), sum(x)). The output is a tuple of a vector and a " *
        "scalar, so its cotangent splits the way every Mooncake tangent does: " *
        "the vector half is fdata — seeded into a buffer with increment!! — and " *
        "the scalar half is rdata, passed into the reverse pass as _2.",
        "vpair(x) = (copy(x), sum(x))",
        vpair,
        inp -> Vector{Float64}(inp["x"]),
        NamedTuple[(name="x", kind="vector", label="x (vector)")],
        Dict{String,Any}("x" => [1.0, 2.0, 3.0]),
        NamedTuple[
            (name="dy_vec", kind="vector", label="ȳ[1] — copy(x) cotangent"),
            (name="dy_sum", kind="scalar", label="ȳ[2] — sum cotangent"),
        ],
        Dict{String,Any}("dy_vec" => [1.0, 1.0, 1.0], "dy_sum" => 1.0),
        function (s, arg)
            dv = fit_vector(Vector{Float64}(s["dy_vec"]), length(arg))
            ds = Float64(s["dy_sum"])
            return ((dv, ds), Dict{String,Any}("dy_vec" => dv, "dy_sum" => ds))
        end,
    ),
    ExampleSpec(
        "branch",
        "Branching control flow",
        "branchy(x) = x > 0 ? x * x : sin(x). Mooncake records the forward " *
        "branch choice on stack 1, then pops it in reverse so the pullback " *
        "visits the same block.",
        "branchy(x) = x > 0 ? x * x : sin(x)",
        branchy,
        inp -> Float64(inp["x"]),
        NamedTuple[(name="x", kind="scalar", label="x (scalar)")],
        Dict{String,Any}("x" => 2.0),
        NamedTuple[(name="dy", kind="scalar", label="dy (output cotangent)")],
        Dict{String,Any}("dy" => 1.0),
        function (s, arg)
            d = Float64(s["dy"])
            return (d, Dict{String,Any}("dy" => d))
        end,
    ),
]

get_example(id::AbstractString) =
    something(findfirst(e -> e.id == id, EXAMPLES), 0) == 0 ?
    error("unknown example id: $id") : EXAMPLES[findfirst(e -> e.id == id, EXAMPLES)]

"""Signature `Tuple{typeof(f), typeof(arg)...}` for a built argument value."""
example_signature(spec::ExampleSpec, arg) = Tuple{typeof(spec.func),typeof(arg)}
