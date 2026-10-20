# Solving a Bongard problem (ch. 11).
#
# 1. Holistic stage (§11.1.2). All twelve boxes are looked at in parallel,
#    time divided finely among them. A pattern of each side is compared with
#    the other's, feature by feature and count by count. A difference whose
#    distributions are clearly distinct is likely to become an idea. A
#    discrete feature with zero variance on both sides and different values
#    ends the search at once, without verification (§11.1.1, BP #3).
# 2. Verification (§11.1.2). Each box is looked at again; the two looks are
#    merged; the idea must hold on every box, with the two sides' values not
#    overlapping. Near-misses earn a few more looks at the failing boxes
#    (§11.1.3, BP #192).
# 3. Analytic stage (§11.1.3). Boxes are re-examined one at a time, simpler
#    ones more often; ideas come from what is seen in that box, specific ones
#    before general ones. Ideas already verified and failed are recognised and
#    not verified again. Each new idea adds to the activation of the master
#    node of ideas; with no new ideas that activation decays, and when it
#    falls low enough Phaeaco gives up ("motivation").

struct SolveResult
    answer::Union{Nothing,Idea}
    stage::Symbol               # :hardwired, :holistic, :analytic, :analogy (X14), or :none
    ticks::Int
    ideas::Int                  # distinct ideas verified
    log::Vector{String}
end

mutable struct Solver
    ctx::Ctx
    bp::BP
    boxpat::Vector{RNode}       # each box's pattern: the looks at it so far, merged
    nlooks::Vector{Int}
    failed::Vector{Idea}        # the master node of failed ideas (Fig. 11.8) ...
    failstrength::Vector{Float64}   # ... and the strength of each one's link
    motivation::Activation
    ticks::Int
    nideas::Int
    log::Vector{String}
    core::Any                   # the problem's core, for the memory of solved problems (X14)
end

function Solver(bp::BP, ctx::Ctx)
    P = ctx.P
    Solver(ctx, bp, RNode[], zeros(Int, 12), Idea[], Float64[],
           Activation(Int(P[:solve_motivation_steps]), Int(P[:solve_motivation_period])),
           0, 0, String[], nothing)
end

_note(s::Solver, msg) = (push!(s.log, "$(s.ticks): $msg"); trace(s.ctx.tracer, 1, s.ticks, msg))

"""A side's six box patterns."""
side(s::Solver, left::Bool) = left ? s.boxpat[1:6] : s.boxpat[7:12]

function _absorb!(s::Solver, i::Int, e::RNode)
    M = Matcher(s.ctx)
    if s.nlooks[i] == 0
        s.boxpat[i] = pattern_of(e)
    else
        update!(M, s.boxpat[i], e)
    end
    s.nlooks[i] += 1
end

# --- looking ------------------------------------------------------------------------------

"""Holistic look: all twelve boxes, their time interleaved finely (§11.1.2)."""
function look_all!(s::Solver)
    ctx = s.ctx
    wss = [BoxWS(i, s.bp.boxes[i], ctx) for i in 1:12]
    active = collect(1:12)
    while !isempty(active)
        k = rand(ctx.rng, eachindex(active))
        before = wss[active[k]].ticks
        tick!(wss[active[k]], ctx) || deleteat!(active, k)
        ctx.now += 1
    end
    s.ticks += sum(ws.ticks for ws in wss)
    s.boxpat = [RNode(:box) for _ in 1:12]
    for i in 1:12
        e = exemplar(wss[i])
        if ctx.P[:ext_enabled] > 0 && ctx.P[:ext_holistic] > 0
            s.ticks += Int(ctx.P[:ext_tick_cost]) * extend!(e, wss[i], ctx)
        end
        _absorb!(s, i, e)
    end
end

