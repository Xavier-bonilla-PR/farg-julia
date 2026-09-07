# Ported from Metacat's memory.ss.
#
# Metacat's EPISODIC MEMORY: what it has answered before, and what it got stuck
# on before. Each entry is a description — the three strings, the answer, both
# rules and the themes underlying them — not the workspace that produced it,
# which is gone by the time the entry is stored.
#
# Two things use it. `answer_present` stops the model reporting an answer it
# has already found, which is what makes it move on to a different one instead
# of circling. And `compare`, run whenever a new answer arrives, measures how
# far the new answer is from each stored one and activates the close ones —
# this is Metacat being REMINDED of an earlier answer, and it is where the
# comparison commentary comes from.
#
# The distance metric is the substance of this file. Two identical answers are
# 0 apart; anything else is at least 1, and grows with how differently the two
# answers see the problem: the themes they disagree about count double, a rule
# difference counts double, and being unable to justify a theme the other one
# justified counts too.
#
# `abstract-answer-description` and `abstract-snag-description` — which read an
# ANSWER or SNAG EVENT and the trace's recent events — are at the foot of this
# file; they waited on trace.ss and came with answers.ss step (C).
#
# Not ported: the memory window and every icon, highlight and bounding-box
# method, and the commentary `compare` writes, which is `*comment-window*`.

"""`%distance-threshold%` — how far apart two answers can be and still remind
Metacat of each other at all."""
const DISTANCE_THRESHOLD = 5

# `entries` and `theme_pattern_entries_equal` are trace.ss's, and live in
# trace.jl, which loads first — as trace.ss does before memory.ss.
#
# `compare_rule_clause_lists` and the rule-clause traversal underneath it are
# justify.ss's, and live in justify.jl, which loads first for the same reason.
# The memory's distance metric was their first caller; `unify_rules` and
# `get_unifying_slippages` are the rest of justify.ss's own use of them.

"""`(intersect-themes themes1 themes2)`. NB: built by `cross-product-filter-map`
keeping the element from the FIRST list, so an entry from `themes1` survives
even when the matching entry in `themes2` carries a different activation."""
function intersect_themes(themes1, themes2)
    result = Any[]
    for x in themes1, y in themes2
        theme_pattern_entries_equal(x, y) && push!(result, x)
    end
    return result
end

"""`(remove-elements elements l)` — everything in `l` not `equal?` to some
element. Value equality, not identity: these are theme entries and rule
clauses, which are compared by structure."""
remove_elements(elements, l) = [x for x in l if !any(y -> theme_entry_equal(y, x),
                                                     elements)]

"""Structural equality for the things `remove-elements` is used on here. Theme
entries are tuples of slipnodes, so `equal?` on them is elementwise identity."""
theme_entry_equal(a, b) =
    length(a) == length(b) && all(x === y for (x, y) in zip(a, b))

"""`(remq-elements elements l)` — the identity version."""
remq_elements(elements, l) = [x for x in l if !any(y -> y === x, elements)]

"""`(theme-abstractness theme)` — how abstract one theme is: the average of its
dimension's conceptual depth and its relation's. A `difference` relation (no
node at all) counts 50, and `identity` counts 0."""
function theme_abstractness(theme, net::Slipnet)
    dimension = theme[1]
    relation = theme[2]
    dimension_abstractness = dimension.conceptual_depth
    relation_abstractness = relation === net[:plato_identity] ? 0 :
                            relation === nothing ? 50 :
                            (relation::Node).conceptual_depth
    return sround(sdiv(dimension_abstractness + relation_abstractness, 2))
end

# --- answer and snag descriptions -------------------------------------------

"""`(make-answer-description ...)` — one entry in memory. Everything about an
answer that outlives the workspace that produced it."""
mutable struct AnswerDescription
    initial_letters::Vector{Node}
    modified_letters::Vector{Node}
    target_letters::Vector{Node}
    answer_letters::Vector{Node}
    top_rule_clauses::Vector{RuleClause}
    bottom_rule_clauses::Vector{RuleClause}
    top_rule_phrases::Vector{String}
    bottom_rule_phrases::Vector{String}
    top_rule_abstractness::Int
    bottom_rule_abstractness::Int
    temperature::Int
    """Relative quality, as the answer event judged it."""
    quality::Int
    vertical_theme_pattern::Any
    top_theme_pattern::Any
    bottom_theme_pattern::Any
    unjustified_theme_pattern::Any
    unjustified_slippages::Vector{ConceptMapping}
    activation::Int
