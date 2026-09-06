# Ported from Metacat's trace.ss — the PATTERN half (trace.ss 1412-1672).
#
# A PATTERN is how the trace says what a moment of processing was about, in a
# form that outlives the workspace it came from. There are three kinds, told
# apart by their first element:
#
#   (<theme-type> (<dimension> <relation> [<activation>]) ...)
#   (concepts     (<slipnode> <activation>) ...)
#   (codelets     (<codelet-type> <urgency>) ...)
#
# Patterns are compared IGNORING the activations and urgencies — two moments
# are "the same idea" when they name the same dimensions and relations, however
# strongly. That is what lets the trace notice it has been here before.
#
# CLAMPING is the other half: given a pattern, force the model into it. Clamp a
# theme pattern and the themespace is emptied of that theme type, refilled from
# the pattern, frozen and switched on; clamp a concept pattern and those
# slipnodes are pinned at those activations; clamp a codelet pattern and those
# codelet types run at those urgencies. This is how Metacat acts on what it has
# noticed about itself — it is the whole mechanism behind jootsing and
# justification.
#
# The TEMPORAL TRACE and `make-generic-event` (trace.ss 23-333) are ported at
# the foot of this file. Still to come: the seven concrete event types
# (333-1310) and the monitors that raise them (1310-1412). `print-pattern` is
# skipped for good — it needs `relation-name` from theme-graphics.ss, a file
# the headless harness never loads, so the Scheme cannot run it either.

# --- what kind of pattern is this -------------------------------------------

"""`(entries pattern)` is `rest` — a pattern is its type followed by its
entries, and the entries are what gets compared."""
entries(pattern) = pattern[2:end]

is_theme_pattern(pattern) =
    pattern[1] === :top_bridge || pattern[1] === :vertical_bridge ||
    pattern[1] === :bottom_bridge
is_concept_pattern(pattern) = pattern[1] === :concepts
is_codelet_pattern(pattern) = pattern[1] === :codelets

same_pattern_type(pattern1, pattern2) = pattern1[1] === pattern2[1]

"""`(pattern-type-present? pattern patterns)` — `assq` on the type."""
pattern_type_present(pattern, patterns) =
    any(p -> p[1] === pattern[1], patterns)

"""`(negate-theme-pattern-entry entry)` — the same theme, wanted as strongly
NOT to hold. An entry with no activation of its own negates to the full
negative activation."""
negate_theme_pattern_entry(entry) =
    Any[entry[1], entry[2],
        length(entry) == 3 ? -entry[3] : -MAX_THEME_ACTIVATION]

# --- are two patterns the same idea -----------------------------------------
#
# These ignore positive/negative theme activations, slipnode activations and
# codelet urgencies.

"""`(theme-pattern-entries-equal? e1 e2)` — dimension and relation only."""
theme_pattern_entries_equal(e1, e2) = e1[1] === e2[1] && e1[2] === e2[2]

theme_patterns_equal(p1, p2) =
    p1[1] === p2[1] &&
    sets_equal_pred(theme_pattern_entries_equal, entries(p1), entries(p2))

"""`(concept-patterns-equal? ...)` / `(codelet-patterns-equal? ...)` — the same
things named, whatever their activations or urgencies."""
concept_patterns_equal(p1, p2) =
    sets_equal(Any[e[1] for e in entries(p1)], Any[e[1] for e in entries(p2)])
codelet_patterns_equal(p1, p2) =
    sets_equal(Any[e[1] for e in entries(p1)], Any[e[1] for e in entries(p2)])

"""`(patterns-equal? pattern1 pattern2)`. NB: the Scheme's `cond` has no `else`,
so two patterns of the same but UNRECOGNISED type return void — unreachable,
since the three predicates cover every type that exists."""
function patterns_equal(pattern1, pattern2)
    same_pattern_type(pattern1, pattern2) || return false
    is_concept_pattern(pattern1) && return concept_patterns_equal(pattern1, pattern2)
    is_codelet_pattern(pattern1) && return codelet_patterns_equal(pattern1, pattern2)
    is_theme_pattern(pattern1) && return theme_patterns_equal(pattern1, pattern2)
    return false