"""
Look at one box again. With an idea in focus, its concepts are primed and
whatever the idea needs that the look did not perceive is perceived
directly, top-down ("quickly looking at each box", §5.1.1).
"""
function look_box!(s::Solver, i::Int; focus::Union{Nothing,Idea}=nothing)
    ctx = s.ctx
    focus === nothing || prime_idea!(ctx, focus; marks=10)
    ws = BoxWS(i, s.bp.boxes[i], ctx; analytic=true)
    look!(ws, ctx)
    focus === nothing || attend!(ws, ctx, focus)
    s.ticks += ws.ticks
    e = exemplar(ws)
    if ctx.P[:ext_enabled] > 0
        s.ticks += Int(ctx.P[:ext_tick_cost]) * extend!(e, ws, ctx; focus=focus)
        # a closer look at cores corrects the glance rather than averaging with it (X17)
        if ctx.P[:ext_core_focus] > 0 && _corefocus(focus) && s.nlooks[i] > 0
            foreach(n -> foreach(f -> delete!(n.feats, f), CORE_FEATURES), _alldesc(s.boxpat[i]))
        end
    end
    _absorb!(s, i, e)
    return e
end

function prime_idea!(ctx::Ctx, idea::Idea; marks::Int=5)
    for c in (idea.what, idea.path...)
        haskey(ctx.ltm, c) && prime!(ctx.ltm, c, ctx.now, ctx.rng; marks=marks)
    end
    idea.kind == :count && prime!(ctx.ltm, :numerosity, ctx.now, ctx.rng; marks=marks)
    idea.kind == :same && prime!(ctx.ltm, :equality, ctx.now, ctx.rng; marks=marks)
end

"""Perceive, top-down, what an idea needs and the look did not provide."""
function attend!(ws::BoxWS, ctx::Ctx, idea::Idea)
    nodes_at(path) = begin
        cur = [ws.root]
        for t in path
            cur = [c for n in cur for c in parts(ws, n) if ws.nodes[c].type == t]
        end
        cur
    end
    if idea.kind in (:feature, :same)
        f = idea.what
        if idea.path == [:object, :barycenter]
            foreach(o -> cod_barycenter!(ws, ctx, o), nodes_at([:object]))
        end
        for n in nodes_at(idea.path)
            haskey(ws.nodes[n].feats, f) && continue
            if f == :missing
                cod_convex_hull!(ws, ctx, n)
                for h in ws.nodes[n].children
                    ws.nodes[h].type == :convex_hull && cod_missing!(ws, ctx, h)
                end
            elseif haskey(CODELETS, f)
                CODELETS[f](ws, ctx, n)
            end
        end
    elseif idea.kind == :count
        if idea.path == [:deep]
            for n in ws.nodes
                (n.alive && n.type == idea.what && n.parent != 0) && cod_numerosity!(ws, ctx, n.id)
            end
        else
            for n in nodes_at(idea.path), c in parts(ws, n)
                ws.nodes[c].type == idea.what && cod_numerosity!(ws, ctx, c)
            end
        end
    elseif idea.kind == :exists && idea.what == :forall
        # look for the sameness directly: measure the feature on every node of
        # the type, then let the sameness detector look at each shared node
        type, f = split_forall(idea.tag)
        for n in descendants(ws, ws.root, type)
            haskey(ws.nodes[n].feats, f) || (haskey(CODELETS, f) && CODELETS[f](ws, ctx, n))
        end
        for n in collect(ws.nodes)
            (n.alive && n.type == f) && cod_equality!(ws, ctx, n.id)
        end
    elseif idea.kind == :exists && idea.what == :category
        foreach(o -> cod_category!(ws, ctx, o), nodes_at([:object]))
    elseif idea.kind == :exists && idea.tag == :concavity
        for o in nodes_at([:object])
            cod_convex_hull!(ws, ctx, o)
            for h in ws.nodes[o].children
                ws.nodes[h].type == :convex_hull && cod_missing!(ws, ctx, h)
            end
        end
    end
end

# --- forming ideas -----------------------------------------------------------------------