end

function make_answer_description(initial_letters, modified_letters, target_letters,
                                 answer_letters, top_rule_clauses, bottom_rule_clauses,
                                 top_rule_phrases, bottom_rule_phrases,
                                 top_rule_abstractness, bottom_rule_abstractness,
                                 temperature, quality, vertical_theme_pattern,
                                 top_theme_pattern, bottom_theme_pattern,
                                 unjustified_theme_pattern, unjustified_slippages)
    return AnswerDescription(initial_letters, modified_letters, target_letters,
                             answer_letters, top_rule_clauses, bottom_rule_clauses,
                             top_rule_phrases, bottom_rule_phrases,
                             top_rule_abstractness, bottom_rule_abstractness,
                             temperature, quality, vertical_theme_pattern,
                             top_theme_pattern, bottom_theme_pattern,
                             unjustified_theme_pattern, unjustified_slippages, 0)
end

"""`(make-snag-description ...)` — the same for a snag: what Metacat was trying
when it got stuck, rather than what it concluded.

NB the argument list: the Scheme takes only the rules, phrases, explanation and
theme pattern, and reads the three strings out of the GLOBALS. The port takes
them explicitly, from the context."""
mutable struct SnagDescription
    initial_letters::Vector{Node}
    modified_letters::Vector{Node}
    target_letters::Vector{Node}
    rule_clauses::Vector{RuleClause}
    translated_rule_clauses::Vector{RuleClause}
    rule_phrases::Vector{String}
    translated_rule_phrases::Vector{String}
    snag_explanation::String
    theme_pattern::Any
    activation::Int
end

make_snag_description(ctx, rule_clauses, translated_rule_clauses, rule_phrases,
                      translated_rule_phrases, snag_explanation, theme_pattern) =
    SnagDescription(ctx.initial_string.letter_categories,
                    ctx.modified_string.letter_categories,
                    ctx.target_string.letter_categories,
                    rule_clauses, translated_rule_clauses, rule_phrases,
                    translated_rule_phrases, snag_explanation, theme_pattern, 0)

const MemoryDescription = Union{AnswerDescription,SnagDescription}

letters_print_name(letters) = join([n.lowercase_name for n in letters])

answer_print_name(a::AnswerDescription) =
    string(letters_print_name(a.initial_letters), " -> ",
           letters_print_name(a.modified_letters), ", ",
           letters_print_name(a.target_letters), " -> ",
           letters_print_name(a.answer_letters))

problem_print_name(a::MemoryDescription) =
    string(letters_print_name(a.initial_letters), " -> ",
           letters_print_name(a.modified_letters), ", ",
           letters_print_name(a.target_letters), " -> ?")

"""`(get-themes)` — the entries of the vertical theme pattern. NB: the top and
bottom patterns are stored but never compared."""
get_themes(a::AnswerDescription) = entries(a.vertical_theme_pattern)
get_unjustified_themes(a::AnswerDescription) = entries(a.unjustified_theme_pattern)
get_themes(s::SnagDescription) = entries(s.theme_pattern)

is_unjustified(a::AnswerDescription) = !isempty(a.unjustified_slippages)

get_activation(d::MemoryDescription) = d.activation
set_activation!(d::MemoryDescription, value::Integer) = (d.activation = value; d)
update_activation!(d::MemoryDescription, value::Integer) = (d.activation = value; d)

"""`(equal? ...)` on an answer description — the same problem, the same answer,
and the same two rules."""
answer_description_equal(a::AnswerDescription, i_letters, m_letters, t_letters,
                         a_letters, top_clauses, bot_clauses, net::Slipnet) =
    letters_equal(i_letters, a.initial_letters) &&
    letters_equal(m_letters, a.modified_letters) &&
    letters_equal(t_letters, a.target_letters) &&
    letters_equal(a_letters, a.answer_letters) &&
    rule_clause_lists_equal(top_clauses, a.top_rule_clauses, net) &&
    rule_clause_lists_equal(bot_clauses, a.bottom_rule_clauses, net)

"""`(equal? ...)` on a snag description — the same problem and the same rule."""
snag_description_equal(s::SnagDescription, i_letters, m_letters, t_letters,
                       rc_list, net::Slipnet) =
    letters_equal(i_letters, s.initial_letters) &&
    letters_equal(m_letters, s.modified_letters) &&
    letters_equal(t_letters, s.target_letters) &&
    rule_clause_lists_equal(rc_list, s.rule_clauses, net)

