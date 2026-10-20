# Long-term memory: the conceptual network (ch. 9), starting from the
# "hard-wired" Platonic primitives the Workspace needs (§7.1, §7.4).
#
# A concept has a weight = significance + activation (§9.3.1). Links have
# types. Three matter from phase 3 on:
#
#   :isa      dot → point. Properties are inherited down these links (§7.4.1).
#   :feature  line → slope, with an urgency. When a Workspace node of a type is
#             built, codelets are posted for every feature linked to its
#             concept or inherited from its ancestors. This is the thesis's answer
#             to "who decides which codelets a line segment gives rise to?" (§7.1).
#   :opposite small ↔ large, inside ↔ outside, line ↔ curve. Activation spreads
#             across these, which is how priming "inside" leads to noticing
#             "outside" (§7.4.7) and "line" slips to "curve" (§6.2, BP #24).

"""A feature's scale: what distance counts as "the same" and the largest value (Eq. 8.1)."""
struct FeatureInfo
    maxval::Float64         # max(f) in Eq. 8.1
    eqtol::Float64          # values closer than this share a Workspace node (§7.1, Fig. 7.7)
    relative::Bool          # eqtol is relative to the value, not absolute
    discrete::Bool
    period::Float64         # > 0 for a circular feature: slope wraps at 180° (D36)
end

FeatureInfo(maxval, eqtol, relative, discrete) = FeatureInfo(maxval, eqtol, relative, discrete, 0.0)

"""Distance between two values of a feature, the short way round if it is circular."""
function fdist(info::FeatureInfo, a::Real, b::Real)
    d = abs(a - b)
    info.period > 0 && (d = mod(d, info.period); d = min(d, info.period - d))
    return d
end

"""`v` moved by whole periods to lie within half a period of `ref` (so means stay coherent)."""
function unwrap(info::FeatureInfo, v::Real, ref::Real)
    info.period > 0 || return Float64(v)
    p = info.period
    return v + p * round((ref - v) / p)
end

mutable struct Concept
    id::Int
    name::Symbol
    kind::Symbol            # :object, :feature, :numerosity, :relation, :quantifier, :abstract
    depth::Float64          # conceptual depth, 0–100: deeper concepts decay more slowly
    w::Weight
    links::Vector{Tuple{Int,Symbol,Float64}}    # (target, link type, urgency or strength)
    feature::Union{Nothing,FeatureInfo}
end

"""
A concept learned from what was seen (§9.2): its core structure is a visual
pattern, and its indexical keys — copies of its numerosity and relational
nodes — let a new representation find it without matching every concept in
turn (§9.4.1).
"""
mutable struct LearnedConcept
    id::Int                     # its Concept (name, weight, links) in the network
    core::RNode                 # the core structure: a pattern of object exemplars
    keys::Vector{Tuple{Symbol,Int}}
end

mutable struct LTM
    concepts::Vector{Concept}
    byname::Dict{Symbol,Int}
    learned::Vector{LearnedConcept}
    assoc::Dict{Tuple{Int,Int},Weight}      # anonymous associations between concepts (§9.3.2)
    episodes::Vector{Any}                   # solved problems (PhaeacoX, solver/memory.jl, X14)
end

LTM() = LTM(Concept[], Dict{Symbol,Int}(), LearnedConcept[], Dict{Tuple{Int,Int},Weight}(), Any[])

Base.getindex(m::LTM, name::Symbol) = m.concepts[m.byname[name]]
Base.getindex(m::LTM, id::Int) = m.concepts[id]
Base.haskey(m::LTM, name::Symbol) = haskey(m.byname, name)

function add_concept!(m::LTM, name::Symbol, kind::Symbol; depth=20.0, feature=nothing,
                      sig_pos=0, now=0, P::Union{Nothing,Params}=nothing)
    period = round(Int, (P === nothing ? 30.0 : P[:ltm_act_period]) * (1 + depth / 25))
    w = Weight(; act_steps=P === nothing ? 20 : Int(P[:ltm_act_steps]), act_period=period,
               sig_steps=P === nothing ? 200 : Int(P[:ltm_sig_steps]),
               sig_period=P === nothing ? 5000 : Int(P[:ltm_sig_period]),
               sig_pos=sig_pos, now=now)
    c = Concept(length(m.concepts) + 1, name, kind, Float64(depth), w, Tuple{Int,Symbol,Float64}[], feature)
    push!(m.concepts, c)
    m.byname[name] = c.id
    return c
end

link!(m::LTM, a::Symbol, kind::Symbol, b::Symbol, x::Real=1.0) =
    push!(m[a].links, (m.byname[b], kind, Float64(x)))

"""Link both ways (for symmetric relations: opposite, similar)."""
function link2!(m::LTM, a::Symbol, kind::Symbol, b::Symbol, x::Real=1.0)
    link!(m, a, kind, b, x)
    link!(m, b, kind, a, x)
end

