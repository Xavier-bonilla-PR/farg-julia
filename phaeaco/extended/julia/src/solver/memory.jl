# A memory of solved problems, and spontaneous analogy (Foundalis 2013,
# "Spontaneity of Analogy Making", Fig. 9; ../../DECISIONS.md X14).
#
# When a problem is solved, its core is stored with the answer: an episode.
# The core is what remains of the problem once its details are worn away —
# which kinds of thing its boxes show, and how widely — with each dimension
# weighted by the LTM weight of its concept (the report's w_k, "suppressing
# some dimensions and magnifying others"). When a new problem has been
# looked at, its core is categorised among the stored ones, as an object is
# categorised among concepts (GCM, X13). Nobody asks for an analogy: if the
# new core falls near an old one, the old answer comes to mind, its concepts
# are primed, and it is tried first, refitted to the new boxes.

"""A solved problem: its name, its core, and the idea that solved it."""
struct Episode
    name::String
    core::Dict{String,Tuple{Float64,Float64}}   # dimension => (fraction of boxes showing it, weight)
    answer::Idea
end

_key(path, what) = string(join(path, '/'), ':', what)

"""
The core of a problem after its holistic look: for each feature at a place
and each kind of node in the box patterns, the fraction of the twelve boxes
that show it, and the LTM weight of its concept.
"""
function problem_core(s::Solver)
    M = Matcher(s.ctx)
    feats, _, kinds = _paths(s)
    core = Dict{String,Tuple{Float64,Float64}}()
    n = length(s.boxpat)
    for (path, f) in feats
        probe = Idea(:feature, path, f, :none, :all, 0.0, true)
        fr = count(b -> !isempty(idea_values(probe, b)), s.boxpat) / n
        core[_key(path, f)] = (fr, mweight(M, f))
    end
    # counts are left out: whether a count is there says whether the counting
    # codelets finished on that look (D38), not what the boxes show, and it
    # made the same problem's cores differ by a third from look to look
    for (t, tag) in kinds
        _notexist(t) && continue
        fr = count(b -> any(x -> x.type == t && x.tag == tag, _alldesc(b)), s.boxpat) / n
        core[_key([t], tag)] = (fr, mweight(M, basetype(t)))
    end
    return core
end

"""Weighted distance between two cores, in [0, 1]: a dimension one core lacks counts as shown by no box."""
function episode_distance(a::Dict{String,Tuple{Float64,Float64}}, b::Dict{String,Tuple{Float64,Float64}})
    num = den = 0.0
    for k in union(keys(a), keys(b))
        fa, wa = get(a, k, (0.0, 0.0))
        fb, wb = get(b, k, (0.0, 0.0))
        w = max(wa, wb)
        num += w * abs(fa - fb)
        den += w
    end
    return den == 0 ? 1.0 : num / den
end

"""
The solved problems the new core reminds of, most probable first. GCM over
the stored episodes (X13): episodes with the same answer (whatever its
split and sides) form one category, whose similarity is the sum of its
members', and β is the similarity of a core at `ext_memory_base`. The new
core activates every category, "the nearer, the higher" (Foundalis 2013);
those whose probability passes a fresh draw of `ext_memory_p`, at most
`ext_memory_recall` of them, come to mind. Returns `(nearest episode of
the category, probability)` pairs.
"""
function remind(ctx::Ctx, core)
    eps = ctx.ltm.episodes
    out = Tuple{Episode,Float64}[]
    isempty(eps) && return out
    c = ctx.P[:ext_memory_c]
    sims = [exp(-c * episode_distance(core, e.core)) for e in eps]
    sig(i::Idea) = (i.kind, i.path, i.what, i.tag, i.quant)
    tot = Dict{Any,Float64}()
    for (e, x) in zip(eps, sims)
        tot[sig(e.answer)] = get(tot, sig(e.answer), 0.0) + x
    end
    den = exp(-c * ctx.P[:ext_memory_base]) + sum(sims)
    for (cat, x) in sort(collect(tot); by=t -> -t[2])[1:min(end, Int(ctx.P[:ext_memory_recall]))]
        p = x / den
        p > sample(thr(ctx.P, :ext_memory_p), ctx.rng) || break
        k = argmax(i -> sig(eps[i].answer) == cat ? sims[i] : -1.0, eachindex(eps))
        push!(out, (eps[k], p))
    end
    return out
end