letters_equal(l1, l2) = length(l1) == length(l2) && all(a === b for (a, b) in zip(l1, l2))

"""`(answers-equal? other)`."""
answers_equal(a::AnswerDescription, other::AnswerDescription, net::Slipnet) =
    answer_description_equal(a, other.initial_letters, other.modified_letters,
                             other.target_letters, other.answer_letters,
                             other.top_rule_clauses, other.bottom_rule_clauses, net)

# --- how far apart two answers are ------------------------------------------

"""`(average-theme-abstractness answer)`."""
function average_theme_abstractness(a::AnswerDescription, net::Slipnet)
    themes = vcat(get_themes(a), get_unjustified_themes(a))
    isempty(themes) && return 0
    values = [theme_abstractness(t, net) for t in themes]
    return sround(sdiv(sum(values), length(values)))
end

"""`(answer-incoherent? answer)` — the answer rests on themes far more abstract
than the rule it used, so it is not really explained by that rule."""
function answer_incoherent(a::AnswerDescription, net::Slipnet)
    theme_abs = average_theme_abstractness(a, net)
    rule_abs = a.top_rule_abstractness
    return theme_abs > 50 && rule_abs < theme_abs && (theme_abs - rule_abs) > 25
end

"""`(get-snag-justified-themes answer)` — the unjustified themes of this answer
that a remembered SNAG on the same problem does explain."""
function get_snag_justified_themes(a::AnswerDescription, mem, net::Slipnet)
    unjustified = get_unjustified_themes(a)
    all_themes = vcat(get_themes(a), unjustified)
    snag = mem === nothing ? nothing : get_equivalent_snag(mem, a, net)
    snag_avoiding = snag === nothing ? Any[] :
                    remove_elements(get_themes(snag::SnagDescription), all_themes)
    return intersect_themes(snag_avoiding, unjustified)
end

"""`(calculate-answer-distance answer1 answer2)`.

Zero for two identical answers, and never less than one otherwise. It adds up
four things: the themes the two answers hold differently, how far apart their
rules are, which of them could justify what, and whether exactly one of them is
incoherent."""
function calculate_answer_distance(answer1::AnswerDescription,
                                   answer2::AnswerDescription, mem, net::Slipnet)
    answers_equal(answer1, answer2, net) && return 0

    all_themes1 = vcat(get_themes(answer1), get_unjustified_themes(answer1))
    all_themes2 = vcat(get_themes(answer2), get_unjustified_themes(answer2))
    unjustified_themes1 = remove_elements(get_snag_justified_themes(answer1, mem, net),
                                          get_unjustified_themes(answer1))
    unjustified_themes2 = remove_elements(get_snag_justified_themes(answer2, mem, net),
                                          get_unjustified_themes(answer2))

    common_themes = intersect_themes(all_themes1, all_themes2)
    common_dimensions = Any[t[1] for t in common_themes]
    shared_dimensions = Any[]
    for x in Any[t[1] for t in all_themes1], y in Any[t[1] for t in all_themes2]
        x === y && push!(shared_dimensions, x)
    end
    # Dimensions both answers have an opinion about, but DIFFERENT opinions.
    differing_dimensions = remq_elements(common_dimensions, shared_dimensions)

    answer1_only_themes = remove_elements(common_themes, all_themes1)
    answer2_only_themes = remove_elements(common_themes, all_themes2)
    differing_themes1 = [t for t in all_themes1
                         if any(d -> d === t[1], differing_dimensions)]
    differing_themes2 = [t for t in all_themes2
                         if any(d -> d === t[1], differing_dimensions)]
    # Themes only one answer has at all, as opposed to ones they disagree on.
    unique_themes1 = remove_elements(differing_themes1, answer1_only_themes)
    unique_themes2 = remove_elements(differing_themes2, answer2_only_themes)

    common_unjustified_themes = intersect_themes(unjustified_themes1,
                                                 unjustified_themes2)
    answer1_only_unjustified = remove_elements(common_unjustified_themes,
                                               unjustified_themes1)
    answer2_only_unjustified = remove_elements(common_unjustified_themes,
                                               unjustified_themes2)
    common_answer1_only_unjustified = remove_elements(differing_themes1,
                                                      answer1_only_unjustified)
    common_answer2_only_unjustified = remove_elements(differing_themes2,
                                                      answer2_only_unjustified)

    theme_distance = length(differing_dimensions) +
                     2 * length(unique_themes1) + 2 * length(unique_themes2)

    rule_differences = compare_rule_clause_lists(answer1.top_rule_clauses,
                                                 answer2.top_rule_clauses, net)
    # -1 means the two rules have no common shape at all, in which case the
    # distance falls back to how differently ABSTRACT they are.
    num_rule_differences = rule_differences === nothing ? -1 :
        count(nodes -> nodes[1].conceptual_depth != nodes[2].conceptual_depth,
              rule_differences)
    rule_distance = num_rule_differences == -1 ?
        sround(sdiv(abs(answer1.top_rule_abstractness -
                        answer2.top_rule_abstractness), 10)) :
        2 * num_rule_differences

    justification_distance = length(common_answer1_only_unjustified) +
                             length(common_answer2_only_unjustified)
    incoherence_distance = answer_incoherent(answer1, net) ==
                           answer_incoherent(answer2, net) ? 0 : 1

    return 1 + theme_distance + rule_distance + justification_distance +
           incoherence_distance
