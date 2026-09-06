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
