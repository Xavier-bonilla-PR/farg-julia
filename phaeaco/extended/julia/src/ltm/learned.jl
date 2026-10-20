# Learning and remembering (ch. 9): concepts formed from visual patterns,
# found again through the LTM index, used to categorise what is seen,
# associations that harden into relations, and forgetting.

"""
Indexical keys of an object's representation (§9.4.1): its counts (how many
lines, vertices, interiors …) and the kinds of part it has (a circle, a
closed interior). A rectangle and a trapezoid share most of their keys; a
triangle shares few with either.
"""
function index_keys(r::RNode)
    keys = Tuple{Symbol,Int}[]
    for (t, s) in r.nums
        push!(keys, (t, round(Int, s.mean)))
    end
    for c in r.children
        c.type in (:circle, :ellipse, :curve, :interior) &&
            push!(keys, (c.tag == :none ? c.type : Symbol(c.type, "_", c.tag), 1))
    end
    return unique(keys)
end

"""
Candidates for matching a representation: concepts whose indexical nodes it
activates, each inactive key of a concept inhibiting it a little, so a
trapezoid activates "trapezoid" more than "rectangle" (§9.4.1). Returns the
concepts above the activation threshold, best first. The index may include
more candidates than necessary but must not miss the closest one (§9.4.1),
so a partly counted representation (two of a triangle's three vertices)
still retrieves "triangle".
"""
function retrieve(ltm::LTM, r::RNode; inhibition::Float64=0.2, threshold::Float64=0.0)
    keys = Set(index_keys(r))
    out = Tuple{Float64,LearnedConcept}[]
    for lc in ltm.learned
        isempty(lc.keys) && continue
        hit = count(in(keys), lc.keys)
        miss = length(lc.keys) - hit
        a = (hit - inhibition * miss) / length(lc.keys)
        a >= threshold && push!(out, (a, lc))
    end
    sort!(out; by=x -> -x[1])
    return [lc for (_, lc) in out]
end

"""
Learn from an object exemplar (§9.2). With a label (the Mentor's word for
it), the concept of that name is updated, or begun. Without one, the
exemplar updates the best-matching retrieved concept if it is similar
enough, and otherwise founds a new, unnamed concept. Returns the concept.
"""
function learn!(ctx::Ctx, e::RNode; label::Union{Nothing,Symbol}=nothing)
    ltm = ctx.ltm
    # what the exemplar was already categorised as is not part of its shape
    e = copy(e)
    filter!(c -> c.type != :category, e.children)
    M = Matcher(ctx)
    target = nothing
    if label !== nothing && haskey(ltm, label)
        target = findfirst(lc -> ltm[lc.id].name == label, ltm.learned)
        target = target === nothing ? nothing : ltm.learned[target]
    elseif label === nothing
        for lc in retrieve(ltm, e)
            if similarity(M, lc.core, e) > sample(thr(ctx.P, :clustering), ctx.rng)
                target = lc
                break
            end
        end
    end
    if target === nothing
        name = label === nothing ? Symbol("concept_", length(ltm.learned) + 1) : label
        c = add_concept!(ltm, name, :object; depth=30, now=ctx.now, P=ctx.P)
        link!(ltm, name, :isa, :object)
        target = LearnedConcept(c.id, pattern_of(e), index_keys(e))
        push!(ltm.learned, target)
    else
        update!(M, target.core, e)
        target.keys = index_keys(target.core)
    end
    # being taught something is significant in itself: the long-term part of
    # the concept's weight grows with each example, not only when its
    # activation happens to max out (D41)
    w = ltm[target.id].w
    prime!(w, ctx.now, Int(ctx.P[:ltm_learn_marks]))
    boost!(w.sig, ctx.now, Int(ctx.P[:ltm_learn_sig_marks]))
    return target
end

"""
The categorisation codelet: is this object an instance of a learned
concept? Candidates come from the index; the best whose core matches closely
enough is attached as a category node, and primed (ch. 9, §8.4: pattern
matching as categorisation).
"""
function cod_category!(ws::BoxWS, ctx::Ctx, id::Int)
    ltm = ctx.ltm
    isempty(ltm.learned) && return
    any(k -> ws.nodes[k].type == :category, ws.nodes[id].children) && return
    e = exemplar(ws, id)
    # wait until the object's parts are counted: a sparse early representation
    # can resemble the wrong concept. The codelet puts itself back on the rack
    # (a few times at most), as FARG codelets do when their input is not ready.
    if any(c -> c.type in (:line, :vertex) && !haskey(e.nums, c.type), e.children)
        tries = get!(ws.retries, (id, :category), 0)
        if tries < 3
            ws.retries[(id, :category)] = tries + 1
            post!(ws, ctx, :category, id, 45.0)
            return
        end
    end
    M = Matcher(ctx)
    sims = [(similarity(M, lc.core, e), lc) for lc in retrieve(ltm, e)]
    isempty(sims) && return
    sort!(sims; by=x -> -x[1])
    bests, best = sims[1]
    if ctx.P[:ltm_gcm] > 0
        gcm_choice(ctx, [s for (s, _) in sims]) || return
    else
        second = length(sims) >= 2 ? sims[2][1] : 0.0
        # a clear best match, not merely a passable one (D41)
        (bests > sample(thr(ctx.P, :category_match), ctx.rng) && bests - second >= ctx.P[:ltm_category_margin]) || return
    end
    name = ltm[best.id].name
    _newnode!(ws, ctx, :category, id; tag=name)
    prime!(ltm[best.id].w, ctx.now, 2)
    _associate!(ws, ctx, best.id)
end
CODELETS[:category] = cod_category!

