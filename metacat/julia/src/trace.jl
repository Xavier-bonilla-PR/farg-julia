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
function clamp_concept_pattern!(concept_pattern, ctx = nothing)
    for entry in entries(concept_pattern)
        clamp_activation!(entry[1], entry[2], ctx)
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

"""`(clamp-codelet-pattern codelet-pattern)`. The codelet count is threaded in
because moving a codelet between bins re-stamps it — see `set_urgency!`."""
function clamp_codelet_pattern!(codelet_pattern, cr::Coderack, codelet_count::Int)
    for entry in entries(codelet_pattern)
        clamp_codelet_type!(entry[1], entry[2], cr, codelet_count)
    end
    return codelet_pattern
end

"""`(unclamp-codelet-pattern codelet-pattern)`."""
function unclamp_codelet_pattern!(codelet_pattern, cr::Coderack, codelet_count::Int)
    for entry in entries(codelet_pattern)
        unclamp_codelet_type!(entry[1], cr, codelet_count)
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

# ============================================================================
# trace.ss slice (C): the concrete event types (trace.ss 333-1310).
#
# An event is what the trace remembers: a thing that happened, together with
# the snapshot `make_generic_event` took at the moment it happened. The four
# types below are the WORKSPACE and SLIPNET events — the ones raised by the
# model perceiving something, as opposed to by the model reacting to its own
# history. Each wraps a `GenericEvent` and adds what it needs to describe
# itself, compare itself against another of its kind, and say what pattern of
# themes or concepts it stands for.
#
# The three workspace ones (concept-mapping, group, rule) also answer to the
# type `:workspace`, which is how the trace asks for "anything the model
# perceived" without naming the kinds.
#
# All the graphics halves (`display`, `display-workspace`) are dropped: they
# only drive SWL windows.

"""The concrete events, so the `GenericEvent` accessors can forward through
one set of methods rather than one per type."""
abstract type ConcreteEvent end

generic(e::ConcreteEvent) = e.generic

get_event_number(e::ConcreteEvent) = get_event_number(generic(e))
set_event_number!(e::ConcreteEvent, n::Int) = (set_event_number!(generic(e), n); e)
get_event_type(e::ConcreteEvent) = get_event_type(generic(e))
get_time(e::ConcreteEvent) = get_time(generic(e))
get_temperature(e::ConcreteEvent) = get_temperature(generic(e))
get_structures(e::ConcreteEvent) = get_structures(generic(e))
get_active_theme_types(e::ConcreteEvent) = get_active_theme_types(generic(e))
get_complete_themespace_patterns(e::ConcreteEvent) =
    get_complete_themespace_patterns(generic(e))
get_dominant_themespace_patterns(e::ConcreteEvent) =
    get_dominant_themespace_patterns(generic(e))
get_complete_themespace_pattern(e::ConcreteEvent, tt::Symbol) =
    get_complete_themespace_pattern(generic(e), tt)
get_dominant_themespace_pattern(e::ConcreteEvent, tt::Symbol) =
    get_dominant_themespace_pattern(generic(e), tt)
get_age(e::ConcreteEvent, ctx) = get_age(generic(e), ctx)
get_clamped_rules(e::ConcreteEvent) = generic(e).clamped_rules

"""`(type? type)` on a concrete event — its own type, or `any`. The three
workspace types override this to answer to `:workspace` as well."""
event_type_is(e::ConcreteEvent, type::Symbol) = event_type_is(generic(e), type)

# --- concept-activation events ----------------------------------------------

"""`(make-concept-activation-event slipnode)` — a concept coming fully awake
is itself a thing that happened, and worth remembering as one."""
struct ConceptActivationEvent <: ConcreteEvent
    generic::GenericEvent
    slipnode::Node
    print_name::String
    concept_pattern::Vector{Any}
end

function make_concept_activation_event(slipnode::Node, ctx)
    return ConceptActivationEvent(
        make_generic_event(:concept_activation, ctx),
        slipnode,
        string("(", slipnode.short_name, ")"),
        Any[:concepts, Any[slipnode, MAX_ACTIVATION]])
end

event_print_name(e::ConceptActivationEvent) = e.print_name
get_slipnode(e::ConceptActivationEvent) = e.slipnode
get_concept_pattern(e::ConceptActivationEvent) = e.concept_pattern
get_event_strength(e::ConceptActivationEvent) = e.slipnode.conceptual_depth

events_equal(e::ConceptActivationEvent, other) =
    event_type_is(other, :concept_activation) && get_slipnode(other) === e.slipnode

# --- concept-mapping events -------------------------------------------------

"""`(make-concept-mapping-event cm bridge)` — a bridge making a slippage the
model thinks is worth noticing."""
struct ConceptMappingEvent <: ConcreteEvent
    generic::GenericEvent
    cm::ConceptMapping
    bridge::Bridge
    bridge_type::Symbol
    print_name::String
    slippage::Bool
    theme_pattern::Vector{Any}
    cm_strength::Int
    concept_pattern::Vector{Any}
end

