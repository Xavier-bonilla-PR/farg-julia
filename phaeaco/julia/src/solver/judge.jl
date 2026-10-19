# Was an answer right? For the synthetic BPs we know the rule each was drawn
# from. An answer is correct if its idea expresses that rule — or an
# equivalent description that holds by construction (BP #6: "three sides"
# for "triangle", as 13 of Foundalis's 26 subjects put it, footnote 19).

_feat(idea, path, what) = idea.kind == :feature && idea.path == path && idea.what == what
_count(idea, what; paths=nothing) = idea.kind == :count && idea.what == what &&
                                    (paths === nothing || idea.path in paths)
_exists(idea, what; tag=nothing) = idea.kind == :exists && idea.what == what && (tag === nothing || idea.tag == tag)

const SYNTH_RULES = Dict{Symbol,Function}(
    :existence => i -> (_exists(i, :object) && !i.leftlow) || (_count(i, :object) && i.leftlow),
    :size => i -> _feat(i, [:object], :area) && !i.leftlow,
    :texture => i -> _feat(i, [:object], :texture) && i.leftlow,
    :convexity => i -> (_feat(i, [:object], :missing) && i.leftlow) || _exists(i, :interior; tag=:concavity),
    :curves => i -> any(t -> _exists(i, t) && !i.leftlow, (:circle, :ellipse, :curve)) ||
                    ((_count(i, :line) || _exists(i, :line)) && !i.leftlow) ||
                    (_exists(i, :line) && i.leftlow),       # "some lines" vs "no lines": the same rule
    :tri_vs_quad => i -> (_count(i, :line) || _count(i, :vertex)) && i.leftlow,
    :position => i -> _feat(i, [:object, :barycenter], :x) && !i.leftlow,
    :elongation => i -> _feat(i, [:object], :elongation) && !i.leftlow,
    :interior => i -> (_exists(i, :interior; tag=:closed) && i.leftlow) || (_count(i, :interior) && !i.leftlow),
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