"""
Categorisation by the Generalized Context Model (Nosofsky 1986, as Foundalis
2013 describes it; X13). Each concept's similarity `s` to the object (a
pattern, so already the hybrid of exemplar and prototype the report asks
for) is sharpened to `s^c`, and the best concept J is chosen with the
probability of Luce's rule, `P(J|i) = s_J / (β + Σ_K s_K)`. β is the
similarity of a concept the object does not belong to, `ltm_gcm_base^c`:
without it a lone concept would win every object. One decision, sampled
against `category_p`, replaces D41's threshold and margin: a weak match and
a close runner-up both lower P. Takes the similarities, best first.
"""
function gcm_choice(ctx::Ctx, sims::Vector{Float64})
    c = ctx.P[:ltm_gcm_c]
    ss = sims .^ c
    p = ss[1] / (ctx.P[:ltm_gcm_base]^c + sum(ss))
    return p > sample(thr(ctx.P, :category_p), ctx.rng)
end

"""
Concepts that turn up together become associated (§9.3.2): each
co-occurrence in a box primes their anonymous association; when its weight
passes a threshold it is reified as a relation concept, which can then be
referred to and matched like any other.
"""
function _associate!(ws::BoxWS, ctx::Ctx, cid::Int)
    ltm = ctx.ltm
    others = unique(ltm.byname[ws.nodes[k].tag] for k in eachindex(ws.nodes)
                    if ws.nodes[k].alive && ws.nodes[k].type == :category && haskey(ltm.byname, ws.nodes[k].tag))
    for o in others
        o == cid && continue
        key = (min(o, cid), max(o, cid))
        # an association is long-term learning: its activation fades ten times
        # more slowly than a concept's momentary priming (D41)
        w = get!(ltm.assoc, key) do
            Weight(; act_steps=Int(ctx.P[:ltm_act_steps]), act_period=10 * Int(ctx.P[:ltm_act_period]),
                   sig_steps=Int(ctx.P[:ltm_sig_steps]), sig_period=Int(ctx.P[:ltm_sig_period]), now=ctx.now)
        end
        prime!(w, ctx.now, 8)
        rel = Symbol("with_", ltm[key[1]].name, "_", ltm[key[2]].name)
        # repetition, not one strong moment: the association's long-term part
        # must have grown through several peaks of its activation
        if sync!(w.sig, ctx.now).pos >= ctx.P[:ltm_relation_marks] && !haskey(ltm, rel)
            add_concept!(ltm, rel, :relation; depth=50, now=ctx.now, P=ctx.P)
            link2!(ltm, ltm[key[1]].name, :similar, rel)
            link2!(ltm, ltm[key[2]].name, :similar, rel)
        end
    end
end

# --- the Mentor (§5.2) ------------------------------------------------------------------

"""
A Mentor lesson: each drawing is looked at, and its largest object is
learned under the given label. (The thesis's Mentor pairs drawings with
phrases and learns word–percept associations; that linguistic system was
unfinished and unpublished, so here a label names the concept — DECISIONS
D41.)
"""
function mentor!(ctx::Ctx, images::Vector{BitMatrix}, labels::Vector{Symbol})
    for (img, lab) in zip(images, labels)
        ws = represent(img, ctx)
        objs = [k for k in parts(ws, ws.root) if ws.nodes[k].type == :object]
        isempty(objs) && continue
        o = argmax(k -> (r = _obj(ws, k); r === nothing ? 0 : r.ink), objs)
        learn!(ctx, exemplar(ws, o); label=lab)
        ctx.now += ws.ticks
    end
end

"""
A synthetic lesson: `n` random polygons with `k` sides (or circles for
k = 0), of varied size, orientation, texture and place, so that what the
concept's pattern keeps steady is the shape (§7.1: "invariant ... in various
sizes, orientations, locations").
"""
function lesson(k::Int, n::Int; seed=1, label::Symbol)
    rng = Xoshiro(seed)
    imgs = BitMatrix[]
    for _ in 1:n
        r = 10 + 25rand(rng)
        c = (r + 6 + (88 - 2r) * rand(rng), r + 6 + (88 - 2r) * rand(rng))
        s = k == 0 ? circle(c, r; filled=rand(rng, Bool)) :
            random_polygon(rng, k, c, r; irreg=0.35, filled=rand(rng, Bool))
        push!(imgs, render([s]))
    end
    return imgs, fill(label, n)
end

# --- remembering and forgetting (§9.4.2) --------------------------------------------------

"""
Save the learned part of LTM. Concepts whose significance and activation have
both decayed to the floor are unreachable and are not saved: that is how
Phaeaco forgets (§9.4.2.2). Uses Julia's Serialization; the file is a
snapshot, not an interchange format.
"""
function save_ltm(path::AbstractString, ctx::Ctx)
    ltm = ctx.ltm
    keep = [lc for lc in ltm.learned if (w = ltm[lc.id].w; sync!(w.sig, ctx.now).pos > 0 || sync!(w.act, ctx.now).pos > 0)]
    data = [(ltm[lc.id].name, lc.core, lc.keys, ltm[lc.id].w.sig.pos, ltm[lc.id].w.sig.steps) for lc in keep]
    open(io -> serialize(io, data), path, "w")
    return length(keep)
end

"""Load learned concepts saved by `save_ltm` into a context's LTM."""
function load_ltm!(path::AbstractString, ctx::Ctx)
    data = open(deserialize, path)
    for (name, core, keys, pos, steps) in data
        haskey(ctx.ltm, name) && continue
        c = add_concept!(ctx.ltm, name, :object; depth=30, now=ctx.now, P=ctx.P)
        link!(ctx.ltm, name, :isa, :object)
        c.w.sig.pos = pos
        c.w.sig.steps = steps
        c.w.sig.last = ctx.now
        push!(ctx.ltm.learned, LearnedConcept(c.id, core, keys))
    end
    return length(data)
end
