# Was an answer right? For the synthetic BPs we know the rule each was drawn
# from. An answer is correct if its idea expresses that rule — or an
# equivalent description that holds by construction (BP #6: "three sides"
# for "triangle", as 13 of Foundalis's 26 subjects put it, footnote 19).

_feat(idea, path, what) = idea.kind == :feature && idea.path == path && idea.what == what
_count(idea, what; paths=nothing) = idea.kind == :count && idea.what == what &&
                                    (paths === nothing || idea.path in paths)
_exists(idea, what; tag=nothing) = idea.kind == :exists && idea.what == what && (tag === nothing || idea.tag == tag)

const SYNTH_RULES = Dict{Symbol,Function}(
    :existence => i -> ((_exists(i, :object) || _exists(i, :thing)) && !i.leftlow) || (_count(i, :object) && i.leftlow),
    :size => i -> _feat(i, [:object], :area) && !i.leftlow,
    :texture => i -> (_feat(i, [:object], :texture) && i.leftlow) || (_count(i, :interior) && !i.leftlow),   # outlined = encloses white (D37)
    :convexity => i -> (_feat(i, [:object], :missing) && i.leftlow) || _exists(i, :interior; tag=:concavity),
    :curves => i -> any(t -> _exists(i, t) && !i.leftlow, (:circle, :ellipse, :curve)) ||
                    any(t -> _count(i, t) && i.leftlow, (:circle, :ellipse, :curve)) ||   # "≤ 0 curves" is "no curve"
                    ((_count(i, :line) || _exists(i, :line)) && !i.leftlow) ||
                    (_exists(i, :line) && i.leftlow),       # "some lines" vs "no lines": the same rule
    :tri_vs_quad => i -> ((_count(i, :line) || _count(i, :vertex)) && i.leftlow) ||
                         (_exists(i, :category; tag=:triangle) && i.leftlow) ||
                         (_exists(i, :category; tag=:quadrilateral) && !i.leftlow),
    :position => i -> _feat(i, [:object, :barycenter], :x) && !i.leftlow,
    :elongation => i -> _feat(i, [:object], :elongation) && !i.leftlow,
    :interior => i -> (_exists(i, :interior; tag=:closed) && i.leftlow) || (_count(i, :interior) && !i.leftlow) ||
                     (_exists(i, :interior; tag=:concavity) && !i.leftlow),    # an open figure's interior is open (Fig. 7.38)
    :small_present => i -> _feat(i, [:object], :area) && i.quant == :some && i.tag == :left && i.leftlow,
    :same_size => i -> _exists(i, :forall; tag=:object_area) && i.leftlow,
    :count_objects => i -> _count(i, :object) && i.leftlow,
    :parallel_lines => i -> _exists(i, :forall; tag=:line_slope) && i.leftlow,
    :same_texture => i -> _exists(i, :forall; tag=:object_texture) && i.leftlow,
    :line_count => i -> _count(i, :line; paths=([:deep],)) && i.leftlow,
)

"""`:correct`, `:incorrect` or `:none` for a result on a synthetic BP."""
function judge(name::Symbol, r::SolveResult)
    r.answer === nothing && return :none
    return SYNTH_RULES[name](r.answer) ? :correct : :incorrect
end

# --- the real BPs of the target set ------------------------------------------------------

"""
Rules for the fifteen BPs Phaeaco solved (Appendix A), with the
descriptions that express them. BP #6 accepts "three sides vs four" (13 of
26 subjects; footnote 19); BP #1 accepts any "nothing vs something".
"""
const REAL_RULES = Dict{Int,Function}(
    1 => i -> (_exists(i, :thing) || _exists(i, :object)) && !i.leftlow || (_count(i, :object) && i.leftlow),
    2 => i -> _feat(i, [:object], :area) && !i.leftlow,
    3 => i -> (_feat(i, [:object], :texture) && i.leftlow) || (_count(i, :interior) && !i.leftlow),
    4 => i -> (_feat(i, [:object], :missing) && i.leftlow) || (_exists(i, :interior; tag=:concavity) && !i.leftlow),
    5 => i -> any(t -> _exists(i, t) && !i.leftlow, (:circle, :ellipse, :curve)) ||
              any(t -> _count(i, t) && i.leftlow, (:circle, :ellipse, :curve)) ||
              ((_count(i, :line) || _exists(i, :line)) && !i.leftlow) || (_exists(i, :line) && i.leftlow),
    6 => i -> ((_count(i, :line) || _count(i, :vertex)) && i.leftlow) ||
              (_exists(i, :category; tag=:triangle) && i.leftlow) || (_exists(i, :category; tag=:quadrilateral) && !i.leftlow),
    8 => i -> _feat(i, [:object, :barycenter], :x) && !i.leftlow,
    11 => i -> _feat(i, [:object], :elongation) && !i.leftlow,
    15 => i -> (_exists(i, :interior; tag=:closed) && i.leftlow) || (_count(i, :interior) && !i.leftlow) ||
               (_exists(i, :interior; tag=:concavity) && !i.leftlow),
    21 => i -> _feat(i, [:object], :area) && i.quant == :some && i.tag == :left && i.leftlow,
    22 => i -> _exists(i, :forall; tag=:object_area) && i.leftlow,
    23 => i -> _count(i, :object) && i.leftlow,
    39 => i -> _exists(i, :forall; tag=:line_slope) && i.leftlow,
    56 => i -> _exists(i, :forall; tag=:object_texture) && i.leftlow,
    85 => i -> _count(i, :line) && i.leftlow,
)