"""
The remembered idea refitted to this problem's box patterns. Its place
and kind may *slip*: any place in the new boxes whose node types differ
from the old one's only in their tags (`contrast@filled_outlined` →
`contrast@filledcircle_outlinedcircle`, `shape@triangle` → `shape@circle`)
is a candidate, as Copycat lets one concept slip into a neighbouring one.
Each candidate's split is recomputed (feature and count ideas, either
direction) or its sides chosen (existence and sameness). Returns the
candidate that the boxes, as seen so far, bear out in most boxes, if that
is at least `ext_memory_fit` of twelve; otherwise nothing.
"""
function transfer(s::Solver, old::Idea)
    nb = Int(s.ctx.P[:solve_holistic_boxes])
    feats, counts, kinds = _paths(s)
    bases(p) = basetype.(p)
    cands = Idea[]
    if old.kind in (:feature, :count)
        places = old.kind == :feature ? feats : counts
        for (path, what) in places
            (length(path) == length(old.path) && bases(path) == bases(old.path) &&
             basetype(what) == basetype(old.what)) || continue
            probe = Idea(old.kind, path, what, :none, :all, 0.0, true)
            perbox = [idea_values(probe, b) for b in s.boxpat]
            if old.quant == :all
                L = reduce(vcat, perbox[1:6]); R = reduce(vcat, perbox[7:12])
                (isempty(L) || isempty(R)) && continue
                i = _split_all(old.kind, path, what, L, R, count(!isempty, perbox[1:6]),
                               count(!isempty, perbox[7:12]); minboxes=nb)
            else
                i = old.kind == :feature ? _split_some(path, what, perbox; minboxes=nb) : nothing
            end
            i === nothing || push!(cands, i)
        end
    else
        whats = old.kind == :exists ? unique([t for (t, _) in kinds if basetype(t) == basetype(old.what)]) : Symbol[]
        old.what in whats || push!(whats, old.what)
        tags = old.kind == :exists && old.tag != :none && old.tag != :any ?
               unique([tag for (t, tag) in kinds if t == old.what]) : Symbol[old.tag]
        for w in whats, tg in (w == old.what ? tags : [old.tag]), ll in (true, false)
            push!(cands, Idea(old.kind, old.path, w, tg, old.quant, old.thr, ll))
        end
    end
    isempty(cands) && return nothing
    fit(i) = count(k -> satisfies(i, s.boxpat[k], k <= 6), 1:12)
    best = argmax(fit, cands)
    return fit(best) >= s.ctx.P[:ext_memory_fit] ? best : nothing
end

"""Prime what an idea is about, untagged too (`pair@circle_triangle` primes `pair`)."""
function prime_remembered!(ctx::Ctx, idea::Idea; marks::Int=5)
    prime_idea!(ctx, idea; marks=marks)
    for c in (idea.what, idea.path...)
        b = basetype(c)
        b != c && haskey(ctx.ltm, b) && prime!(ctx.ltm, b, ctx.now, ctx.rng; marks=marks)
    end
end

"""
Spontaneous analogy, after the holistic look: each solved problem this
one's core reminds of is refitted in turn to these boxes; the first the
boxes bear out has its answer primed, in proportion to how strongly it is
recalled, and is verified before anything else. Returns the
verified idea or nothing.
"""
function analogy!(s::Solver)
    for (ep, p) in remind(s.ctx, s.core)
        _note(s, @sprintf("reminded of %s (P = %.2f): %s", ep.name, p, ep.answer))
        idea = transfer(s, ep.answer)
        if idea === nothing
            _note(s, "the boxes do not bear it out")
            continue
        end
        # only an analogy the boxes bear out primes its concepts: priming
        # every recalled answer steered later problems' attention (X14)
        prime_remembered!(s.ctx, ep.answer; marks=max(1, round(Int, p * s.ctx.P[:ext_memory_marks])))
        same_idea(idea, ep.answer) || _note(s, "slipped to $idea")
        verify!(s, idea) && return idea
    end
    return nothing
end

# --- answer comparison, as Metacat does it (X18) -------------------------------------------
#
# Metacat (Marshall 1999, §5.2.3; ../../../metacat/julia/src/memory.jl) is
# reminded AFTER it finds an answer, and by the answer, not by the problem:
# each stored answer is compared with the new one by the themes the two rest
# on and the rules that state them, and the reminding strength is
# 100 − 100 · min(1, distance / 5). A theme there is a dimension with a
# relation on it (alphabetic position: opposite). Two identical answers are
# 0 apart; otherwise the distance is 1, plus 1 for a dimension both answers
# hold with different relations, plus 2 for each theme only one of them has,
# plus 2 when their rules differ. Here an answer's one theme has as its
# dimension the kind of idea, the kind of node it is about and its feature's
# concept (an object's area, a pair's `above`), and as its relation the
# quantifier and direction; its "rule" is the specific tags
# (`pair@circle_triangle`, `shape@triangle`) that say which things. Answers
# about different dimensions are therefore 5 apart: no reminding, as in
# Metacat.

"""An idea's theme: its dimension and the relation on it."""
answer_theme(i::Idea) = ((i.kind, isempty(i.path) ? :box : basetype(i.path[end]), basetype(i.what)),
                         (i.quant, i.leftlow))

"""An idea's specifics: the tags that name which things it is about."""
answer_tags(i::Idea) = (tagof.(i.path)..., tagof(i.what), i.tag)

"""Metacat's answer distance (`calculate-answer-distance`), for PhaeacoX's ideas."""
function answer_distance(a::Idea, b::Idea)
    same_idea(a, b) && return 0
    (da, ra), (db, rb) = answer_theme(a), answer_theme(b)
    themes = da == db ? (ra == rb ? 0 : 1) : 2 + 2
    rule = answer_tags(a) == answer_tags(b) ? 0 : 2
    return 1 + themes + rule
end

"""How strongly one answer reminds of another, as Metacat's `compare` puts it (0–100)."""
answer_reminding(a::Idea, b::Idea) = 100 - round(Int, 100 * min(1, answer_distance(a, b) / 5))

"""
After an answer is found: the earlier answer it most strongly reminds of, as
Metacat's commentary has it ("This answer strongly reminds me of …"), or
nothing. Returns `(episode, strength)`.
"""
function answer_reminded(ctx::Ctx, answer::Idea)
    best = nothing
    for e in ctx.ltm.episodes
        x = answer_reminding(e.answer, answer)
        x > 0 && (best === nothing || x > best[2]) && (best = (e, x))
    end
    return best
end
