# Codelets and the coderack (§6.2.3, §7.1), and process R which runs them
# (§10.3.14).
#
# A node's codelets come from its LTM concept's :feature links (inherited
# down :isa links), each with a base urgency. The urgency is raised by how
# primed the feature's concept is in LTM, so context steers what gets seen
# (§7.1: width, ends and middle "only have a decent chance ... if there are
# contextual pressures").
#
# Selection: a codelet is drawn with probability proportional to urgency
# and then runs with probability (u/100)^γ. Low-urgency codelets therefore
# mostly sit on the rack while time passes and the box's activation decays —
# which is how activity can end "while the coderack is still not empty"
# (§7.2). See DECISIONS D19.

function post_codelets!(ws::BoxWS, ctx::Ctx, id::Int)
    n = ws.nodes[id]
    haskey(ctx.ltm, n.type) || return
    for (f, base) in feature_links(ctx.ltm, n.type)
        haskey(CODELETS, f) || continue
        post!(ws, ctx, f, id, base)
    end
end

function post!(ws::BoxWS, ctx::Ctx, kind::Symbol, id::Int, base::Float64)
    prim = haskey(ctx.ltm, kind) ? cweight(ctx.ltm, kind, ctx.now) : 0.0
    u = base * (1 + ctx.P[:ws_priming_gain] * prim)
    ctxnode = ws.nodes[id].parent
    (kind != :numerosity && (ctxnode, ws.nodes[id].type) in ws.suppressed) && (u *= ctx.P[:ws_many_damping])
    push!(ws.rack, Codelet(kind, id, min(u, 100.0), ws.ticks))
end

"""Lower the urgency of the codelets waiting on a node (a line string quells its lines)."""
function damp_codelets!(ws::BoxWS, id::Int, factor::Float64; keep::Symbol=:none)
    for (k, c) in enumerate(ws.rack)
        (c.node == id && c.kind != keep) && (ws.rack[k] = Codelet(c.kind, c.node, c.urgency * factor, c.born))
    end
end

"""Process R: one turn of the coderack. Returns true if a codelet ran."""
function process_R!(ws::BoxWS, ctx::Ctx)
    isempty(ws.rack) && return false
    tot = sum(c.urgency for c in ws.rack)
    u = rand(ctx.rng) * tot
    k = 1
    while k < length(ws.rack) && u > ws.rack[k].urgency
        u -= ws.rack[k].urgency
        k += 1
    end
    c = ws.rack[k]
    rand(ctx.rng) < (c.urgency / 100)^ctx.P[:ws_urgency_gamma] || return false
    ws.rack[k] = ws.rack[end]
    pop!(ws.rack)
    ws.nodes[c.node].alive || return false
    CODELETS[c.kind](ws, ctx, c.node)
    trace(ctx.tracer, 3, ctx.now, "box $(ws.index) ran", c.kind, "on #$(c.node)")
    return true
end

# --- what each codelet does -------------------------------------------------------

_det(ws::BoxWS, id::Int) = ws.nodes[id].ret

function _obj(ws::BoxWS, id::Int)
    k, i = _det(ws, id)
    k == :object || return nothing
    return ws.retina.objects[i]
end

"""Count the node in its structural parent's numerosity node of its type."""
function cod_numerosity!(ws::BoxWS, ctx::Ctx, id::Int)
    n = ws.nodes[id]
    n.parent == 0 && return
    count_item!(ws, ctx, n.parent, id)
end

function cod_slope!(ws::BoxWS, ctx::Ctx, id::Int)
    k, i = _det(ws, id)
    k == :line || return
    add_feature!(ws, ctx, id, :slope, slope_deg(ws.retina.lines[i].d))
end

function cod_length!(ws::BoxWS, ctx::Ctx, id::Int)
    k, i = _det(ws, id)
    k == :line || return
    add_feature!(ws, ctx, id, :length, linelength(ws.retina.lines[i]))
end