function make_concept_mapping_event(cm::ConceptMapping, bridge::Bridge, ctx)
    bridge_type = bridge.bridge_type
    tag = bridge_type === :top ? "T" : bridge_type === :vertical ? "V" : "B"
    return ConceptMappingEvent(
        make_generic_event(:concept_mapping, ctx),
        cm, bridge, bridge_type,
        string(tag, ":", cm_print_name(cm, ctx.net)),
        is_slippage(cm),
        Any[bridge_type_to_theme_type(bridge_type), Any[cm_type(cm), cm.label]],
        cm_strength(cm),
        get_concept_pattern(cm))
end

event_print_name(e::ConceptMappingEvent) = e.print_name
get_concept_mapping(e::ConceptMappingEvent) = e.cm
get_bridge(e::ConceptMappingEvent) = e.bridge
get_bridge_type(e::ConceptMappingEvent) = e.bridge_type
get_cm_type(e::ConceptMappingEvent) = cm_type(e.cm)
is_cm_type(e::ConceptMappingEvent, t::Node) = t === cm_type(e.cm)
is_bridge_type(e::ConceptMappingEvent, t::Symbol) = t === e.bridge_type
get_theme_pattern(e::ConceptMappingEvent) = e.theme_pattern
get_concept_pattern(e::ConceptMappingEvent) = e.concept_pattern
get_event_strength(e::ConceptMappingEvent) = e.cm_strength
is_event_slippage(e::ConceptMappingEvent) = e.slippage

event_type_is(e::ConceptMappingEvent, type::Symbol) =
    type === :workspace || event_type_is(generic(e), type)

"""`(currently-present?)` — whether the bridge this event describes is still
in the workspace. The event holds the bridge it was made from, which may since
have been broken and rebuilt."""
event_currently_present(e::ConceptMappingEvent, ctx) = bridge_present(ctx, e.bridge)
get_equivalent_bridge(e::ConceptMappingEvent, ctx) = get_equivalent_bridge(ctx, e.bridge)

relevant_for_answer_description(e::ConceptMappingEvent, ctx) =
    e.bridge_type === :vertical && event_currently_present(e, ctx)

events_equal(e::ConceptMappingEvent, other, net::Slipnet) =
    event_type_is(other, :concept_mapping) &&
    cms_equal(e.cm, get_concept_mapping(other))

# --- group events -----------------------------------------------------------

"""`(group-event-pexp-text-string group)`, from trace-graphics.ss — the group
spelled out along its bond facet, `a-b-c` or `1-2-3`. It lives in a graphics
file, but it NAMES the event, so it is algorithm-visible and comes here."""
function group_event_pexp_text_string(g::Group, net::Slipnet)
    bond_facet = g.group_bond_facet::Node
    parts = String[]
    for o in g.constituent_objects
        d = get_descriptor_for(o, bond_facet)::Node
        push!(parts, platonic_number(net, d) ?
                     string(platonic_number_to_number(net, d)) :
                     (o isa Letter ? d.lowercase_name : d.uppercase_name))
    end
    return join(parts, "-")
end

"""`(platonic-number? node)` / `(platonic-number->number node)`."""
platonic_number(net::Slipnet, node::Node) = any(n -> n === node, net.numbers)
platonic_number_to_number(net::Slipnet, node::Node) =
    findfirst(n -> n === node, net.numbers)

"""`(make-group-event group flipped?)` — a group being built, or FLIPPED from
a successor reading to a predecessor one (or back), which is a different kind
of event about the same group."""
struct GroupEvent <: ConcreteEvent
    generic::GenericEvent
    group::Group
    flipped::Bool
    print_name::String
    group_category::Node
    direction::Union{Nothing,Node}
    group_strength::Int
    concept_pattern::Vector{Any}
end

function make_group_event(group::Group, flipped::Bool, ctx)
    net = ctx.net
    text = group_event_pexp_text_string(group, net)
    direction = group.direction
    name = direction === net[:plato_right] ? string(">", text, ">") :
           direction === net[:plato_left]  ? string("<", text, "<") :
                                             string("[", text, "]")
    return GroupEvent(make_generic_event(:group, ctx), group, flipped, name,
                      group.group_category, direction, group.strength,
                      get_concept_pattern(group))
end

event_print_name(e::GroupEvent) = e.print_name
get_group(e::GroupEvent) = e.group
is_event_flipped(e::GroupEvent) = e.flipped
get_group_category(e::GroupEvent) = e.group_category
get_event_direction(e::GroupEvent) = e.direction
get_concept_pattern(e::GroupEvent) = e.concept_pattern
get_event_strength(e::GroupEvent) = e.group_strength
is_event_spanning(e::GroupEvent) = spans_whole_string(e.group)
get_event_string_type(e::GroupEvent) = e.group.string.string_type
is_event_string_type(e::GroupEvent, t::Symbol) = get_event_string_type(e) === t
event_spans(e::GroupEvent, t::Symbol) =
    is_event_spanning(e) && is_event_string_type(e, t)

event_type_is(e::GroupEvent, type::Symbol) =
    type === :workspace || event_type_is(generic(e), type)

event_currently_present(e::GroupEvent) = group_present(e.group.string, e.group)
get_equivalent_group(e::GroupEvent) = get_equivalent_group(e.group.string, e.group)

relevant_for_answer_description(e::GroupEvent) =
    is_event_spanning(e) && event_currently_present(e)

