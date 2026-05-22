# Minimal HTTP service: serves example metadata and on-demand traces so the web
# app can re-run real Mooncake AD whenever the user edits inputs.

const _CORS = [
    "Access-Control-Allow-Origin" => "*",
    "Access-Control-Allow-Methods" => "GET, POST, OPTIONS",
    "Access-Control-Allow-Headers" => "Content-Type",
]

json_response(obj; status=200) =
    HTTP.Response(status, ["Content-Type" => "application/json", _CORS...],
                  JSON3.write(obj))

function examples_handler(_req)
    return json_response(Dict("examples" => examples_manifest()))
end

function trace_handler(req)
    try
        body = JSON3.read(String(req.body))
        example_id = String(body.exampleId)
        inputs = Dict{String,Any}(String(k) => _plain(v) for (k, v) in pairs(body.inputs))
        seed = haskey(body, :seed) ?
               Dict{String,Any}(String(k) => _plain(v) for (k, v) in pairs(body.seed)) :
               Dict{String,Any}()
        return json_response(build_trace(example_id, inputs, seed))
    catch err
        @error "trace request failed" exception = (err, catch_backtrace())
        return json_response(
            Dict("error" => sprint(showerror, err)); status=400)
    end
end

# JSON3 values -> plain Julia (numbers / vectors of numbers).
_plain(v::JSON3.Array) = [_plain(e) for e in v]
_plain(v) = v

function router()
    r = HTTP.Router()
    HTTP.register!(r, "GET", "/api/health", _ -> json_response(Dict("ok" => true)))
    HTTP.register!(r, "GET", "/api/examples", examples_handler)
    HTTP.register!(r, "POST", "/api/trace", trace_handler)
    return r
end

# Answer CORS preflight before routing.
function _wrap(handler)
    return function (req)
        req.method == "OPTIONS" && return HTTP.Response(204, _CORS)
        return handler(req)
    end
end

"""
    serve(; host="127.0.0.1", port=8754)

Start the trace HTTP server (blocking).
"""
function serve(; host="127.0.0.1", port=8754)
    r = router()
    @info "Mooncake walkthrough trace server" host port
    return HTTP.serve(_wrap(r), host, port)
end