function cod_width!(ws::BoxWS, ctx::Ctx, id::Int)
    k, i = _det(ws, id)
    k == :line || return
    l = ws.retina.lines[i]
    l.src == :endo || return            # the sides of a filled region have no width
    r = ws.retina
    ds = Float64[]
    for p in l.pts
        x, y = round(Int, p[1]), round(Int, p[2])
        _ink(r, x, y) && r.depth[y, x] > 0 && push!(ds, 2r.depth[y, x] - 1)
    end
    isempty(ds) || add_feature!(ws, ctx, id, :width, sum(ds) / length(ds))
end

function _point_of(ws::BoxWS, id::Int)
    n = ws.nodes[id]
    r = ws.retina
    if n.type == :barycenter
        o = _obj(ws, n.parent)
        return o === nothing ? nothing : o.barycenter
    end
    k, i = n.ret
    k == :dot && return r.dots[i].centre
    k == :junction && return r.junctions[i].p
    return nothing
end

function cod_x!(ws::BoxWS, ctx::Ctx, id::Int)
    p = _point_of(ws, id)
    p === nothing || add_feature!(ws, ctx, id, :x, p[1])
end

function cod_y!(ws::BoxWS, ctx::Ctx, id::Int)
    p = _point_of(ws, id)
    # reported with y up, so "higher in the box" is a larger value (D6)
    p === nothing || add_feature!(ws, ctx, id, :y, BOXSIZE + 1 - p[2])
end

"""The angle at an intersection: the angle of a vertex, the acute angle of a touch or cross (§7.4.3)."""
function cod_angle!(ws::BoxWS, ctx::Ctx, id::Int)
    k, i = _det(ws, id)
    k == :junction || return
    j = ws.retina.junctions[i]
    length(j.lines) >= 2 || return
    a, b = ws.retina.lines[j.lines[1]], ws.retina.lines[j.lines[2]]
    if j.kind == :V
        far(l, e) = e == 0 ? midpoint(l) : endpoint(l, 3 - e)
        ang = vertex_angle(j.p, far(a, j.ends[1]), far(b, j.ends[2]))
    else
        ang = 90 - abs(90 - acosd(clamp(a.d[1] * b.d[1] + a.d[2] * b.d[2], -1.0, 1.0)))
    end
    add_feature!(ws, ctx, id, :angle, ang)
end

function cod_size!(ws::BoxWS, ctx::Ctx, id::Int)
    k, i = _det(ws, id)
    k == :dot && add_feature!(ws, ctx, id, :size, Float64(ws.retina.dots[i].size))
end

function cod_texture!(ws::BoxWS, ctx::Ctx, id::Int)
    o = _obj(ws, id)
    o === nothing || add_feature!(ws, ctx, id, :texture, o.filled ? 1.0 : 0.0)
end

"""
Area of an object: the area it covers (ink and enclosed interior) when it
is closed or filled; for open figures — a Λ, a zig-zag — the area of its
convex hull, which "gives a rough idea about how large an object these lines
make" (§7.1, Fig. 7.15). DECISIONS D20.
"""
function cod_area!(ws::BoxWS, ctx::Ctx, id::Int)
    o = _obj(ws, id)
    o === nothing && return
    a = (o.filled || !isempty(o.holes)) ? o.area : max(o.hull_area, Float64(o.ink))
    add_feature!(ws, ctx, id, :area, a)
end

function cod_barycenter!(ws::BoxWS, ctx::Ctx, id::Int)
    _obj(ws, id) === nothing && return
    any(k -> ws.nodes[k].type == :barycenter, ws.nodes[id].children) && return
    n = _newnode!(ws, ctx, :barycenter, id)
    post_codelets!(ws, ctx, n.id)
end

function cod_elongation!(ws::BoxWS, ctx::Ctx, id::Int)
    o = _obj(ws, id)
    o === nothing || add_feature!(ws, ctx, id, :elongation, o.elongation)
end

"""Imagine the convex hull (§5.1.3, §7.1): an imaginary percept, low urgency."""
function cod_convex_hull!(ws::BoxWS, ctx::Ctx, id::Int)
    _obj(ws, id) === nothing && return
    any(k -> ws.nodes[k].type == :convex_hull, ws.nodes[id].children) && return
    n = _newnode!(ws, ctx, :convex_hull, id)
    post_codelets!(ws, ctx, n.id)
end