events_equal(e::GroupEvent, other) =
    event_type_is(other, :group) &&
    equivalent_workspace_objects(get_group(other), e.group)

# --- rule events ------------------------------------------------------------

"""`(make-rule-event rule)` — a rule being built. The reference objects and
supporting bridges are captured NOW, because what makes the rule interesting
is what it rested on at the time, which the workspace may since have broken."""
struct RuleEvent <: ConcreteEvent
    generic::GenericEvent
    rule::Rule
    rule_type::Symbol
    print_name::String
    supporting_bridges::Vector{Bridge}
    reference_objects::Vector{Any}
    relative_quality::Int
    concept_pattern::Vector{Any}
end

function make_rule_event(rule::Rule, ctx)
    rule_type = rule.rule_type
    s = rule_type === :top ? ctx.initial_string : ctx.target_string
    # workspace-strings are filtered out: a rule can refer to the string as a
    # whole, but the string is not an object anything can be highlighted on.
    reference_objects = Any[o for o in get_all_reference_objects(s, rule, ctx.net)
                            if !(o isa WorkspaceString)]
    return RuleEvent(make_generic_event(:rule, ctx), rule, rule_type,
                     rule_type === :top ? "[Top Rule]" : "[Bottom Rule]",
                     copy(rule.supporting_horizontal_bridges),
                     reference_objects,
                     get_relative_quality(rule, ctx),
                     get_concept_pattern(rule))
end

event_print_name(e::RuleEvent) = e.print_name
get_rule(e::RuleEvent) = e.rule
get_rule_type(e::RuleEvent) = e.rule_type
get_supporting_bridges(e::RuleEvent) = e.supporting_bridges
get_reference_objects(e::RuleEvent) = e.reference_objects
get_concept_pattern(e::RuleEvent) = e.concept_pattern
"""Both `get-relative-quality` and `get-strength` answer with the quality the
rule had WHEN THE EVENT HAPPENED, not the quality it has now."""
get_event_relative_quality(e::RuleEvent) = e.relative_quality
get_event_strength(e::RuleEvent) = e.relative_quality

event_type_is(e::RuleEvent, type::Symbol) =
    type === :workspace || event_type_is(generic(e), type)

events_equal(e::RuleEvent, other, net::Slipnet) =
    event_type_is(other, :rule) && rules_equal(e.rule, get_rule(other), net)

# --- names (trace.ss 1258-1310) ---------------------------------------------

"""`(group-present? group)` — the group's own string still holds it, or an
equivalent one built since."""
group_present(s::WorkspaceString, g::Group) = get_equivalent_group(s, g) !== nothing

"""`(full-slipnode-name slipnode)` — the reader-facing name of a concept. The
categories differ from both their short and their lowercase names, and the
three group categories are spelled out rather than abbreviated."""
function full_slipnode_name(node::Node, net::Slipnet)
    node === net[:plato_alphabetic_position_category] && return "Alphabetic-Position"
    node === net[:plato_bond_facet] && return "Bond-Facet"
    node === net[:plato_object_category] && return "Object-Category"
    node === net[:plato_letter_category] && return "Letter-Category"
    node === net[:plato_length] && return "Length"
    node === net[:plato_bond_category] && return "Bond-Category"
    node === net[:plato_group_category] && return "Group-Category"
    node === net[:plato_direction_category] && return "Direction"
    node === net[:plato_string_position_category] && return "String-Position"
    node === net[:plato_opposite] && return "Opposite"
    node === net[:plato_identity] && return "Identity"
    node === net[:plato_predgrp] && return "predecessor-group"
    node === net[:plato_succgrp] && return "successor-group"
    node === net[:plato_samegrp] && return "sameness-group"
    return node.lowercase_name
end

"""`(unflipped-group-name group)` — a flipped group is named by what it was
BEFORE the flip, which is why the two categories come out swapped. NB the
Scheme's `cond` has no `else`: a sameness group returns Chez's unspecified
value, since a sameness group cannot be flipped."""
function unflipped_group_name(g::Group, net::Slipnet)
    g.group_category === net[:plato_predgrp] && return "successor-group"
    g.group_category === net[:plato_succgrp] && return "predecessor-group"
    return nothing
end

"""`(full-workspace-object-name object)`. Same missing `else` as above."""
function full_workspace_object_name(o::WSObject, net::Slipnet)
    o isa Letter && return "letter"
    g = o::Group
    g.group_category === net[:plato_samegrp] && return "sameness-group"
    g.group_category === net[:plato_predgrp] && return "predecessor-group"
    g.group_category === net[:plato_succgrp] && return "successor-group"
    return nothing
end

"""`(snag-object-phrase object)` — how a snag event names the thing it snagged
on, in the prose Metacat writes about itself."""
function snag_object_phrase(o)
    o isa WorkspaceString && return string("the string \"", o.print_name, "\"")
    o isa Letter && return string("the letter ", print_name(o))
    return string("the ", join([print_name(l) for l in get_letters(o)]), " group")
end

# ============================================================================
# trace.ss slice (C), part 2: the SELF-WATCHING events.
#
# Where the four types above record the model perceiving something, these three
# record it reacting to its own history. An ANSWER event is a result reached; a
# CLAMP event is the model deciding to force itself into a pattern it has
# noticed; a SNAG event is a rule that could not be applied and the impasse
# that follows. The last two are the only events that are ACTIVATED and
# DEACTIVATED — they do not merely describe a state, they impose one — and the
# only ones carrying a PROGRESS EVALUATOR, which is how the trace later asks
# whether the detour was worth taking.