end

# --- the memory itself ------------------------------------------------------

"""`(make-memory)` — the store. Answers and snags are kept apart as well as
together, because `answer-present?` and `snag-present?` ask different
questions."""
mutable struct Memory
    answer_descriptions::Vector{AnswerDescription}
    snag_descriptions::Vector{SnagDescription}
    all_descriptions::Vector{MemoryDescription}
end

make_memory() = Memory(AnswerDescription[], SnagDescription[], MemoryDescription[])

get_answers(m::Memory) = m.answer_descriptions
get_snags(m::Memory) = m.snag_descriptions
get_all_descriptions(m::Memory) = m.all_descriptions

function clear_memory!(m::Memory)
    m.answer_descriptions = AnswerDescription[]
    m.snag_descriptions = SnagDescription[]
    m.all_descriptions = MemoryDescription[]
    return m
end

"""`(clear-activations)` — NB: only ANSWER descriptions, not snags."""
clear_activations!(m::Memory) =
    (foreach(a -> update_activation!(a, 0), m.answer_descriptions); m)

"""`(delete answer)` — `remq` from whichever list it belongs to, and from the
combined one."""
function delete_description!(m::Memory, d::MemoryDescription)
    drop!(v) = (i = findfirst(x -> x === d, v); i === nothing || deleteat!(v, i))
    drop!(d isa AnswerDescription ? m.answer_descriptions : m.snag_descriptions)
    drop!(m.all_descriptions)
    return m
end

"""`(answer-present? answer-letters top-rule bottom-rule)` — has this exact
answer, by this exact pair of rules, been found before? This is what stops the
model reporting the same answer twice."""
answer_present(m::Memory, answer_letters, top_rule::Rule, bottom_rule::Rule,
               ctx, net::Slipnet) =
    any(a -> answer_description_equal(a, ctx.initial_string.letter_categories,
                                      ctx.modified_string.letter_categories,
                                      ctx.target_string.letter_categories,
                                      answer_letters, top_rule.rule_clauses,
                                      bottom_rule.rule_clauses, net),
        m.answer_descriptions)

"""`(snag-present? snag-rule)`."""
snag_present(m::Memory, snag_rule::Rule, ctx, net::Slipnet) =
    any(s -> snag_description_equal(s, ctx.initial_string.letter_categories,
                                    ctx.modified_string.letter_categories,
                                    ctx.target_string.letter_categories,
                                    snag_rule.rule_clauses, net),
        m.snag_descriptions)

"""`(get-equivalent-snag answer)` — the remembered snag, if any, from the same
problem and the same top rule as this answer."""
function get_equivalent_snag(m::Memory, a::AnswerDescription, net::Slipnet)
    i = findfirst(s -> snag_description_equal(s, a.initial_letters,
                                              a.modified_letters, a.target_letters,
                                              a.top_rule_clauses, net),
                  m.snag_descriptions)
    return i === nothing ? nothing : m.snag_descriptions[i]
end

"""`(compare new-answer)` — how strongly this remembered answer is reminded of
a new one. Identical answers activate it fully; anything at or beyond the
distance threshold leaves it at 0.

The commentary the Scheme writes here is `*comment-window*` and is not ported."""
function compare_answer!(a::AnswerDescription, new_answer::AnswerDescription,
                         mem, net::Slipnet)
    distance = calculate_answer_distance(a, new_answer, mem, net)
    # `(100- (100* ...))`: `(100* x)` is `(round (* 100 x))`.
    # `smin`, not `min`: `sdiv` yields a rational for a distance under the
    # threshold, and Julia's `min` would promote a winning integer 1 to `1//1`.
    new_activation = sub_from_100(sround(100 * smin(1, sdiv(distance,
                                                            DISTANCE_THRESHOLD))))
    update_activation!(a, new_activation)
    return new_activation