end

# --- theme patterns ---------------------------------------------------------

"""`(get-associated-concept-pattern theme-pattern)` — the slipnodes a theme
pattern implies: every dimension it names, fully active, plus `opposite`
itself when a theme wants an opposite relation. A NEGATIVE opposite theme
brings `opposite` in at 0 rather than fully active, since the pattern is about
that relation not holding.

NB: `remove-duplicates` (value equality) keeps the LAST of each group, so a
node named twice at different activations takes the later one."""
function get_associated_concept_pattern(theme_pattern, net::Slipnet)
    result = Any[]
    for entry in entries(theme_pattern)
        dim = entry[1]
        rel = entry[2]
        act = length(entry) == 3 ? entry[3] : MAX_THEME_ACTIVATION
        push!(result, Any[dim, MAX_ACTIVATION])
        if rel === net[:plato_opposite]
            push!(result, Any[rel, act > 0 ? MAX_ACTIVATION : 0])
        end
    end
    deduped = [x for (i, x) in enumerate(result)
               if !any(y -> length(y) == length(x) && all(a === b || a == b
                                                          for (a, b) in zip(y, x)),
                       result[(i + 1):end])]
    return Any[:concepts, deduped...]
end

"""`(impose-theme-pattern theme-pattern)` — set every theme the pattern names.
NB: this does NOT touch the frozen status of clusters or the themespace's
thematic pressure; `clamp_theme_pattern!` is what does that."""
function impose_theme_pattern!(ts::Themespace, theme_pattern)
    theme_type = theme_pattern[1]
    for entry in entries(theme_pattern)
        act = length(entry) == 3 ? entry[3] : MAX_THEME_ACTIVATION
        set_theme_activation!(ts, theme_type, entry[1], entry[2], act)
    end
    return ts
end

"""`(clamp-theme-pattern theme-pattern)` — wipe that theme type, impose the
pattern, freeze it so nothing can drift, and switch its pressure on."""
function clamp_theme_pattern!(ts::Themespace, theme_pattern)
    theme_type = theme_pattern[1]
    delete_theme_type!(ts, theme_type)
    impose_theme_pattern!(ts, theme_pattern)
    freeze_theme_type!(ts, theme_type)
    thematic_pressure_on!(ts, theme_type)
    return ts
end

"""`(unclamp-theme-pattern theme-pattern)`. NB: this unfreezes and switches the
pressure off but LEAVES the themes in place — undoing a clamp does not undo
what it imposed."""
function unclamp_theme_pattern!(ts::Themespace, theme_pattern)
    theme_type = theme_pattern[1]
    unfreeze_theme_type!(ts, theme_type)
    thematic_pressure_off!(ts, theme_type)
    return ts
end

# --- concept patterns -------------------------------------------------------

"""`(clamp-concept-pattern concept-pattern)` — pin each node at its activation."""
function clamp_concept_pattern!(concept_pattern)
    for entry in entries(concept_pattern)
        clamp_activation!(entry[1], entry[2])
    end
    return concept_pattern
end

"""`(unclamp-concept-pattern concept-pattern)`."""
function unclamp_concept_pattern!(concept_pattern)
    for entry in entries(concept_pattern)
        unfreeze!(entry[1])
    end
    return concept_pattern
end

# --- codelet patterns -------------------------------------------------------

"""`(get-complement-codelet-pattern urgency codelet-patterns)` — every codelet
type the given patterns do NOT name, at one urgency. This is what lets a clamp
say "these types loudly, everything else at this background level"."""
function get_complement_codelet_pattern(urgency, codelet_patterns)
    specified = Any[]
    for p in codelet_patterns
        append!(specified, entries(p))
    end
    specified_types = remq_duplicates(Any[e[1] for e in specified])
    unspecified = [t for t in all_codelet_types()
                   if !any(x -> x === t, specified_types)]
    return Any[:codelets, [Any[t, urgency] for t in unspecified]...]
end