"""(path, feature) pairs and (path, counted type) pairs present in the box patterns."""
function _paths(s::Solver)
    feats = Set{Tuple{Vector{Symbol},Symbol}}()
    counts = Set{Tuple{Vector{Symbol},Symbol}}()
    kinds = Set{Tuple{Symbol,Symbol}}()
    function walk(r::RNode, path::Vector{Symbol})
        for f in keys(r.feats)
            push!(feats, (copy(path), f))
        end
        for t in keys(r.nums)
            push!(counts, (copy(path), t))
            push!(counts, ([:deep], t))
        end
        path == [] || push!(kinds, (r.type, r.tag))
        length(path) >= 3 && return
        for c in r.children
            walk(c, vcat(path, c.type))
        end
    end
    foreach(b -> walk(b, Symbol[]), s.boxpat)
    return feats, counts, kinds
end

const _NOT_EXISTENTIAL = (:box, :barycenter, :convex_hull, :line_string, :contains, :equality)
# relations, contrasts and groups are derived descriptions, not things that exist in a box
_notexist(t::Symbol) = t in _NOT_EXISTENTIAL || basetype(t) in (:pair, :contrast, :group)

"""`:object_texture` → (:object, :texture)."""
function split_forall(tag::Symbol)
    s = string(tag)
    i = findfirst('_', s)
    return Symbol(s[1:i-1]), Symbol(s[i+1:end])
end

"""
Separate the two sides on the values an `:all` idea would look at: every
left value below every right value, or the reverse. Returns the idea or
nothing.
"""
function _split_all(kind, path, what, L::Vector{Float64}, R::Vector{Float64}, nl::Int, nr::Int;
                    minboxes::Int=6)
    (nl >= minboxes && nr >= minboxes) || return nothing
    if maximum(L) < minimum(R)
        return Idea(kind, path, what, :none, :all, (maximum(L) + minimum(R)) / 2, true)
    elseif maximum(R) < minimum(L)
        return Idea(kind, path, what, :none, :all, (maximum(R) + minimum(L)) / 2, false)
    end
    return nothing
end

"""
Separate the sides by a `:some` idea: each box of one side has an instance
beyond a split that no instance of the other side passes (BP #21: "there is
a small object on the left").
"""
function _split_some(path, what, perbox::Vector{Vector{Float64}}; minboxes::Int=6)
    count(!isempty, perbox[1:6]) >= minboxes && count(!isempty, perbox[7:12]) >= minboxes || return nothing
    mins = [isempty(v) ? NaN : minimum(v) for v in perbox]
    maxs = [isempty(v) ? NaN : maximum(v) for v in perbox]
    for (low, mark) in ((true, :left), (true, :right), (false, :left), (false, :right))
        marked = filter(i -> !isempty(perbox[i]), mark == :left ? (1:6) : (7:12))
        other = filter(i -> !isempty(perbox[i]), mark == :left ? (7:12) : (1:6))
        (isempty(marked) || isempty(other)) && continue
        if low
            a, b = maximum(mins[marked]), minimum(mins[other])     # marked boxes reach lower than any other instance
            a < b && return Idea(:feature, path, what, mark, :some, (a + b) / 2, true)
        else
            a, b = minimum(maxs[marked]), maximum(maxs[other])
            a > b && return Idea(:feature, path, what, mark, :some, (a + b) / 2, false)
        end
    end
    return nothing
end