"""Ancestors along :isa links, nearest first, the concept itself included."""
function lineage(m::LTM, name::Symbol)
    out = Symbol[name]
    i = 1
    while i <= length(out)
        for (t, k, _) in m[out[i]].links
            k == :isa || continue
            n = m.concepts[t].name
            n in out || push!(out, n)
        end
        i += 1
    end
    return out
end

"""
The codelets a node of this type gives rise to: `(feature concept, urgency)`
for every :feature link of the concept or an ancestor. A nearer link
overrides an inherited one for the same feature.
"""
function feature_links(m::LTM, name::Symbol)
    out = Dict{Symbol,Float64}()
    for anc in lineage(m, name)
        for (t, k, u) in m[anc].links
            k == :feature || continue
            f = m.concepts[t].name
            haskey(out, f) || (out[f] = u)
        end
    end
    return out
end

isakind(m::LTM, a::Symbol, b::Symbol) = b in lineage(m, a)

"""Current weight of a concept: significance + activation (§9.3.1, Eq. 8.7's wᵢ)."""
cweight(m::LTM, name::Symbol, now::Int) = weight(m[name].w, now)

"""
Prime a concept, and spread a fraction of it to neighbours along :opposite,
:similar and :isa links (§6.2.1). Spreading is in whole activation marks,
probabilistically, so a single prime of "inside" sometimes reaches
"outside" and sometimes does not.
"""
function prime!(m::LTM, name::Symbol, now::Int, rng::AbstractRNG; marks::Int=1, spread::Float64=0.3)
    c = m[name]
    prime!(c.w, now, marks)
    for (t, k, _) in c.links
        k in (:opposite, :similar, :isa) || continue
        for _ in 1:marks
            rand(rng) < spread && prime!(m.concepts[t].w, now, 1)
        end
    end
end