"""`(against-background urgency . codelet-patterns)` — the named types at their
own urgencies, and every other type at the background one."""
function against_background(urgency, codelet_patterns...)
    specified = Any[]
    for p in codelet_patterns
        append!(specified, entries(p))
    end
    complement = entries(get_complement_codelet_pattern(urgency, codelet_patterns))
    return Any[:codelets, specified..., complement...]
end

"""`(clamp-codelet-pattern codelet-pattern)`."""
function clamp_codelet_pattern!(codelet_pattern, cr::Coderack)
    for entry in entries(codelet_pattern)
        clamp_codelet_type!(entry[1], entry[2], cr)
    end
    return codelet_pattern
end

"""`(unclamp-codelet-pattern codelet-pattern)`."""
function unclamp_codelet_pattern!(codelet_pattern, cr::Coderack)
    for entry in entries(codelet_pattern)
        unclamp_codelet_type!(entry[1], cr)
    end
    return codelet_pattern
end

# --- the standard codelet patterns ------------------------------------------
#
# "not all of these codelet-patterns are used", as the Scheme says. They are
# built as functions rather than constants because a `CodeletType` is created
# lazily on first mention, and the pattern has to hold the same object the
# coderack does.

ct(name::Symbol) = get!(CODELET_TYPES, name, CodeletType(name))

top_down_codelet_pattern() = Any[:codelets,
    Any[ct(:top_down_bond_scout_direction), VERY_HIGH_URGENCY],
    Any[ct(:top_down_group_scout_direction), VERY_HIGH_URGENCY],
    Any[ct(:top_down_bond_scout_category), VERY_HIGH_URGENCY],
    Any[ct(:top_down_group_scout_category), VERY_HIGH_URGENCY],
    Any[ct(:top_down_description_scout), VERY_HIGH_URGENCY],
    Any[ct(:bond_evaluator), EXTREMELY_HIGH_URGENCY],
    Any[ct(:bond_builder), EXTREMELY_HIGH_URGENCY],
    Any[ct(:group_evaluator), EXTREMELY_HIGH_URGENCY],
    Any[ct(:group_builder), EXTREMELY_HIGH_URGENCY],
    Any[ct(:description_evaluator), EXTREMELY_HIGH_URGENCY],
    Any[ct(:description_builder), EXTREMELY_HIGH_URGENCY]]

bottom_up_codelet_pattern() = Any[:codelets,
    Any[ct(:bottom_up_bond_scout), VERY_HIGH_URGENCY],
    Any[ct(:bond_evaluator), EXTREMELY_HIGH_URGENCY],
    Any[ct(:bond_builder), EXTREMELY_HIGH_URGENCY],
    Any[ct(:group_scout_whole_string), VERY_HIGH_URGENCY],
    Any[ct(:group_evaluator), EXTREMELY_HIGH_URGENCY],
    Any[ct(:group_builder), EXTREMELY_HIGH_URGENCY],
    Any[ct(:bottom_up_bridge_scout), VERY_HIGH_URGENCY],
    Any[ct(:important_object_bridge_scout), VERY_HIGH_URGENCY],
    Any[ct(:bridge_evaluator), EXTREMELY_HIGH_URGENCY],
    Any[ct(:bridge_builder), EXTREMELY_HIGH_URGENCY],
    Any[ct(:bottom_up_description_scout), VERY_HIGH_URGENCY],
    Any[ct(:description_evaluator), EXTREMELY_HIGH_URGENCY],
    Any[ct(:description_builder), EXTREMELY_HIGH_URGENCY],
    Any[ct(:rule_scout), VERY_HIGH_URGENCY],
    Any[ct(:rule_evaluator), EXTREMELY_HIGH_URGENCY],
    Any[ct(:rule_builder), EXTREMELY_HIGH_URGENCY]]

thematic_codelet_pattern() = Any[:codelets,
    Any[ct(:thematic_bridge_scout), EXTREMELY_HIGH_URGENCY]]