# --- answer events ----------------------------------------------------------

"""`(make-answer-event ...)` — a result reached, with everything it rested on:
both rules, the vertical mapping that let one be read as the other, the groups
and reference objects involved, and the slippage log of the translation.

`unjustified_slippages` is non-empty when Metacat settled for an answer it
could not fully account for, which is the difference between finding an answer
and justifying one."""
mutable struct AnswerEvent <: ConcreteEvent
    generic::GenericEvent
    initial_string::WorkspaceString
    modified_string::WorkspaceString
    target_string::WorkspaceString
    answer_string::WorkspaceString
    top_rule::Rule
    bottom_rule::Rule
    supporting_vertical_bridges::Vector{Bridge}
    supporting_groups::Vector{Any}
    top_rule_ref_objects::Vector{Any}
    bottom_rule_ref_objects::Vector{Any}
    slippage_log::SlippageLog
    unjustified_slippages::Vector{ConceptMapping}
    """Filled in later by the memory, which abstracts the event into a
    description it can compare against remembered answers."""
    answer_description::Any
end

function make_answer_event(initial_string, modified_string, target_string,
                           answer_string, top_rule::Rule, bottom_rule::Rule,
                           supporting_vertical_bridges, supporting_groups,
                           top_rule_ref_objects, bottom_rule_ref_objects,
                           slippage_log::SlippageLog, unjustified_slippages, ctx)
    return AnswerEvent(make_generic_event(:answer, ctx),
                       initial_string, modified_string, target_string, answer_string,
                       top_rule, bottom_rule,
                       Bridge[supporting_vertical_bridges...],
                       Any[supporting_groups...],
                       Any[top_rule_ref_objects...], Any[bottom_rule_ref_objects...],
                       slippage_log, ConceptMapping[unjustified_slippages...],
                       nothing)
end

event_print_name(e::AnswerEvent) = string("[Answer ", e.answer_string.print_name, "]")

problem_print_name(e::AnswerEvent) =
    string(e.initial_string.print_name, " => ", e.modified_string.print_name, "; ",
           e.target_string.print_name, " => ?")

problem_answer_print_name(e::AnswerEvent) =
    string(e.initial_string.print_name, " => ", e.modified_string.print_name, "; ",
           e.target_string.print_name, " => ", e.answer_string.print_name)

get_initial_string(e::AnswerEvent) = e.initial_string
get_modified_string(e::AnswerEvent) = e.modified_string
get_target_string(e::AnswerEvent) = e.target_string
get_answer_string(e::AnswerEvent) = e.answer_string
get_initial_letters(e::AnswerEvent) = e.initial_string.letter_categories
get_modified_letters(e::AnswerEvent) = e.modified_string.letter_categories
get_target_letters(e::AnswerEvent) = e.target_string.letter_categories
get_answer_letters(e::AnswerEvent) = e.answer_string.letter_categories
get_slippage_log(e::AnswerEvent) = e.slippage_log
get_supporting_groups(e::AnswerEvent) = e.supporting_groups
get_unjustified_slippages(e::AnswerEvent) = e.unjustified_slippages
is_unjustified(e::AnswerEvent) = !isempty(e.unjustified_slippages)
get_answer_description(e::AnswerEvent) = e.answer_description
set_answer_description!(e::AnswerEvent, a) = (e.answer_description = a; e)

get_event_rule(e::AnswerEvent, rule_type::Symbol) =
    rule_type === :top ? e.top_rule : e.bottom_rule

get_rule_ref_objects(e::AnswerEvent, rule_type::Symbol) =
    rule_type === :top ? e.top_rule_ref_objects : e.bottom_rule_ref_objects

"""The top and bottom mappings come from the RULES, which hold their own
supporting bridges; only the vertical one is stored on the event."""
function get_supporting_bridges(e::AnswerEvent, type::Symbol)
    type === :top && return e.top_rule.supporting_horizontal_bridges
    type === :vertical && return e.supporting_vertical_bridges
    return e.bottom_rule.supporting_horizontal_bridges
end

"""`(get-absolute-quality)` / `(get-relative-quality)` — how good the answer is,
60% the rule's quality and 40% how cold the model was when it found it. A cold
model has settled, so it believes itself more."""
get_absolute_quality(e::AnswerEvent) =
    sround(weighted_average([e.top_rule.quality, sub_from_100(get_temperature(e))],
                            [60, 40]))

get_event_relative_quality(e::AnswerEvent, ctx) =
    sround(weighted_average([get_relative_quality(e.top_rule, ctx),
                             sub_from_100(get_temperature(e))], [60, 40]))

get_event_quality(e::AnswerEvent) = get_absolute_quality(e)
get_event_strength(e::AnswerEvent) = get_absolute_quality(e)

"""NB: ANY two answer events are equal. The trace holds at most one answer for
a given problem, so the type alone identifies it."""
events_equal(e::AnswerEvent, other) = event_type_is(other, :answer)

# --- clamp events -----------------------------------------------------------