"""
The primitive network. Urgencies (0–100) follow the qualitative ordering of
§7.1: slope and length of a line segment very high, its count medium, its
width, ends and middle very low; texture high (§11.1.1); the convex hull low
(§7.1, Fig. 7.8); barycenter coordinates "almost always" run once the
barycenter exists. Values not given by the thesis are DECISIONS D18.
"""
function build_primitives(P::Params; now::Int=0)
    m = LTM()
    F(maxval, eqtol; relative=false, discrete=false, period=0.0) = FeatureInfo(maxval, eqtol, relative, discrete, period)
    obj(n, d=20) = add_concept!(m, n, :object; depth=d, now=now, P=P)
    feat(n, info, d=15) = add_concept!(m, n, :feature; depth=d, feature=info, now=now, P=P)
    # objects and their hierarchy
    for n in (:box, :object, :point, :dot, :barycenter, :intersection, :vertex, :touch, :cross, :kpoint,
              :linear_structure, :line, :curve, :line_string, :circle, :ellipse, :interior, :convex_hull)
        obj(n, n in (:point, :linear_structure, :intersection) ? 40 : 20)
    end
    link!(m, :dot, :isa, :point); link!(m, :barycenter, :isa, :point)
    link!(m, :intersection, :isa, :point)
    for n in (:vertex, :touch, :cross, :kpoint)
        link!(m, n, :isa, :intersection)
    end
    for n in (:line, :curve, :line_string)
        link!(m, n, :isa, :linear_structure)
    end
    link!(m, :circle, :isa, :ellipse); link!(m, :ellipse, :isa, :curve)
    # features (max value, "same" tolerance)
    feat(:slope, F(90.0, 6.0; period=180.0))      # lines at 178° and 2° are parallel
    feat(:length, F(141.4, 0.07; relative=true))
    feat(:width, F(10.0, 1.0))
    feat(:texture, F(1.0, 0.5; discrete=true), 25)
    feat(:angle, F(180.0, 5.0))
    feat(:area, F(10000.0, 0.18; relative=true))      # "same size": shapes of one extent differ ~30% in area (D43)
    feat(:x, F(100.0, 5.0))
    feat(:y, F(100.0, 5.0))
    feat(:size, F(30.0, 0.25; relative=true))
    feat(:elongation, F(1.0, 0.06))
    feat(:openness, F(1.0, 0.1))
    feat(:missing, F(1.0, 0.05))
    feat(:eccentricity, F(1.0, 0.08))
    add_concept!(m, :numerosity, :numerosity; depth=35, now=now, P=P)
    # PhaeacoX's extended percepts (src/ext/extend.jl)
    for n in (:shape, :mark, :pair, :contrast, :group, :cluster)
        obj(n)
    end
    feat(:vert, F(1.0, 0.1))
    feat(:endgap, F(1.0, 0.08)); feat(:endangle, F(90.0, 8.0))
    feat(:above, F(1.0, 0.05)); feat(:larger, F(5.0, 0.15)); feat(:inside, F(1.0, 0.5; discrete=true))
    feat(:diff, F(10.0, 0.5; discrete=true)); feat(:depth, F(5.0, 0.5; discrete=true))
    feat(:simmin, F(1.0, 0.5; discrete=true)); feat(:simmax, F(1.0, 0.5; discrete=true)); feat(:identmin, F(1.0, 0.5; discrete=true))
    feat(:nsame, F(10.0, 0.5; discrete=true))
    feat(:collinear, F(1.0, 0.03)); feat(:tricol, F(1.0, 0.03)); feat(:gvert, F(1.0, 0.1)); feat(:gelong, F(1.0, 0.06))
    feat(:gcorners, F(10.0, 0.5; discrete=true)); feat(:bcorners, F(10.0, 0.5; discrete=true))
    feat(:cends, F(10.0, 0.5; discrete=true)); feat(:cjunct, F(10.0, 0.5; discrete=true))
    feat(:corder, F(5.0, 0.5; discrete=true)); feat(:neck, F(1.0, 0.1)); feat(:neckvert, F(1.0, 0.1))
    feat(:ccorners, F(10.0, 0.5; discrete=true))
    feat(:ssimmin, F(1.0, 0.5; discrete=true)); feat(:ssimmax, F(1.0, 0.5; discrete=true))
    # relations, quantifiers, and abstract notions
    for n in (:inside, :contains, :outside, :equality)
        add_concept!(m, n, :relation; depth=50, now=now, P=P)
    end
    add_concept!(m, :forall, :quantifier; depth=70, now=now, P=P)
    add_concept!(m, :sides, :abstract; depth=30, now=now, P=P)      # a string's count of its lines
    link2!(m, :convex_hull, :similar, :missing)
    for n in (:similar, :opposite, :small, :large, :many, :few)
        add_concept!(m, n, :abstract; depth=60, now=now, P=P)
    end
    # features each type gives rise to (urgency)
    link!(m, :line, :feature, :slope, 90); link!(m, :line, :feature, :length, 85)
    link!(m, :line, :feature, :numerosity, 50); link!(m, :line, :feature, :width, 10)
    link!(m, :point, :feature, :x, 85); link!(m, :point, :feature, :y, 85)
    link!(m, :intersection, :feature, :x, 8); link!(m, :intersection, :feature, :y, 8)
    link!(m, :intersection, :feature, :angle, 45); link!(m, :intersection, :feature, :numerosity, 35)
    link!(m, :dot, :feature, :size, 60); link!(m, :dot, :feature, :numerosity, 70)
    link!(m, :dot, :feature, :x, 30); link!(m, :dot, :feature, :y, 30)
    link!(m, :object, :feature, :texture, 80); link!(m, :object, :feature, :numerosity, 60)
    link!(m, :object, :feature, :area, 55); link!(m, :object, :feature, :barycenter, 35)
    link!(m, :object, :feature, :elongation, 25); link!(m, :object, :feature, :convex_hull, 10)
    add_concept!(m, :category, :abstract; depth=30, now=now, P=P)   # "this is a kind of …" (ch. 9)
    link!(m, :object, :feature, :category, 45)
    link!(m, :convex_hull, :feature, :missing, 70)
    link!(m, :curve, :feature, :numerosity, 50)
    link!(m, :line_string, :feature, :sides, 60)
    link!(m, :ellipse, :feature, :eccentricity, 30)
    link!(m, :interior, :feature, :openness, 45); link!(m, :interior, :feature, :numerosity, 45)
    # associations along which activation spreads
    link2!(m, :inside, :opposite, :outside); link2!(m, :inside, :similar, :contains)
    link2!(m, :small, :opposite, :large); link2!(m, :many, :opposite, :few)
    link2!(m, :line, :opposite, :curve)
    link2!(m, :similar, :opposite, :opposite)
    link2!(m, :area, :similar, :small); link2!(m, :area, :similar, :large)
    link2!(m, :numerosity, :similar, :many); link2!(m, :numerosity, :similar, :few)
    link2!(m, :equality, :similar, :similar); link2!(m, :equality, :similar, :forall)
    # built-in salience (§11.1.1 footnote 85): texture is noticed first,
    # coordinates of barycenters late
    for (n, s) in ((:texture, 120), (:numerosity, 80), (:area, 70), (:slope, 60), (:length, 50),
                   (:line, 50), (:curve, 50), (:object, 60), (:interior, 50), (:dot, 50),
                   (:circle, 40), (:missing, 35), (:x, 20), (:y, 20), (:elongation, 25),
                   (:forall, 40), (:equality, 30))
        m[n].w.sig.pos = s
    end
    for (n, s) in ((:shape, 30), (:mark, 40), (:pair, 40), (:contrast, 35), (:group, 35), (:vert, 35),
                   (:endgap, 30), (:endangle, 30), (:above, 40), (:larger, 35), (:inside, 45),
                   (:diff, 35), (:depth, 30), (:simmin, 35), (:simmax, 35), (:identmin, 35), (:nsame, 30),
                   (:collinear, 35), (:tricol, 30), (:gvert, 35), (:gelong, 25), (:gcorners, 35), (:bcorners, 35),
                   (:cends, 35), (:cjunct, 30), (:corder, 30), (:neck, 35), (:neckvert, 30),
                   (:cluster, 40), (:ccorners, 35), (:ssimmin, 35), (:ssimmax, 35))
        m[n].w.sig.pos = s
    end
    return m
end