rule_codelet_pattern() = Any[:codelets,
    Any[ct(:rule_scout), VERY_HIGH_URGENCY],
    Any[ct(:rule_evaluator), EXTREMELY_HIGH_URGENCY],
    Any[ct(:rule_builder), EXTREMELY_HIGH_URGENCY]]

bond_codelet_pattern() = Any[:codelets,
    Any[ct(:bottom_up_bond_scout), VERY_HIGH_URGENCY],
    Any[ct(:bond_evaluator), EXTREMELY_HIGH_URGENCY],
    Any[ct(:bond_builder), EXTREMELY_HIGH_URGENCY]]

group_codelet_pattern() = Any[:codelets,
    Any[ct(:group_scout_whole_string), VERY_HIGH_URGENCY],
    Any[ct(:group_evaluator), EXTREMELY_HIGH_URGENCY],
    Any[ct(:group_builder), EXTREMELY_HIGH_URGENCY]]

bridge_codelet_pattern() = Any[:codelets,
    Any[ct(:bottom_up_bridge_scout), VERY_HIGH_URGENCY],
    Any[ct(:important_object_bridge_scout), VERY_HIGH_URGENCY],
    Any[ct(:bridge_evaluator), EXTREMELY_HIGH_URGENCY],
    Any[ct(:bridge_builder), EXTREMELY_HIGH_URGENCY]]

description_codelet_pattern() = Any[:codelets,
    Any[ct(:bottom_up_description_scout), VERY_HIGH_URGENCY],
    Any[ct(:description_evaluator), EXTREMELY_HIGH_URGENCY],
    Any[ct(:description_builder), EXTREMELY_HIGH_URGENCY]]

answer_codelet_pattern() = Any[:codelets,
    Any[ct(:answer_finder), EXTREMELY_HIGH_URGENCY],
    Any[ct(:answer_justifier), EXTREMELY_HIGH_URGENCY]]

# --- the temporal trace (trace.ss 23-333) -----------------------------------
#
# The TEMPORAL TRACE is Metacat's record of its own processing: a list of
# EVENTS, newest first, each a snapshot of the moment it happened. This is what
# separates Metacat from Copycat — Copycat has a workspace and no memory of how
# it got there, and cannot notice that it has been going round in circles.
#
# An event carries the time, the temperature, every structure the workspace had
# built by then, which rules were clamped, and the themespace's complete and
# dominant patterns. Those snapshots are what the later questions are asked of:
# how long since the last snag, what has been built since the last clamp, is
# there a current answer.
#
# The trace also tracks two PERIODS. A clamp period runs from a clamp event
# until the clamp is undone, and a grace period follows it, during which no new
# clamp is allowed — together they stop Metacat clamping constantly. A snag
# period runs from a snag until the snag condition is undone.
#
# The seven concrete event types (answer, clamp, concept-activation,
# concept-mapping, group, rule, snag) and the monitors that raise them are not
# ported yet, so the four trace methods that reach into a clamp or snag event —
# `progress-since-last-clamp`, `undo-last-clamp`, `progress-since-last-snag`
# and `undo-snag-condition` — come with them.

"""`%max-clamp-period%` and `%grace-period%` (jootsing.ss) — how long a clamp
may last, and how long after one before another is allowed."""
const MAX_CLAMP_PERIOD = 750
const GRACE_PERIOD = 100

"""`(make-generic-event event-type)` — a snapshot of the model at the moment
the event happened. Every concrete event type is built on one of these.

NB: the snapshot is taken at CONSTRUCTION, not when the event is added to the
trace, so it records the state that gave rise to the event."""
mutable struct GenericEvent
    event_type::Symbol
    event_number::Union{Nothing,Int}
    time_of_occurrence::Int
    temperature::Int
    workspace_structures::Vector{Any}
    clamped_rules::Vector{Any}
    active_theme_types::Vector{Symbol}
    complete_themespace_patterns::Vector{Any}
    dominant_themespace_patterns::Vector{Any}
end