"""
Candidate ideas from comparing the sides' patterns, each with a salience:
the probability that the two sides' distributions differ (§11.1.2) times the
LTM weight of what is compared (footnote 85: texture before coordinates).
"""
function pattern_candidates(s::Solver; some::Bool=false)
    ctx = s.ctx
    M = Matcher(ctx)
    out = Tuple{Idea,Float64,Bool}[]          # (idea, salience, zero-variance discrete?)
    feats, counts, kinds = _paths(s)
    for (path, f) in feats
        info = haskey(ctx.ltm, f) ? ctx.ltm[f].feature : nothing
        info === nothing && continue
        probe = Idea(:feature, path, f, :none, :all, 0.0, true)
        perbox = [idea_values(probe, b) for b in s.boxpat]
        L = reduce(vcat, perbox[1:6]); R = reduce(vcat, perbox[7:12])
        nl, nr = count(!isempty, perbox[1:6]), count(!isempty, perbox[7:12])
        (isempty(L) || isempty(R)) && continue
        sL, sR = Stats(), Stats()
        foreach(v -> push!(sL, v), L); foreach(v -> push!(sR, v), R)
        p = difference_probability(M, sL, sR, info)
        w = mweight(M, f)
        idea = _split_all(:feature, path, f, L, R, nl, nr; minboxes=Int(ctx.P[:solve_holistic_boxes]))
        if idea !== nothing
            # the hardwired shortcut of BP #3 is for built-in percepts, not PhaeacoX's
            zerovar = info.discrete && !(f in EXT_FEATURES) && variance(sL) == 0 && variance(sR) == 0 && sL.mean != sR.mean
            push!(out, (idea, p * w, zerovar))
        elseif some
            idea = _split_some(path, f, perbox; minboxes=Int(ctx.P[:solve_holistic_boxes]))
            idea === nothing || push!(out, (idea, 0.5 * p * w, false))
        end
    end
    wn = mweight(M, :numerosity)
    for (path, t) in counts
        probe = Idea(:count, path, t, :none, :all, 0.0, true)
        perbox = [idea_values(probe, b) for b in s.boxpat]
        L = reduce(vcat, perbox[1:6]); R = reduce(vcat, perbox[7:12])
        nl, nr = count(!isempty, perbox[1:6]), count(!isempty, perbox[7:12])
        (isempty(L) || isempty(R)) && continue
        idea = _split_all(:count, path, t, L, R, nl, nr; minboxes=Int(ctx.P[:solve_holistic_boxes]))
        idea === nothing && continue
        sL, sR = Stats(), Stats()
        foreach(v -> push!(sL, v), L); foreach(v -> push!(sR, v), R)
        p = numerosity_difference(M, sL, sR)
        push!(out, (idea, p * wn * sqrt(mweight(M, t)), false))
    end
    # "nothing vs something" (§11.1.1): any thing at all in the box
    let fl = count(b -> !isempty(b.children), s.boxpat[1:6]) / 6, fr = count(b -> !isempty(b.children), s.boxpat[7:12]) / 6
        abs(fl - fr) >= 0.99 && push!(out, (Idea(:exists, Symbol[], :thing, :any, :all, 0.0, fl > fr), mweight(M, :object), false))
    end
    for (t, tag) in union(kinds, Set((g, :none) for g in keys(KIND_OF)))
        _notexist(t) && continue
        has(b) = any(n -> iskind(n.type, t) && n.tag == tag, _alldesc(b))
        fl = count(has, s.boxpat[1:6]) / 6
        fr = count(has, s.boxpat[7:12]) / 6
        if t == :category || basetype(t) == :shape
            # categorising is a codelet, so a concept is seen in only some
            # boxes on one look; seen on one side only, it is worth verifying,
            # weighted by how significant the concept is (D41)
            (min(fl, fr) == 0 && max(fl, fr) >= 0.5) || continue
            push!(out, (Idea(:exists, Symbol[], t, tag, :all, 0.0, fl > fr), mweight(M, tag) * max(fl, fr), false))
            continue
        end
        abs(fl - fr) >= 0.99 || continue
        push!(out, (Idea(:exists, Symbol[], t, tag, :all, 0.0, fl > fr), mweight(M, t), false))
    end
    return out
end