"""`(make-clamp-event clamp-type patterns rules progress-focus)` — the model
forcing itself into a pattern it has noticed about its own processing.

The patterns handed in are sorted by kind. A theme pattern also contributes the
concept pattern it implies, so clamping "string-position opposite" also wakes
the concepts that idea is made of.

`progress_focus` names the event type that counts as progress while this clamp
is up: the evaluator scores an event by its strength if it is of that type, and
0 otherwise."""
mutable struct ClampEvent <: ConcreteEvent
    generic::GenericEvent
    clamp_type::Symbol          # :rule_codelet_clamp | :snag_response_clamp |
                                # :justify_clamp | :manual_clamp
    clamped_theme_patterns::Vector{Any}
    clamped_concept_patterns::Vector{Any}
    clamped_codelet_patterns::Vector{Any}
    theme_related_concept_patterns::Vector{Any}
    rules::Vector{Rule}
    unifying_slippages::Union{Nothing,Vector{ConceptMapping}}
    progress_focus::Symbol
    progress_achieved::Int
end

function make_clamp_event(clamp_type::Symbol, patterns, rules, progress_focus::Symbol,
                          ctx)
    specified_theme_patterns = Any[p for p in patterns if is_theme_pattern(p)]
    specified_concept_patterns = Any[p for p in patterns if is_concept_pattern(p)]
    specified_codelet_patterns = Any[p for p in patterns if is_codelet_pattern(p)]
    theme_related = Any[get_associated_concept_pattern(p, ctx.net)
                        for p in specified_theme_patterns]
    rules_v = Rule[rules...]
    # A justify clamp is clamping two rules it believes unify, so it records
    # the slippages that unification rests on. Any other clamp has no rules.
    unifying = nothing
    if clamp_type === :justify_clamp
        top = rules_v[findfirst(r -> r.rule_type === :top, rules_v)]
        bottom = rules_v[findfirst(r -> r.rule_type === :bottom, rules_v)]
        unifying = get_unifying_slippages(top, bottom, ctx.net)
    end
    return ClampEvent(make_generic_event(:clamp, ctx), clamp_type,
                      specified_theme_patterns,
                      Any[specified_concept_patterns..., theme_related...],
                      specified_codelet_patterns, theme_related, rules_v,
                      unifying, progress_focus, 0)
end

event_print_name(e::ClampEvent) = "[Clamp]"
get_clamped_theme_patterns(e::ClampEvent) = e.clamped_theme_patterns
get_clamped_concept_patterns(e::ClampEvent) = e.clamped_concept_patterns
get_clamped_codelet_patterns(e::ClampEvent) = e.clamped_codelet_patterns
get_theme_related_concept_patterns(e::ClampEvent) = e.theme_related_concept_patterns
get_clamp_type(e::ClampEvent) = e.clamp_type
is_clamp_type(e::ClampEvent, type::Symbol) = type === e.clamp_type
get_progress_focus(e::ClampEvent) = e.progress_focus
get_progress_achieved(e::ClampEvent) = e.progress_achieved
update_progress_achieved!(e::ClampEvent, v::Int) = (e.progress_achieved = v; e)
get_event_rules(e::ClampEvent) = e.rules
get_unifying_slippages(e::ClampEvent) = e.unifying_slippages
get_event_strength(e::ClampEvent) = 100

# NB: the Scheme's `get-complement-codelet-pattern` method reads a variable that
# its `let*` never binds — the top-level `get-complement-codelet-pattern` is a
# different name — so calling it raises an unbound-variable error in Chez.
# Nothing calls it. It is not ported rather than silently given a value.

function get_event_rule(e::ClampEvent, rule_type::Symbol)
    i = findfirst(r -> r.rule_type === rule_type, e.rules)
    return i === nothing ? nothing : e.rules[i]
end

get_all_clamped_patterns(e::ClampEvent) =
    Any[e.clamped_theme_patterns..., e.clamped_concept_patterns...,
        e.clamped_codelet_patterns...]

"""`(get-progress-evaluator)` — score an EVENT: its strength if it is of the
focused type, 0 otherwise."""
progress_evaluator(e::ClampEvent, event) =
    event_type_is(event, e.progress_focus) ? get_event_strength(event) : 0

events_equal(e::ClampEvent, other, net::Slipnet) =
    event_type_is(other, :clamp) && is_clamp_type(other, e.clamp_type) &&
    e.progress_focus === get_progress_focus(other) &&
    sets_equal_pred((r1, r2) -> rules_equal(r1, r2, net), e.rules,
                    get_event_rules(other))

"""`(activate)` — impose everything the clamp names. The comment window is
graphics, so only the model-visible half is here."""
function activate!(e::ClampEvent, tr::TemporalTrace, ctx)
    undo_snag_condition!(tr, ctx)
    for rule in e.rules
        clamp_rule!(ctx, rule)
    end
    for pattern in e.clamped_theme_patterns
        clamp_theme_pattern!(ctx.themespace, pattern)
    end
    for pattern in e.clamped_concept_patterns
        clamp_concept_pattern!(pattern, ctx)
    end
    for pattern in e.clamped_codelet_patterns
        clamp_codelet_pattern!(pattern, ctx.coderack, ctx.codelet_count)
    end
    return e