function make_generic_event(event_type::Symbol, ctx)
    return GenericEvent(event_type, nothing, ctx.codelet_count, ctx.temperature,
                        get_structures(ctx), copy(get_clamped_rules(ctx)),
                        copy(ctx.themespace.active_theme_types),
                        get_all_complete_theme_patterns(ctx.themespace),
                        get_all_dominant_theme_patterns(ctx.themespace))
end

event_print_name(e::GenericEvent) =
    string("Event #", e.event_number === nothing ? "#f" : e.event_number,
           "  Type: ", replace(String(e.event_type), "_" => "-"),
           "  Time: ", e.time_of_occurrence, "  Temperature: ", e.temperature)

"""`(type? type)` — `any` matches every event."""
event_type_is(e::GenericEvent, type::Symbol) =
    type === :any || type === e.event_type

get_event_number(e::GenericEvent) = e.event_number
set_event_number!(e::GenericEvent, n::Int) = (e.event_number = n; e)
get_event_type(e::GenericEvent) = e.event_type
get_time(e::GenericEvent) = e.time_of_occurrence
get_temperature(e::GenericEvent) = e.temperature
get_structures(e::GenericEvent) = e.workspace_structures
get_active_theme_types(e::GenericEvent) = e.active_theme_types
get_complete_themespace_patterns(e::GenericEvent) = e.complete_themespace_patterns
get_dominant_themespace_patterns(e::GenericEvent) = e.dominant_themespace_patterns

"""`(get-age)` — how many codelets ago this happened."""
get_age(e::GenericEvent, ctx) = ctx.codelet_count - e.time_of_occurrence

"""`(get-complete-themespace-pattern theme-type)` — `assq` on the stored
patterns, so `nothing` when the type is not among the possible ones."""
function get_complete_themespace_pattern(e::GenericEvent, theme_type::Symbol)
    i = findfirst(p -> p[1] === theme_type, e.complete_themespace_patterns)
    return i === nothing ? nothing : e.complete_themespace_patterns[i]
end

function get_dominant_themespace_pattern(e::GenericEvent, theme_type::Symbol)
    i = findfirst(p -> p[1] === theme_type, e.dominant_themespace_patterns)
    return i === nothing ? nothing : e.dominant_themespace_patterns[i]
end

"""`(make-temporal-trace)`. NB: `event-list` is CONSed, so it is NEWEST FIRST,
and every `select` over it therefore finds the most recent match."""
mutable struct TemporalTrace
    event_list::Vector{Any}
    next_event_number::Int
    last_clamp_time::Union{Nothing,Int}
    last_unclamp_time::Union{Nothing,Int}
    within_clamp_period::Bool
    within_snag_period::Bool
end

make_temporal_trace() = TemporalTrace(Any[], 1, nothing, nothing, false, false)

function initialize!(tr::TemporalTrace)
    tr.event_list = Any[]
    tr.next_event_number = 1
    tr.last_clamp_time = nothing
    tr.last_unclamp_time = nothing
    tr.within_clamp_period = false
    tr.within_snag_period = false
    return tr
end

get_all_events(tr::TemporalTrace) = tr.event_list

"""`(get-event n)` — by event number."""
function get_event(tr::TemporalTrace, n::Int)
    i = findfirst(e -> get_event_number(e) == n, tr.event_list)
    return i === nothing ? nothing : tr.event_list[i]
end

get_events(tr::TemporalTrace, event_type::Symbol) =
    Any[e for e in tr.event_list if event_type_is(e, event_type)]

get_num_of_events(tr::TemporalTrace, event_type::Symbol) =
    count(e -> event_type_is(e, event_type), tr.event_list)

"""`(get-last-event event-type/s)` — the most recent event of that type, or of
any of those types. The list is newest first, so this is just the first match."""
function get_last_event(tr::TemporalTrace, event_type::Symbol)
    i = findfirst(e -> event_type_is(e, event_type), tr.event_list)
    return i === nothing ? nothing : tr.event_list[i]
end

function get_last_event(tr::TemporalTrace, event_types::AbstractVector{Symbol})
    i = findfirst(e -> get_event_type(e) in event_types, tr.event_list)
    return i === nothing ? nothing : tr.event_list[i]
end