"""
Ideas suggested by what one box shows (§11.1.3): a feature or count of some
node in it, or the presence of some kind of thing. Each is formed only if
the boxes seen so far are consistent with it; specific counts come before
general ones ("Could this problem be about counting lines?" before
"counting things in general?").
"""
function box_ideas(s::Solver, e::RNode; ext::Bool=false)
    ctx = s.ctx
    out = Idea[]
    # pick a node of the box, favouring the salient
    nodes = Tuple{RNode,Vector{Symbol}}[]
    function walk(r, path)
        push!(nodes, (r, path))
        length(path) >= 3 && return
        foreach(c -> walk(c, vcat(path, c.type)), r.children)
    end
    walk(e, Symbol[])
    # PhaeacoX: attend to one of the extended percepts of this look
    isext(n) = basetype(n.type) in (:shape, :mark, :pair, :contrast, :group)
    if ext
        # shape kinds are noisy, so only all twelve boxes together (the
        # holistic comparison) may suggest "some circle vs no circle"
        filter!(((n, _),) -> basetype(n.type) == :mark || any(in(EXT_FEATURES), keys(n.feats)), nodes)
    else
        filter!(((n, _),) -> !isext(n), nodes)      # ordinary attention is PhaeacoJL's
    end
    isempty(nodes) && return out
    M = Matcher(ctx)
    # salient nodes catch attention more often: a for-all node is a
    # "structural curiosity" (§7.4.10), a line one of many
    nw = [mweight(M, n.type) for (n, _) in nodes]
    u = rand(ctx.rng) * sum(nw)
    j = 1
    while j < length(nodes) && u > nw[j]
        u -= nw[j]; j += 1
    end
    (r, path) = nodes[j]
    opts = Tuple{Symbol,Symbol,Float64}[]           # (kind, what, weight)
    for f in keys(r.feats)
        (ext != (f in EXT_FEATURES)) && continue
        push!(opts, (:feature, f, mweight(M, f)))
    end
    for t in keys(r.nums)
        ext && break
        push!(opts, (:count, t, mweight(M, :numerosity) * sqrt(mweight(M, t))))
    end
    path == [] || _notexist(r.type) || push!(opts, (:exists, r.type, mweight(M, r.type)))
    isempty(opts) && return out
    tot = sum(last, opts)
    u = rand(ctx.rng) * tot
    k = 1
    while k < length(opts) && u > opts[k][3]
        u -= opts[k][3]; k += 1
    end
    kind, what, _ = opts[k]
    if kind == :feature
        probe = Idea(:feature, path, what, :none, :all, 0.0, true)
        perbox = [idea_values(probe, b) for b in s.boxpat]
        L = reduce(vcat, perbox[1:6]); R = reduce(vcat, perbox[7:12])
        nl, nr = count(!isempty, perbox[1:6]), count(!isempty, perbox[7:12])
        if !isempty(L) && !isempty(R)
            # one box can suggest an idea; verification will look at them all
            idea = _split_all(:feature, path, what, L, R, nl, nr; minboxes=1)
            idea === nothing && (idea = _split_some(path, what, perbox; minboxes=1))
            # PhaeacoX: an idea about cores may be formed despite one box that
            # contradicts it; verification looks at cores closely and may see
            # that box otherwise (X17)
            if idea === nothing && ext && ctx.P[:ext_core_focus] > 0 && what in CORE_FEATURES
                for k in 1:12
                    isempty(perbox[k]) && continue
                    pb = copy(perbox); pb[k] = Float64[]
                    L2 = reduce(vcat, pb[1:6]); R2 = reduce(vcat, pb[7:12])
                    (isempty(L2) || isempty(R2)) && continue
                    idea = _split_all(:feature, path, what, L2, R2, count(!isempty, pb[1:6]),
                                      count(!isempty, pb[7:12]); minboxes=1)
                    idea === nothing || break
                end
            end
            idea === nothing || push!(out, idea)
        end
    elseif kind == :count
        for p in (path, [:deep])                     # specific, then general
            probe = Idea(:count, p, what, :none, :all, 0.0, true)
            perbox = [idea_values(probe, b) for b in s.boxpat]
            L = reduce(vcat, perbox[1:6]); R = reduce(vcat, perbox[7:12])
            nl, nr = count(!isempty, perbox[1:6]), count(!isempty, perbox[7:12])
            (isempty(L) || isempty(R)) && continue
            idea = _split_all(:count, p, what, L, R, nl, nr; minboxes=1)
            idea === nothing || push!(out, idea)
        end
    else
        # present here and in none of the other side's boxes seen so far — as
        # its own kind, then as the more general kinds it is a case of
        # (a circle, then an ellipse, then a curve)
        for k in (what, (g for (g, ks) in KIND_OF if what in ks && g != what)...)
            has(b) = any(n -> iskind(n.type, k) && n.tag == r.tag, _alldesc(b))
            fl, fr = count(has, s.boxpat[1:6]), count(has, s.boxpat[7:12])
            if (fl >= 1 && fr == 0) || (fl == 0 && fr >= 1)
                push!(out, Idea(:exists, Symbol[], k, r.tag, :all, 0.0, fl >= 1))
            end
        end
    end
    return out
