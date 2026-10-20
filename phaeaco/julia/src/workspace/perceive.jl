# Process P (§10.3.13): the interface from retina to Workspace. It picks a
# detector — probabilistically, favouring salient ones — and builds the node
# that stands for it, in the right place in the structure. A line found
# before its object hangs from the box until the object node is built and
# inserted above it (Figs. 7.2–7.3). An isolated line segment hangs from the
# box for good (§7.1 footnote 31).

function init_pending!(ws::BoxWS)
    r = ws.retina
    empty!(ws.pending)
    for o in r.objects
        o.isdot && continue
        _isolated_line(r, o) && continue
        push!(ws.pending, (:object, o.id))
        for (k, _) in enumerate(o.holes)
            push!(ws.pending, (:hole, o.id * 1000 + k))
        end
    end
    for d in r.dots
        push!(ws.pending, (:dot, d.id))
    end
    # Lines that are only the retina's approximation of an ellipse or curve
    # are not perceived as line segments: the identified shape stands for
    # them (§7.4.4, "identified shapes ... replace ... the more general nodes").
    inell = Set{Int}(l for e in r.ellipses for l in e.lines)
    incurve = Set{Int}(l for c in r.curves if !all(in(inell), c.lines) for l in c.lines)
    ws.hidden_lines = union(inell, incurve)
    for l in r.lines
        (l.alive && !(l.id in ws.hidden_lines)) && push!(ws.pending, (:line, l.id))
    end
    for j in r.junctions
        any(l -> !(l in ws.hidden_lines), j.lines) && push!(ws.pending, (:junction, j.id))
    end
    for e in r.ellipses
        push!(ws.pending, (:ellipse, e.id))
    end
    for c in r.curves
        all(in(inell), c.lines) || push!(ws.pending, (:curve, c.id))
    end
    for s in r.strings
        (s.closed && !all(in(inell), s.lines)) && push!(ws.pending, (:string, s.id))
    end
    for (k, _) in enumerate(r.insides)
        push!(ws.pending, (:inside, k))
    end
end

_isolated_line(r::Retina, o::RetObject) =
    length(o.lines) == 1 && isempty(o.ellipses) && isempty(o.holes) && isempty(o.curves) && !o.filled

"""How much P wants to perceive a detector now (0 = not yet possible)."""
function _salience(ws::BoxWS, det::Tuple{Symbol,Int})
    r = ws.retina
    kind, id = det
    has(k, i) = haskey(ws.node_of, (k, i))
    if kind == :object
        return 3.0 + sqrt(r.objects[id].ink) / 3
    elseif kind == :dot
        return 2.0
    elseif kind == :line
        return 1.0 + linelength(r.lines[id]) / 10
    elseif kind == :junction
        return all(l -> l in ws.hidden_lines || has(:line, l), r.junctions[id].lines) ? 1.0 : 0.0
    elseif kind == :ellipse
        return has(:object, r.ellipses[id].comp) ? 4.0 : 0.0
    elseif kind == :curve
        return has(:object, r.curves[id].comp) ? 2.0 : 0.0
    elseif kind == :string
        return has(:object, r.strings[id].comp) ? 2.0 : 0.0
    elseif kind == :hole
        return has(:object, id ÷ 1000) ? 2.0 : 0.0
    elseif kind == :inside
        a, b, _ = r.insides[id]
        return has(:object, a) && has(:object, b) ? 1.5 : 0.0
    end
    return 0.0
end

"""The node a detector's object is represented by, or the box."""
function _context_of(ws::BoxWS, comp::Int)
    get(ws.node_of, (:object, comp), ws.root)
end

"""One step of process P. Returns true if it did something."""
function process_P!(ws::BoxWS, ctx::Ctx)
    isempty(ws.pending) && return false
    w = [_salience(ws, d) for d in ws.pending]
    tot = sum(w)
    if tot <= 0
        # everything left waits on something P will never build (an inside
        # relation of an isolated line, say): nothing more can be perceived
        empty!(ws.pending)
        return false
    end
    u = rand(ctx.rng) * tot
    k = 1
    while u > w[k]
        u -= w[k]
        k += 1
    end
    det = ws.pending[k]
    deleteat!(ws.pending, k)
    perceive!(ws, ctx, det)
    return true
