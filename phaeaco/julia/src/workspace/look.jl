# Looking at a box: the retina runs, then processes P (perception) and R
# (codelets) share the box's time until its activation falls low enough that
# the box counts as seen (§7.2, §10.3.13–14).

"""
One tick of a box. The first tick runs its retina (DECISIONS D17: the
cognitive level starts once the retina has settled); the ticks that costs
are charged to the box, at `ws_retina_units_per_tick` retinal steps per tick.
Returns false once the box is seen.
"""
function tick!(ws::BoxWS, ctx::Ctx)
    ws.done && return false
    ws.ticks += 1
    r = ws.retina
    if !r.settled
        run_retina!(r)
        init_pending!(ws)
        ws.ticks += ceil(Int, r.now / ctx.P[:ws_retina_units_per_tick])
        root = ws.nodes[ws.root].act
        root.pos = root.steps; root.last = ws.ticks       # the box is fresh when perception starts
        return true
    end
    wP = isempty(ws.pending) ? 0.0 : ctx.P[:ws_p_weight]
    wR = isempty(ws.rack) ? 0.0 : 1.0
    if wP + wR > 0
        rand(ctx.rng) * (wP + wR) < wP ? process_P!(ws, ctx) : process_R!(ws, ctx)
    end
    if ws.ticks >= ctx.P[:ws_min_ticks] && isempty(ws.pending) &&
       value(ws.nodes[ws.root].act, ws.ticks) < sample(thr(ctx.P, :box_done), ctx.rng)
        ws.done = true
        trace(ctx.tracer, 2, ctx.now, "box $(ws.index) seen after", ws.ticks, "ticks,", length(ws.nodes), "nodes")
    end
    return !ws.done
end

"""Look at one box until it is seen (or `maxticks` pass). Advances the global clock."""
function look!(ws::BoxWS, ctx::Ctx; maxticks::Int=100_000)
    while ws.ticks < maxticks && tick!(ws, ctx)
        ctx.now += 1
    end
    return ws
end

"""Build and look at the representation of a single image."""
function represent(img::AbstractMatrix{Bool}, ctx::Ctx; index::Int=1)
    ws = BoxWS(index, img, ctx)
    look!(ws, ctx)
    return ws
end

# --- inspecting a representation ------------------------------------------------------

function _label(ws::BoxWS, n::WNode)
    s = string(n.type)
    n.tag != :none && n.type != :numerosity && (s *= "($(n.tag))")
    if n.type == :numerosity
        s = "$(reported(n)) $(n.tag)"
    elseif n.stats.n > 0
        s *= @sprintf("=%.3g", n.stats.mean)
        n.stats.n > 1 && (s *= " ×$(n.stats.n)")
    end
    return s
end

"""Print the representation as an indented tree, with shared feature nodes marked."""
function show_tree(io::IO, ws::BoxWS; id::Int=ws.root, indent::Int=0)
    n = ws.nodes[id]
    feats = join(["$(f)=$(round(v; sigdigits=3))" for (f, (_, v)) in sort(collect(n.feats); by=first)], " ")
    println(io, "  "^indent, "#", n.id, " ", _label(ws, n), isempty(feats) ? "" : "  [$feats]")
    for c in n.children
        ws.nodes[c].alive || continue
        (ws.nodes[c].stats.n > 0 && ws.nodes[c].type != :numerosity) && continue    # shown inline
        show_tree(io, ws; id=c, indent=indent + 1)
    end
end
show_tree(ws::BoxWS) = show_tree(stdout, ws)