end

"""`(add-answer-description new-answer)`. NB: every stored answer is compared
against the new one BEFORE it joins them, and the lists are CONSed, so they are
in reverse order of storage."""
function add_answer_description!(m::Memory, new_answer::AnswerDescription,
                                 net::Slipnet)
    set_activation!(new_answer, 100)
    for answer in m.answer_descriptions
        compare_answer!(answer, new_answer, m, net)
    end
    pushfirst!(m.answer_descriptions, new_answer)
    pushfirst!(m.all_descriptions, new_answer)
    return m
end

function add_snag_description!(m::Memory, new_snag::SnagDescription)
    pushfirst!(m.snag_descriptions, new_snag)
    pushfirst!(m.all_descriptions, new_snag)
    return m
end

# --- abstracting an event into something the memory can compare -------------
#
# These are what turn a moment into a memory. An answer or snag EVENT records
# what happened in terms of the workspace that produced it — particular groups,
# particular bridges. A DESCRIPTION records it in terms that outlive that
# workspace, so a later run on a different problem can be reminded of it.

"""`(abstract-answer-description answer-event)` — build the abstract
characterization of an answer from the workspace and the trace, hang it on the
event, and store it in memory."""
function abstract_answer_description!(answer_event::AnswerEvent, mem::Memory, ctx)
    net = ctx.net
    vertical_theme_pattern = abstract_answer_description_theme_pattern(
        most_recent_group_and_concept_mapping_events(ctx), ctx)
    unjustified_theme_pattern = get_unjustified_theme_pattern(
        get_unjustified_slippages(answer_event), net)
    top_rule = get_event_rule(answer_event, :top)
    bottom_rule = get_event_rule(answer_event, :bottom)
    new_answer = make_answer_description(
        get_initial_letters(answer_event), get_modified_letters(answer_event),
        get_target_letters(answer_event), get_answer_letters(answer_event),
        top_rule.rule_clauses, bottom_rule.rule_clauses,
        top_rule.english_transcription, bottom_rule.english_transcription,
        top_rule.abstractness, bottom_rule.abstractness,
        get_temperature(answer_event),
        # NB the Scheme comment: "This is relative quality" — but it sends
        # `get-quality`, which is ABSOLUTE quality. The comment is wrong, not
        # the code, and the port follows the code.
        get_event_quality(answer_event),
        vertical_theme_pattern, top_rule.theme_pattern, bottom_rule.theme_pattern,
        unjustified_theme_pattern, get_unjustified_slippages(answer_event))
    set_answer_description!(answer_event, new_answer)
    add_answer_description!(mem, new_answer, net)
    return new_answer
end

"""`(abstract-snag-description snag-event)`.

The snag's theme pattern is thinned to the DOMINANT themes only: any dimension
the snag implicates more than once is dropped entirely, because a dimension
pulling in two directions says nothing about what went wrong."""
function abstract_snag_description!(snag_event::SnagEvent, mem::Memory, ctx)
    net = ctx.net
    clusters = partition_pred((e1, e2) -> e1[1] === e2[1],
                              get_snag_theme_pattern(snag_event)[2:end])
    snag_theme_pattern = Any[:vertical_bridge,
                             Any[c[1] for c in clusters if length(c) == 1]...]
    rule = get_event_rule(snag_event, :top)
    translated_rule = get_event_rule(snag_event, :bottom)
    # The bridges the snag itself implicated, when there are any; otherwise
    # whichever vertical bridges happen to hold the thinned pattern up.
    snag_bridges = get_snag_bridges(snag_event)
    theme_supporting_bridges = isempty(snag_bridges) ?
        Bridge[b for b in get_bridges(ctx, :vertical)
               if supports_theme_pattern(b, snag_theme_pattern, net)] :
        snag_bridges
    new_snag = make_snag_description(
        ctx, rule.rule_clauses, translated_rule.rule_clauses,
        rule.english_transcription, translated_rule.english_transcription,
        snag_explanation(snag_event, net), snag_theme_pattern)
    add_snag_description!(mem, new_snag)
    return new_snag
end