end

function deactivate!(e::ClampEvent, ctx)
    for rule in e.rules
        unclamp_rule!(ctx, rule)
    end
    for pattern in e.clamped_theme_patterns
        unclamp_theme_pattern!(ctx.themespace, pattern)
    end
    for pattern in e.clamped_concept_patterns
        unclamp_concept_pattern!(pattern)
    end
    for pattern in e.clamped_codelet_patterns
        unclamp_codelet_pattern!(pattern, ctx.coderack, ctx.codelet_count)
    end
    return e
end

# --- snag events ------------------------------------------------------------

"""`(get-snag-theme-pattern snag-concept-mappings)` — the vertical theme
pattern the snag implicates. `remove-duplicates` is VALUE equality here, and
keeps the LAST of each group."""
function get_snag_theme_pattern(snag_concept_mappings)
    raw = Any[Any[cm_type(cm), cm.label] for cm in snag_concept_mappings]
    deduped = Any[x for (i, x) in enumerate(raw)
                  if !any(y -> y[1] === x[1] && y[2] === x[2], raw[(i + 1):end])]
    return Any[:vertical_bridge, deduped...]
end

"""`(get-snag-concept-pattern snag-objects)` — every descriptor of every object
the snag involved, clamped. `remq-duplicates` keeps the LAST of each group."""
function get_snag_concept_pattern(snag_objects)
    descriptors = Node[]
    for o in snag_objects
        append!(descriptors, get_all_descriptors(o))
    end
    deduped = Node[n for (i, n) in enumerate(descriptors)
                   if !any(x -> x === n, descriptors[(i + 1):end])]
    return Any[:concepts, Any[Any[d, MAX_ACTIVATION] for d in deduped]...]
end

"""`(make-snag-event ...)` — a rule that could not be applied, and the impasse
that follows. The failure result says which of the three ways it failed, and
which objects it failed on; those objects have their salience CLAMPED while the
snag is active, so the model keeps looking at what tripped it up."""
mutable struct SnagEvent <: ConcreteEvent
    generic::GenericEvent
    failure_result::Vector{Any}
    snag_type::Symbol                  # :SWAP | :CONFLICT | :CHANGE
    rule::Rule
    translated_rule::Rule
    supporting_vertical_bridges::Vector{Bridge}
    slippage_log::SlippageLog
    rule_ref_objects::Vector{Any}
    snag_objects::Vector{Any}
    snag_bridges::Vector{Bridge}
    snag_concept_mappings::Vector{ConceptMapping}
    snag_theme_pattern::Vector{Any}
    snag_concept_pattern::Vector{Any}
    progress_achieved::Int
end

function make_snag_event(failure_result, rule::Rule, translated_rule::Rule,
                         supporting_vertical_bridges, slippage_log::SlippageLog,
                         rule_ref_objects, ctx)
    snag_type = failure_result[1]::Symbol
    snag_objects = snag_type === :SWAP     ? Any[failure_result[2]...] :
                   snag_type === :CONFLICT ? Any[failure_result[2], failure_result[4]] :
                                             Any[failure_result[2]]
    snag_bridges = Bridge[b for b in (get_bridge(o, :vertical) for o in snag_objects)
                          if b !== nothing]
    # With no vertical bridge on any snagged object, the snag implicates the
    # whole vertical mapping instead.
    snag_concept_mappings = isempty(snag_bridges) ?
        get_all_vertical_cms(ctx) :
        ConceptMapping[cm for b in snag_bridges for cm in b.all_concept_mappings]
    return SnagEvent(make_generic_event(:snag, ctx), Any[failure_result...], snag_type,
                     rule, translated_rule, Bridge[supporting_vertical_bridges...],
                     slippage_log, Any[rule_ref_objects...], snag_objects,
                     snag_bridges, snag_concept_mappings,
                     get_snag_theme_pattern(snag_concept_mappings),
                     get_snag_concept_pattern(snag_objects), 0)
end

event_print_name(e::SnagEvent) = "[Snag]"
get_failure_result(e::SnagEvent) = e.failure_result
get_snag_type(e::SnagEvent) = e.snag_type
get_snag_objects(e::SnagEvent) = e.snag_objects
get_snag_bridges(e::SnagEvent) = e.snag_bridges
get_snag_concept_mappings(e::SnagEvent) = e.snag_concept_mappings
get_snag_theme_pattern(e::SnagEvent) = e.snag_theme_pattern
get_snag_concept_pattern(e::SnagEvent) = e.snag_concept_pattern
get_slippage_log(e::SnagEvent) = e.slippage_log
get_rule_ref_objects(e::SnagEvent) = e.rule_ref_objects
get_progress_achieved(e::SnagEvent) = e.progress_achieved
update_progress_achieved!(e::SnagEvent, v::Int) = (e.progress_achieved = v; e)
get_event_strength(e::SnagEvent) = 100

"""The translated rule is the "bottom" one here: it is the reading that failed."""
get_event_rule(e::SnagEvent, rule_type::Symbol) =
    rule_type === :top ? e.rule : e.translated_rule

"""A snag has no supporting BOTTOM bridges, because the translated rule failed."""
get_supporting_bridges(e::SnagEvent, bridge_type::Symbol) =
    bridge_type === :top ? e.rule.supporting_horizontal_bridges :
                           e.supporting_vertical_bridges