end

function perceive!(ws::BoxWS, ctx::Ctx, det::Tuple{Symbol,Int})
    r = ws.retina
    kind, id = det
    if kind == :object
        n = _newnode!(ws, ctx, :object, ws.root; ret=det)
        # lines and junctions already perceived move under their object
        for l in r.objects[id].lines
            haskey(ws.node_of, (:line, l)) && reparent!(ws, ctx, ws.node_of[(:line, l)], n.id)
        end
        for j in r.objects[id].junctions
            haskey(ws.node_of, (:junction, j)) && reparent!(ws, ctx, ws.node_of[(:junction, j)], n.id)
        end
        post_codelets!(ws, ctx, n.id)
    elseif kind == :dot
        _perceive_counted!(ws, ctx, :dot, ws.root, det)
    elseif kind == :line
        ctxnode = _context_of(ws, r.lines[id].comp)
        _perceive_counted!(ws, ctx, :line, ctxnode, det)
    elseif kind == :junction
        j = r.junctions[id]
        type = j.kind == :V ? :vertex : j.kind == :T ? :touch : j.kind == :X ? :cross : :kpoint
        ctxnode = _context_of(ws, j.comp)
        n = _perceive_counted!(ws, ctx, type, ctxnode, det)
        n === nothing && return
        for l in j.lines
            ln = get(ws.node_of, (:line, l), 0)
            ln == 0 && continue
            push!(n.links, (ln, :meets, 1.0))
            push!(ws.nodes[ln].links, (n.id, :meets, 1.0))
        end
    elseif kind == :ellipse
        e = r.ellipses[id]
        n = _newnode!(ws, ctx, e.circle ? :circle : :ellipse, _context_of(ws, e.comp); ret=det)
        post_codelets!(ws, ctx, n.id)
    elseif kind == :curve
        _perceive_counted!(ws, ctx, :curve, _context_of(ws, r.curves[id].comp), det)
    elseif kind == :string
        s = r.strings[id]
        n = _newnode!(ws, ctx, :line_string, _context_of(ws, s.comp); ret=det, tag=s.closed ? :closed : :open)
        # a perceived whole quells attention to its parts (§7.4.4)
        for l in s.lines
            ln = get(ws.node_of, (:line, l), 0)
            ln == 0 && continue
            push!(n.links, (ln, :part, 1.0))
            damp_codelets!(ws, ln, ctx.P[:ws_string_damping])
        end
        post_codelets!(ws, ctx, n.id)
    elseif kind == :hole
        n = _perceive_counted!(ws, ctx, :interior, _context_of(ws, id ÷ 1000), det; tag=:closed)
    elseif kind == :inside
        a, b, s = r.insides[id]
        add_relation!(ws, ctx, :inside, :contains, ws.node_of[(:object, a)], ws.node_of[(:object, b)], s)
    end
end

"""
Build a node for a detector of a countable type — unless process Q has
already judged there are "many" of that type here, in which case it is only
counted (§10.3.15).
"""
function _perceive_counted!(ws::BoxWS, ctx::Ctx, type::Symbol, context::Int, det; tag=:none)
    if (context, type) in ws.suppressed
        count_item!(ws, ctx, context, -Int(hash(det) % 1_000_000_007) - 1; type=type)
        return nothing
    end
    n = _newnode!(ws, ctx, type, context; ret=det, tag=tag)
    post_codelets!(ws, ctx, n.id)
    # process Q watches the nodes P builds (§10.3.15)
    k = count(c -> ws.nodes[c].type == type, ws.nodes[context].children)
    if exceeds(k, thr(ctx.P, :many), ctx.rng)
        push!(ws.suppressed, (context, type))
        prime!(ctx.ltm, :many, ctx.now, ctx.rng)
        for c in ws.nodes[context].children
            ws.nodes[c].type == type && damp_codelets!(ws, c, ctx.P[:ws_many_damping], keep=:numerosity)
        end
        trace(ctx.tracer, 2, ctx.now, "box $(ws.index) Q many", type, "in #$context")
    end
    return n
end
