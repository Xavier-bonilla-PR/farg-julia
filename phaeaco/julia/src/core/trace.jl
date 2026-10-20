# A structured event trace. With no reference implementation to diff against,
# being able to see exactly what a seeded run did is the main debugging tool.

mutable struct Tracer
    io::Union{Nothing,IO}
    level::Int          # 0 = silent, 1 = solver events, 2 = + workspace, 3 = + retina
end

Tracer() = Tracer(nothing, 0)
Tracer(io::IO, level::Integer=1) = Tracer(io, Int(level))

@inline tracing(t::Tracer, level::Integer) = t.io !== nothing && t.level >= level

function trace(t::Tracer, level::Integer, now::Integer, what::AbstractString, args...)
    tracing(t, level) || return nothing
    print(t.io, lpad(now, 7), "  ", what)
    for a in args
        print(t.io, ' ', a)
    end
    println(t.io)
    return nothing
end