"""`(get-progress-evaluator)` — score a STRUCTURE, not an event: its strength,
unless it is a bond, which is too cheap to count as getting anywhere."""
snag_progress_evaluator(structure) = structure isa Bond ? 0 : structure.strength

events_equal(e::SnagEvent, other, net::Slipnet) =
    event_type_is(other, :snag) &&
    rules_equal(e.translated_rule, get_event_rule(other, :bottom), net) &&
    sets_equal_pred(equivalent_workspace_objects, e.snag_objects,
                    get_snag_objects(other))

"""`(get-explanation)` — the English Metacat writes about why it snagged."""
function snag_explanation(e::SnagEvent, net::Slipnet)
    fr = e.failure_result
    if e.snag_type === :SWAP
        objects, dimension = fr[2], fr[3]
        return string("no ", (dimension::Node).lowercase_name, " swap is possible between ",
                      punctuate([snag_object_phrase(o) for o in objects]), " in ",
                      get_string(objects[1]).print_name)
    elseif e.snag_type === :CONFLICT
        o1, d1, o2, d2 = fr[2], fr[3], fr[4], fr[5]
        return string("changing the ", (d1::Node).lowercase_name, " of ",
                      snag_object_phrase(o1), " conflicts with changing the ",
                      (d2::Node).lowercase_name, " of ", snag_object_phrase(o2),
                      " in ", get_string(o1).print_name)
    end
    object, transform = fr[2], fr[3]
    s = get_string(object)
    if transform[1] === net[:plato_group_category]
        return string("reversing the starting and ending ",
                      (transform[3]::Node).lowercase_name, " of ",
                      snag_object_phrase(object), " is not possible in ", s.print_name)
    end
    target = platonic_relation(transform[2]::Node, net) ?
             string("its ", (transform[2]::Node).lowercase_name) :
             string("`", (transform[2]::Node).lowercase_name, "'")
    return string("changing the ", (transform[1]::Node).lowercase_name, " of ",
                  snag_object_phrase(object), " to ", target, " is not possible in ",
                  s.print_name)
end

"""`(activate)` — hold the snagged objects in view and wake the concepts they
are described by, so the model keeps worrying at what stopped it."""
function activate!(e::SnagEvent, tr::TemporalTrace, ctx)
    undo_last_clamp!(tr, ctx)
    for o in e.snag_objects
        clamp_salience!(o)
    end
    clamp_concept_pattern!(e.snag_concept_pattern)
    return e
end

function deactivate!(e::SnagEvent, ctx)
    for o in e.snag_objects
        unclamp_salience!(o)
    end
    unclamp_concept_pattern!(e.snag_concept_pattern)
    return e
end

# --- the four trace methods deferred with these events ----------------------

"""`(progress-since-last-clamp)` — the best any event since the last clamp
scored under that clamp's own evaluator."""
function progress_since_last_clamp(tr::TemporalTrace, ctx)
    last_clamp = get_last_event(tr, :clamp)
    last_clamp === nothing && return 0
    new_events = get_new_events_since_last(tr, :clamp)
    return maximum_or_zero([progress_evaluator(last_clamp::ClampEvent, ev)
                            for ev in new_events])
end

"""`(undo-last-clamp)` — end the clamp period, record what the clamp achieved,
and take back everything it imposed."""
function undo_last_clamp!(tr::TemporalTrace, ctx)
    tr.within_clamp_period || return tr
    last_clamp = get_last_event(tr, :clamp)
    progress = progress_since_last_clamp(tr, ctx)
    tr.within_clamp_period = false
    tr.last_unclamp_time = ctx.codelet_count
    if last_clamp !== nothing
        update_progress_achieved!(last_clamp::ClampEvent, progress)
        deactivate!(last_clamp::ClampEvent, ctx)
    end
    return tr
end

"""`(progress-since-last-snag)` — the best STRUCTURE built since the last snag,
scored by that snag's evaluator. Structures, not events: getting past a snag
means building something, not noticing something."""
function progress_since_last_snag(tr::TemporalTrace, ctx)
    last_snag = get_last_event(tr, :snag)
    last_snag === nothing && return 0
    new_structures = get_new_structures_since_last(tr, :snag, ctx)
    return maximum_or_zero([snag_progress_evaluator(s) for s in new_structures])
end

"""`(undo-snag-condition)`. NB the Scheme also clears `*temperature-clamped?*`,
which the port keeps on the context."""
function undo_snag_condition!(tr::TemporalTrace, ctx)
    tr.within_snag_period || return tr
    last_snag = get_last_event(tr, :snag)
    tr.within_snag_period = false
    if last_snag !== nothing
        update_progress_achieved!(last_snag::SnagEvent,
                                  progress_since_last_snag(tr, ctx))
        deactivate!(last_snag::SnagEvent, ctx)
    end
    ctx.temperature_clamped = false
    return tr
end

"""`(maximum l)` — 0 for the empty list, as utilities.ss has it."""
maximum_or_zero(l) = isempty(l) ? 0 : maximum(l)