"""
How much of the hull the object does not fill (§7.4.6), attached to the
object. If it is a fair amount, the concavity is perceived as an (open)
interior of the object (§7.4.7, Fig. 7.38).
"""
function cod_missing!(ws::BoxWS, ctx::Ctx, id::Int)
    obj = ws.nodes[id].parent
    o = _obj(ws, obj)
    o === nothing && return
    add_feature!(ws, ctx, obj, :missing, o.missing)
    if o.missing > ctx.P[:retina_concavity_min] &&
       !any(k -> ws.nodes[k].type == :interior && ws.nodes[k].tag == :concavity, ws.nodes[obj].children)
        n = _newnode!(ws, ctx, :interior, obj; ret=(:object, o.id), tag=:concavity)
        post_codelets!(ws, ctx, n.id)
    end
end

"""
A line string's sides (Fig. 7.30): it carries the count of its lines, so the
count survives the string's damping of its lines' own codelets.
"""
function cod_sides!(ws::BoxWS, ctx::Ctx, id::Int)
    n = ws.nodes[id]
    for (ln, kind, _) in n.links
        kind == :part && count_item!(ws, ctx, n.parent, ln)
    end
end

function cod_eccentricity!(ws::BoxWS, ctx::Ctx, id::Int)
    k, i = _det(ws, id)
    k == :ellipse && add_feature!(ws, ctx, id, :eccentricity, ws.retina.ellipses[i].ecc)
end

function cod_openness!(ws::BoxWS, ctx::Ctx, id::Int)
    n = ws.nodes[id]
    if n.tag == :closed
        add_feature!(ws, ctx, id, :openness, 0.0)
    elseif n.tag == :concavity
        o = ws.retina.objects[n.ret[2]]
        add_feature!(ws, ctx, id, :openness, o.openness)
    end
end

"""
The sameness detector (§7.4.10, "Sam" in GEB): make the implicit equality of
a shared feature node explicit, and if every node of that type in their
context shares it, add the for-all quantifier: "all objects have similar
texture" (Fig. 7.52). The for-all's tag names the quantified type and the
feature (`:object_texture`); it points to the Platonic feature, not to the
specific value.
"""
function cod_equality!(ws::BoxWS, ctx::Ctx, fnode::Int)
    f = ws.nodes[fnode]
    ftype = f.type
    for type in unique(ws.nodes[k].type for k in f.sharers)
        members = [k for k in f.sharers if ws.nodes[k].type == type && ws.nodes[k].alive]
        length(members) >= 2 || continue
        context = ws.nodes[members[1]].parent
        all(k -> ws.nodes[k].parent == context, members) || (context = ws.root)
        tag = Symbol(type, "_", ftype)
        if !any(n -> n.alive && n.type == :equality && any(l -> l[1] == fnode, n.links), ws.nodes)
            eq = _newnode!(ws, ctx, :equality, ws.root; tag=tag)
            push!(eq.links, (fnode, :value, 1.0))
            foreach(k -> push!(eq.links, (k, :member, 1.0)), members)
        end
        # all of them? (the for-all codelet has high urgency once a group exists; run it at once)
        everyone = context == ws.root ? descendants(ws, ws.root, type) :
                   [c for c in ws.nodes[context].children if ws.nodes[c].type == type && ws.nodes[c].alive]
        if length(everyone) == length(members) &&
           !any(n -> n.alive && n.type == :forall && n.tag == tag, ws.nodes)
            _newnode!(ws, ctx, :forall, ws.root; tag=tag)
            prime!(ctx.ltm, :forall, ctx.now, ctx.rng)
        end
    end
end

const CODELETS = Dict{Symbol,Function}(
    :numerosity => cod_numerosity!, :slope => cod_slope!, :length => cod_length!,
    :width => cod_width!, :x => cod_x!, :y => cod_y!, :angle => cod_angle!, :size => cod_size!,
    :texture => cod_texture!, :area => cod_area!, :barycenter => cod_barycenter!,
    :elongation => cod_elongation!, :convex_hull => cod_convex_hull!, :missing => cod_missing!,
    :eccentricity => cod_eccentricity!, :openness => cod_openness!, :sides => cod_sides!,
    :equality => cod_equality!)