"""`(get-new-events-since-last event-type/s)`.

NB: this counts back by EVENT NUMBER, not by scanning — the newest
`(length - number)` events are the ones after it. With no such event yet, every
event counts as new."""
function get_new_events_since_last(tr::TemporalTrace, event_type)
    last_event = get_last_event(tr, event_type)
    last_event === nothing && return tr.event_list
    n = length(tr.event_list) - get_event_number(last_event)
    return tr.event_list[1:min(n, length(tr.event_list))]
end

"""`(get-new-structures-since-last event-type/s)` — what the workspace has
built since that event, by set difference against the snapshot it stored."""
function get_new_structures_since_last(tr::TemporalTrace, event_type, ctx)
    last_event = get_last_event(tr, event_type)
    current = get_structures(ctx)
    last_event === nothing && return current
    old = get_structures(last_event)
    return Any[s for s in current if !any(x -> x === s, old)]
end

"""`(get-elapsed-time event-type)` — how long since the last event of that
type, or the whole run so far if there has been none."""
function get_elapsed_time(tr::TemporalTrace, event_type::Symbol, ctx)
    last_event = get_last_event(tr, event_type)
    return last_event === nothing ? ctx.codelet_count : get_age(last_event, ctx)
end

get_last_clamp_time(tr::TemporalTrace) = tr.last_clamp_time
get_last_unclamp_time(tr::TemporalTrace) = tr.last_unclamp_time
within_clamp_period(tr::TemporalTrace) = tr.within_clamp_period
within_snag_period(tr::TemporalTrace) = tr.within_snag_period

"""`(within-grace-period?)` — the quiet spell after a clamp is undone."""
within_grace_period(tr::TemporalTrace, ctx) =
    !tr.within_clamp_period && tr.last_unclamp_time !== nothing &&
    ctx.codelet_count < (tr.last_unclamp_time::Int) + GRACE_PERIOD

"""`(permission-to-clamp?)` — not while clamped, and not during the grace
period that follows one."""
permission_to_clamp(tr::TemporalTrace, ctx) =
    SELF_WATCHING_ENABLED[] && !tr.within_clamp_period &&
    !within_grace_period(tr, ctx)

"""`(clamp-period-expired?)`."""
clamp_period_expired(tr::TemporalTrace, ctx) =
    tr.within_clamp_period && tr.last_clamp_time !== nothing &&
    ctx.codelet_count > (tr.last_clamp_time::Int) + MAX_CLAMP_PERIOD

"""`(current-answer?)` — an answer event exists and happened just now."""
current_answer(tr::TemporalTrace, ctx) =
    get_last_event(tr, :answer) !== nothing &&
    get_elapsed_time(tr, :answer, ctx) == 0

"""`(immediate-snag-condition?)`."""
immediate_snag_condition(tr::TemporalTrace, ctx) =
    tr.within_snag_period && get_elapsed_time(tr, :snag, ctx) == 0

"""`(add-event new-event)`. NB: a clamp event opens the clamp period AND stamps
the clamp time; a snag event opens the snag period but stamps nothing."""
function add_event!(tr::TemporalTrace, new_event, ctx)
    set_event_number!(new_event, tr.next_event_number)
    tr.next_event_number += 1
    pushfirst!(tr.event_list, new_event)
    if event_type_is(new_event, :clamp)
        tr.within_clamp_period = true
        tr.last_clamp_time = ctx.codelet_count
    end
    if event_type_is(new_event, :snag)
        tr.within_snag_period = true
    end
    return tr
end

"""`(clamp-progress-amount-phrase progress)` and
`(clamp-progress-adjective-phrase progress)` — how the commentary describes
how much a clamp achieved."""
function clamp_progress_amount_phrase(progress)
    progress == 0 && return "zero"
    progress < 50 && return "very little"
    progress < 80 && return "some"
    return "a lot of"
end

function clamp_progress_adjective_phrase(progress)
    progress == 0 && return "a pretty useless"
    progress < 50 && return "not such a great"
    progress < 80 && return "an okay"
    return "a pretty good"
end