# ============================================================================
# trace.ss slice (D): the MONITORS (trace.ss 1310-1412).
#
# This is what makes events raise themselves. Four hooks sit in the code that
# builds structure and moves slipnode activations; each asks how IMPORTANT the
# thing that just happened was, and appends an event only if it clears the
# threshold for its kind. That filter is the whole reason the trace stays small
# enough to reason over: Metacat builds thousands of structures per run and
# remembers a few dozen moments.
#
# The four thresholds differ in spirit. A group has to be REMARKABLE (100 —
# only a flip, a string-spanning group, or a singleton that has noticed its own
# length gets in). A concept waking up has to be a deep concept moving a long
# way (85). A rule needs to be decent (67). A slippage needs only to be a
# slippage worth the name (65), because slippages are what the whole program is
# about.

"""`%concept-mapping-importance-threshold%` and friends."""
const CONCEPT_MAPPING_IMPORTANCE_THRESHOLD = 65
const CONCEPT_ACTIVATION_IMPORTANCE_THRESHOLD = 85
const GROUP_IMPORTANCE_THRESHOLD = 100
const RULE_IMPORTANCE_THRESHOLD = 67

"""`(100* x)`."""
mul_100(x) = sround(100 * x)

# --- how important was that? ------------------------------------------------

"""`(concept-activation-importance slipnode prev new)` — how far the concept
moved, weighted by how deep a concept it is. A shallow concept flashing to full
activation is not news; `opposite` doing so is."""
concept_activation_importance(slipnode::Node, previous_activation::Int,
                              new_activation::Int) =
    mul_100(pct(abs(new_activation - previous_activation)) *
            pct(slipnode.conceptual_depth))

"""`(group-importance group flipped?)` — a flip, a string-spanning group, or a
singleton that has noticed its own length is always worth recording; anything
else has to be strong enough, and the threshold is 100, so in practice nothing
else gets in."""
function group_importance(g::Group, flipped::Bool, net::Slipnet)
    (flipped || spans_whole_string(g) ||
     (singleton_group(g) && description_type_present(g, net[:plato_length]))) && return 100
    return g.strength
end

"""`(rule-importance rule)` — a perfectly uniform rule is always worth
recording; otherwise it has to be good relative to the others."""
rule_importance(r::Rule, ctx) =
    r.uniformity == 100 ? 100 : get_relative_quality(r, ctx)

"""`(concept-mapping-importance cm bridge)`.

Only slippages count — an identity mapping is not news. A slippage an active
theme already supports counts for everything, because that is the model finding
what it was looking for. Otherwise it is scored by depth: the mapping's own
dimension weighs most, then whether the bridge spans the whole string, the two
descriptors, and the label. Bond-category slippages score 0: they are a
by-product of bonding, not a decision about correspondence."""
function concept_mapping_importance(cm::ConceptMapping, bridge::Bridge, ctx)
    is_slippage(cm) || return 0
    supported_by_active_theme(ctx.themespace, cm, bridge) && return 100
    net = ctx.net
    cm_type(cm) === net[:plato_bond_category] && return 0
    return sround(weighted_average(
        [cm_type(cm).conceptual_depth,
         bridge.spanning_bridge ? 100 : 0,
         sdiv(cm.descriptor1.conceptual_depth + cm.descriptor2.conceptual_depth, 2),
         cm.label === nothing ? 50 : (cm.label::Node).conceptual_depth],
        [4, 2, 2, 3]))
end

# --- the hooks --------------------------------------------------------------
#
# Each returns the event it raised, or `nothing`. They no-op when no trace is
# attached; see the `trace` field on MetacatCtx for why that is faithful.

function monitor_slipnode_activation_change(slipnode::Node, previous_activation::Int,
                                            new_activation::Int, ctx)
    ctx.trace === nothing && return nothing
    importance = concept_activation_importance(slipnode, previous_activation,
                                               new_activation)
    importance >= CONCEPT_ACTIVATION_IMPORTANCE_THRESHOLD || return nothing
    event = make_concept_activation_event(slipnode, ctx)
    add_event!(ctx.trace::TemporalTrace, event, ctx)
    return event
end

function monitor_new_concept_mappings(concept_mappings, bridge::Bridge, ctx)
    ctx.trace === nothing && return nothing
    for cm in concept_mappings
        importance = concept_mapping_importance(cm, bridge, ctx)
        importance >= CONCEPT_MAPPING_IMPORTANCE_THRESHOLD || continue
        add_event!(ctx.trace::TemporalTrace,
                   make_concept_mapping_event(cm, bridge, ctx), ctx)
    end
    return nothing
end

function monitor_new_groups(group::Group, flipped::Bool, ctx)
    ctx.trace === nothing && return nothing
    importance = group_importance(group, flipped, ctx.net)
    importance >= GROUP_IMPORTANCE_THRESHOLD || return nothing
    event = make_group_event(group, flipped, ctx)
    add_event!(ctx.trace::TemporalTrace, event, ctx)
    return event
end

function monitor_new_rules(rule::Rule, ctx)
    ctx.trace === nothing && return nothing
    importance = rule_importance(rule, ctx)
    importance >= RULE_IMPORTANCE_THRESHOLD || return nothing
    event = make_rule_event(rule, ctx)
    add_event!(ctx.trace::TemporalTrace, event, ctx)
    return event
end