end

# --- verifying -------------------------------------------------------------------------------

"""Has this idea already been verified and failed? Seeing it again strengthens its link."""
function already_failed!(s::Solver, idea::Idea)
    for (k, f) in enumerate(s.failed)
        if same_idea(f, idea)
            s.failstrength[k] = min(1.0, s.failstrength[k] + 0.1)
            return true
        end
    end
    return false
end

"""
Verify an idea on every box (§11.1.2): look again, merge the looks, check.
Boxes are taken in random order and the attempt stops at the third failure.
If at most two boxes failed, they get a few more looks (§11.1.3, BP #192).
"""
function verify!(s::Solver, idea::Idea)
    ctx = s.ctx
    s.nideas += 1
    _note(s, "verifying $idea")
    prime_idea!(ctx, idea; marks=5)
    failing = Int[]
    for i in randperm(ctx.rng, 12)
        look_box!(s, i; focus=idea)
        satisfies(idea, s.boxpat[i], i <= 6) || push!(failing, i)
        length(failing) > Int(ctx.P[:solve_max_failing]) && break
    end
    if !isempty(failing) && length(failing) <= Int(ctx.P[:solve_max_failing])
        for _ in 1:Int(ctx.P[:solve_persistence]), i in copy(failing)
            look_box!(s, i; focus=idea)
            satisfies(idea, s.boxpat[i], i <= 6) && filter!(!=(i), failing)
            isempty(failing) && break
        end
    end
    ok = isempty(failing)
    _note(s, ok ? "verified" : "failed on boxes $(join(boxlabel.(failing), ", "))")
    if !ok
        push!(s.failed, idea)
        push!(s.failstrength, 1.0)
    end
    return ok
end

# --- the whole run -----------------------------------------------------------------------------

function _pick(rng, cands, γ)
    w = [max(c[2], 0.0)^γ for c in cands]
    tot = sum(w)
    tot <= 0 && return nothing
    u = rand(rng) * tot
    for (k, c) in enumerate(cands)
        u -= w[k]
        u <= 0 && return c
    end
    return cands[end]
end

"""
    solve(bp, ctx) -> SolveResult

Run Phaeaco's solver on a BP: holistic stage, then analytic stage until a
verified idea or loss of motivation.
"""
function solve(bp::BP, ctx::Ctx)
    s = Solver(bp, ctx)
    r = _solve!(s)
    # PhaeacoX: remember the solved problem (X14)
    if ctx.P[:ext_memory] > 0 && r.answer !== nothing && s.core !== nothing
        push!(ctx.ltm.episodes, Episode(bp.name, s.core, r.answer))
    end
    return r
end

