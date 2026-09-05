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
# The rest of trace.ss — the temporal trace itself and its eight event types,
# and the monitors that watch the workspace and raise events — is not ported
# yet. `print-pattern` is also skipped: it needs `relation-name` from
# theme-graphics.ss, which the headless harness never loads.

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