judge_real(n::Int, r::SolveResult) = r.answer === nothing ? :none : (REAL_RULES[n](r.answer) ? :correct : :incorrect)

"""Appendix A (100 runs): Phaeaco's correct / wrong / none, and its relative time (BP #3 = 1, 2006 table)."""
const APPENDIX_A = Dict{Int,Tuple{Int,Int,Int,Float64}}(
    1 => (100, 0, 0, 2.18), 2 => (82, 18, 0, 3.0), 3 => (99, 1, 0, 1.0), 4 => (20, 3, 77, 2.27),
    5 => (60, 18, 22, 3.07), 6 => (70, 11, 19, 1.47), 8 => (23, 4, 73, 2.63), 11 => (83, 4, 13, 5.40),
    15 => (99, 0, 1, 2.17), 21 => (34, 20, 46, 5.30), 22 => (13, 6, 81, 10.07), 23 => (83, 4, 13, 2.57),
    39 => (65, 29, 6, 1.23), 56 => (19, 17, 64, 11.20), 85 => (94, 0, 6, 3.53),
)

# --- Bongard's other problems (PhaeacoX) -------------------------------------------------
#
# Rules for the problems whose solution one of PhaeacoX's percepts can state,
# from Foundalis's solutions page. Problems without an entry are not scored.
# A pair's features name its kinds in alphabetical order: in
# `pair@circle_triangle`, above > 0 means the circle is higher.

_xfeat(i, node, f) = i.kind == :feature && !isempty(i.path) && i.path[end] == node && i.what == f
_xexists(i, t) = i.kind == :exists && (i.what == t || i.what == Symbol("shape@", t))
_tri_quad(i) = ((_count(i, :line) || _count(i, :vertex)) && i.leftlow) ||
               (_xexists(i, :triangle) && i.leftlow) || (_xexists(i, :quadrangle) && !i.leftlow) ||
               (i.kind == :feature && i.what in (:gcorners, :bcorners) && i.leftlow)
_parts(i) = (_count(i, :object) || _count(i, :line) || _count(i, :curve)) && i.leftlow

const SURVEY_RULES = Dict{Int,Function}(
    7 => i -> _xfeat(i, :object, :vert) && !i.leftlow,
    10 => _tri_quad,
    12 => i -> _feat(i, [:object], :elongation) && !i.leftlow,
    24 => i -> ((_xexists(i, :circle) || _xexists(i, :curve)) && i.leftlow) || (_count(i, :circle) && !i.leftlow),
    27 => i -> _xfeat(i, Symbol("contrast@filled_outlined"), :diff) && !i.leftlow,
    28 => i -> _xfeat(i, Symbol("contrast@filledcircle_outlinedcircle"), :diff) && !i.leftlow,
    29 => i -> _xfeat(i, Symbol("contrast@inside_outside"), :diff) && !i.leftlow,
    30 => i -> i.kind == :exists && i.what == Symbol("mark@selfcrossing") && i.leftlow,
    33 => i -> _feat(i, [:object, :vertex], :angle) && i.quant == :some && i.tag == :left && i.leftlow,
    34 => i -> _feat(i, [:object], :texture) && i.leftlow,
    36 => i -> _xfeat(i, Symbol("pair@circle_triangle"), :above) && i.leftlow,
    37 => i -> _xfeat(i, Symbol("pair@circle_triangle"), :above) && i.leftlow,
    38 => i -> _xfeat(i, Symbol("pair@circle_triangle"), :larger) && i.leftlow,
    40 => i -> i.kind == :feature && !isempty(i.path) && basetype(i.path[end]) == :group && i.what == :tricol && i.leftlow,
    41 => i -> (_xfeat(i, Symbol("group@outlinedcircle"), :collinear) || _xfeat(i, Symbol("group@circle"), :collinear)) && i.leftlow,
    47 => i -> _xfeat(i, Symbol("pair@circle_triangle"), :inside) && i.leftlow,
    48 => i -> _xfeat(i, Symbol("pair@filled_outlined"), :above) && !i.leftlow,
    57 => i -> i.kind == :feature && isempty(i.path) && i.what == :identmin && !i.leftlow,
    59 => i -> i.kind == :feature && isempty(i.path) && i.what == :simmin && !i.leftlow,
    60 => i -> i.kind == :feature && isempty(i.path) && i.what == :simmax && !i.leftlow,
    62 => i -> _xfeat(i, :object, :endgap) && !i.leftlow,
    65 => i -> _xfeat(i, Symbol("group@triangle"), :gvert) && i.leftlow,
    66 => i -> _xfeat(i, Symbol("group@circle"), :gvert) && i.leftlow,
    71 => i -> i.kind == :feature && isempty(i.path) && i.what == :depth && !i.leftlow,
    72 => i -> _xfeat(i, :object, :endangle) && i.leftlow,
    86 => _parts, 87 => _parts, 88 => _parts, 89 => _parts, 90 => _parts,
    91 => i -> i.kind == :feature && isempty(i.path) && i.what == :nsame && i.leftlow,
    96 => _tri_quad,
    97 => i -> (_xexists(i, :triangle) && i.leftlow) || (_xexists(i, :circle) && !i.leftlow) ||
               (_count(i, :circle) && i.leftlow),
    98 => _tri_quad,
)

"""`:correct`, `:incorrect`, `:none`, or `:unscored` for a run on one of Bongard's other problems."""
judge_survey(n::Int, r::SolveResult) =
    r.answer === nothing ? :none : !haskey(SURVEY_RULES, n) ? :unscored :
    SURVEY_RULES[n](r.answer) ? :correct : :incorrect