function _solve!(s::Solver)
    ctx = s.ctx
    bp = s.bp
    P = ctx.P
    look_all!(s)
    _note(s, "holistic look done")
    P[:ext_memory] > 0 && (s.core = problem_core(s))
    # --- hardwired: nothing vs something (BP #1, §11.1.1)
    emptyL = all(b -> isempty(b.children), s.boxpat[1:6])
    emptyR = all(b -> isempty(b.children), s.boxpat[7:12])
    if emptyL != emptyR && all(b -> !isempty(b.children), emptyL ? s.boxpat[7:12] : s.boxpat[1:6])
        idea = Idea(:exists, Symbol[], :thing, :any, :all, 0.0, emptyR)
        _note(s, "one side empty: $idea")
        return SolveResult(idea, :hardwired, s.ticks, 0, s.log)
    end
    # --- PhaeacoX: spontaneous analogy with a solved problem (X14)
    if P[:ext_memory] > 0
        idea = analogy!(s)
        idea === nothing || return SolveResult(idea, :analogy, s.ticks, s.nideas, s.log)
    end
    # --- holistic stage
    cands = pattern_candidates(s)
    for (idea, _, zerovar) in cands
        if zerovar
            _note(s, "zero variance on both sides: $idea")
            return SolveResult(idea, :hardwired, s.ticks, 0, s.log)
        end
    end
    sharp = filter(c -> c[2] >= P[:solve_holistic_min], cands)
    c = _pick(ctx.rng, sharp, P[:solve_idea_gamma])
    if c !== nothing
        idea = c[1]
        prime_idea!(ctx, idea)
        verify!(s, idea) && return SolveResult(idea, :holistic, s.ticks, s.nideas, s.log)
    end
    # --- analytic stage
    _note(s, "analytic stage")
    s.motivation.pos = s.motivation.steps
    s.motivation.last = s.ticks
    simple(i) = 1 / nnodes(s.boxpat[i])
    while s.ticks < P[:solve_max_ticks]
        value(s.motivation, s.ticks) < sample(thr(P, :solve_bored), ctx.rng) && break
        w = [simple(i) for i in 1:12]
        u = rand(ctx.rng) * sum(w)
        i = findfirst(k -> (u -= w[k]) <= 0, 1:12)
        e = look_box!(s, i === nothing ? 12 : i)
        # a look is costly; if the node attended to suggests nothing new,
        # attention moves to another part of the same look (D43)
        ideas = Idea[]
        for _ in 1:Int(P[:solve_picks_per_look])
            ideas = box_ideas(s, e)
            any(idea -> !any(f -> same_idea(f, idea), s.failed), ideas) && break
        end
        # PhaeacoX: besides PhaeacoJL's attention, the look's extended percepts
        if P[:ext_enabled] > 0 && rand(ctx.rng) < P[:ext_pick_prob]
            for _ in 1:Int(P[:solve_picks_per_look])
                xi = box_ideas(s, e; ext=true)
                if any(idea -> !any(f -> same_idea(f, idea), s.failed), xi)
                    append!(ideas, xi)
                    break
                end
            end
        end
        if rand(ctx.rng) < P[:solve_pattern_prob]
            c = _pick(ctx.rng, pattern_candidates(s; some=true), P[:solve_idea_gamma])
            c === nothing || push!(ideas, c[1])
        end
        for idea in ideas
            already_failed!(s, idea) && continue
            boost!(s.motivation, s.ticks, Int(P[:solve_new_idea_marks]))
            prime_idea!(ctx, idea)
            verify!(s, idea) && return SolveResult(idea, :analytic, s.ticks, s.nideas, s.log)
        end
    end
    _note(s, "gave up")
    return SolveResult(nothing, :none, s.ticks, s.nideas, s.log)
end

"""Solve with a fresh context (LTM at its starting state) seeded by `seed`."""
solve(bp::BP, P::Params, seed::Integer; tracer=Tracer()) = solve(bp, Ctx(P, seed; tracer=tracer))
