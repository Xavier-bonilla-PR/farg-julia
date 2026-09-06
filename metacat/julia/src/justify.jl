# Ported from Metacat's justify.ss — the rule-UNIFICATION machinery.
#
# Justification is Metacat asking whether two rules are really the same idea.
# A top rule describes how the initial string changes; a bottom rule describes
# how the target string changes. If one can be walked onto the other, slipping
# concepts along the way, then the two changes are the same change under a
# different reading, and the answer is justified. The slippages that walk
# survives ARE the explanation.
#
# The traversal is structural: two rules unify when their clause trees have the
# same SHAPE and every corresponding pair of slipnodes is either identical or
# joined by a lateral sliplink. Where they merely slip, the traversal records a
# concept mapping; where the shapes disagree at all, it fails outright.
#
# SCOPE — the `answer-justifier` codelet (justify.ss 20-180) is NOT here. It
# needs `report-new-answer` (answers.ss step C), `clamp-rules` →
# `make-clamp-event` (trace.ss slice C), `monitor-new-rules` (trace.ss slice D)
# and the answer string that only justify mode builds. What IS here is
# everything that codelet reasons WITH, which is self-contained and testable
# on its own: the traversal, the two procs that ride it, rule unification, the
# unifying slippages, and the theme pattern a unification asks to be clamped.
#
# `compare_rule_clause_lists` and `traverse_rule_clauses` were ported ahead of
# this file with `memory.ss`, whose distance metric was their only caller then;
# they move here, to the file they came from, now that justify.ss has its own
# use for them. `traverse_rule_clauses` gains the `proc` argument the Scheme
# always had — memory needs `rule-clause-comparison-proc`, unification needs
# `concept-mapping-proc`.

# --- walking two rules in parallel ------------------------------------------

"""`(traverse-rule-clauses clauses1 clauses2 fail proc)` — walk two rule-clause
trees together, handing each pair of leaves to `proc`, and fail outright if
their shapes ever disagree.

`proc` pushes onto `results` and returns false to fail. Returns `nothing` when
the traversal failed.

NB the `'string` special case: a rule that says "the string" and one that says
"the whole group" are talking about the same thing.

`must_not_fail` is the Scheme's `fail = #f`, which `get-unifying-slippages`
passes because it assumes the rules unify. Calling it there would apply `#f`
as a procedure and crash, so this raises rather than quietly returning."""
function traverse_rule_clauses(clauses1, clauses2, net::Slipnet, proc;
                               must_not_fail::Bool = false)
    results = Any[]
    failed = false
    fail!() = (failed = true; nothing)
    function walk(x1, x2)
        failed && return
        empty1 = x1 isa AbstractVector && isempty(x1)
        empty2 = x2 isa AbstractVector && isempty(x2)
        (empty1 && empty2) && return
        (empty1 || empty2) && (fail!(); return)
        if x1 isa AbstractVector && x2 isa AbstractVector
            # The Scheme walks the REST first, then the head, so the results
            # list comes out in order.
            walk(x1[2:end], x2[2:end])
            walk(x1[1], x2[1])
            return
        end
        (x1 isa AbstractVector || x2 isa AbstractVector) && (fail!(); return)
        if x1 isa Symbol && x2 isa Symbol
            x1 === x2 || fail!()
            return
        end
        x1 === :string && (x2 === net[:plato_group] || fail!(); return)
        x2 === :string && (x1 === net[:plato_group] || fail!(); return)
        (x1 isa Symbol || x2 isa Symbol) && (fail!(); return)
        proc(x1, x2, results) || fail!()
        return
    end
    walk(rule_clauses_as_lists(clauses1, net), rule_clauses_as_lists(clauses2, net))
    if failed
        must_not_fail && error("traverse_rule_clauses failed where the caller " *
                               "passed fail = #f; the rules do not unify")
        return nothing
    end
    return results
end

"""The rule clauses as the nested lists the Scheme walks, so the traversal can
compare their shapes as well as their contents."""
function rule_clauses_as_lists(clauses, net::Slipnet)
    out = Any[]
    for rc in clauses
        if is_verbatim_clause(rc)
            push!(out, Any[:verbatim, Any[rc.letter_categories...]])
        elseif is_intrinsic_clause(rc)
            push!(out, Any[:intrinsic,
                           Any[Any[od.object_type, od.description_type, od.descriptor]
                               for od in rc.object_descriptions],
                           Any[Any[c.scope, c.dimension, c.descriptor]
                               for c in rc.changes]])
        else
            push!(out, Any[:extrinsic,
                           Any[Any[od.object_type, od.description_type, od.descriptor]
                               for od in rc.object_descriptions],
                           Any[rc.dimensions...]])
        end
    end
    return out
end

# --- the two procs that ride the traversal ----------------------------------

"""`(rule-clause-comparison-proc n1 n2 fail results)` — collect the pairs where
two rules differ. Never fails: any two slipnodes are comparable."""
function rule_clause_comparison_proc(n1, n2, results)
    n1 === n2 || pushfirst!(results, Any[n1, n2])
    return true
end

"""`(concept-mapping-proc n1 n2 fail results)` — the unifying proc. Two nodes
must be identical or slip-linked, or the rules do not unify at all. A node with
no category (the relations `identity`, `opposite` and friends) is accepted but
contributes no mapping, since there is nothing to slip along."""
function concept_mapping_proc(net::Slipnet)
    return function (n1, n2, results)
        (n1 !== n2 && !slip_linked(n1, n2)) && return false
        category = get_category(n1)
        category === nothing && return true
        pushfirst!(results, make_concept_mapping(net, nothing, category::Node, n1,
                                                 nothing, category::Node, n2))
        return true
    end
end

# --- comparing two rules (memory.ss's caller) -------------------------------

"""`(compare-rule-clause-lists rc-list1 rc-list2)` — the pairs of slipnodes at
which two rules differ, or `nothing` when they differ so much that no
correspondence can be made at all."""
function compare_rule_clause_lists(rc_list1::Vector{RuleClause},
                                   rc_list2::Vector{RuleClause}, net::Slipnet)
    if verbatim_rule_clause_list(rc_list1) && verbatim_rule_clause_list(rc_list1)
        # NB: the Scheme tests rc-list1 TWICE — rc-list2 is never looked at.
        return rule_clause_lists_equal(rc_list1, rc_list2, net) ? Any[] : nothing
    end
    return traverse_rule_clauses(rc_list1, rc_list2, net, rule_clause_comparison_proc)
end

"""`(verbatim-rule-clause-list? rc-list)`."""
verbatim_rule_clause_list(rc_list) =
    length(rc_list) == 1 && is_verbatim_clause(rc_list[1])

# --- unifying two rules -----------------------------------------------------

"""`(remove-whole/single-concept-mappings concept-mappings)`.

single=>whole, whole=>single, single=>single and whole=>whole mappings are
dropped, because keeping them would clamp the StrPos:diff theme and only
confuse the program.

NB: the Scheme is `(remq (select pred? cms) cms)` — `select` returns the FIRST
match and `remq` removes only that one object, so a second whole/single mapping
SURVIVES. That is faithfully reproduced here, quirk included. (When nothing
matches, `select` gives `#f` and `remq` removes nothing.)"""
function remove_whole_single_concept_mappings(cms::Vector{ConceptMapping},
                                              net::Slipnet)
    idx = findfirst(cm -> is_cm_type(cm, net[:plato_string_position_category]) &&
                          (cm.descriptor1 === net[:plato_single] ||
                           cm.descriptor1 === net[:plato_whole]),
                    cms)
    idx === nothing && return cms
    return ConceptMapping[cm for cm in cms if cm !== cms[idx]]
end

"""`(unify-rules from-rule to-rule)` — the theme pattern that holds when the two
rules are read as the same idea, or `nothing` when they cannot be unified. A
verbatim rule says nothing general, so it unifies with nothing."""
function unify_rules(from_rule::Rule, to_rule::Rule, net::Slipnet)
    (is_verbatim_rule(from_rule) || is_verbatim_rule(to_rule)) && return nothing
    cms = traverse_rule_clauses(from_rule.rule_clauses, to_rule.rule_clauses, net,
                                concept_mapping_proc(net))
    cms === nothing && return nothing
    kept = remove_whole_single_concept_mappings(ConceptMapping[cms...], net)
    return Any[:vertical_bridge, Any[Any[cm_type(cm), cm.label] for cm in kept]...]
end

"""`(get-unifying-slippages from-rule to-rule)` — just the slippages of that
unification, deduplicated. Which slippages come back depends on the DIRECTION
of translation, and the function assumes the rules can be unified at all."""
function get_unifying_slippages(from_rule::Rule, to_rule::Rule, net::Slipnet)
    cms = traverse_rule_clauses(from_rule.rule_clauses, to_rule.rule_clauses, net,
                                concept_mapping_proc(net); must_not_fail = true)
    slippages = ConceptMapping[cm for cm in cms if is_slippage(cm)]
    return remove_duplicate_cms(remove_whole_single_concept_mappings(slippages, net))
end

# --- the pattern a unification asks to be clamped ---------------------------

"""`(retention-probability pattern-entries)` — how likely an entry is to survive
into the clamped pattern. String-position always survives; otherwise deep
concepts survive more often than shallow ones, and an identity relation is
worth half as much as any other, being the least informative thing a theme can
say."""
function retention_probability(entry, net::Slipnet)
    entry[1] === net[:plato_string_position_category] && return 1
    return pct((entry[1]::Node).conceptual_depth) *
           pct(entry[2] === net[:plato_identity] ? 50 : 100)
end

"""`(add-direction-entry pattern-entries)` — heuristic (1): opposite
string-position and opposite direction are closely related ideas, so a
StrPos entry with a relation drags a matching Dir entry in behind it."""
function add_direction_entry(pattern_entries, net::Slipnet)
    strpos_idx = findfirst(e -> e[1] === net[:plato_string_position_category],
                           pattern_entries)
    dir_idx = findfirst(e -> e[1] === net[:plato_direction_category], pattern_entries)
    strpos_idx === nothing && return pattern_entries
    pattern_entries[strpos_idx][2] === nothing && return pattern_entries
    dir_idx === nothing || return pattern_entries
    return Any[Any[net[:plato_direction_category], pattern_entries[strpos_idx][2]],
               pattern_entries...]
end

"""`(replace-bond-category-entry pattern-entries)` — heuristic (2): bond-category
themes barely influence the bridges `thematic-bridge-scout` builds, so a
BondCtgy entry becomes the matching GroupCtgy entry, or is dropped when a
GroupCtgy entry is already there."""
function replace_bond_category_entry(pattern_entries, net::Slipnet)
    bond_idx = findfirst(e -> e[1] === net[:plato_bond_category], pattern_entries)
    bond_idx === nothing && return pattern_entries
    group_idx = findfirst(e -> e[1] === net[:plato_group_category], pattern_entries)
    bond_entry = pattern_entries[bond_idx]
    without = Any[e for e in pattern_entries if e !== bond_entry]
    group_idx === nothing || return without
    return Any[Any[net[:plato_group_category], bond_entry[2]], without...]
end

"""`(get-vertical-theme-pattern-to-clamp unifying-pattern)` — thin the unifying
pattern down to the entries worth clamping, apply the two heuristics, and fall
back on the whole pattern if thinning left nothing.

The filter draws one random number per entry, in order.

NB the Scheme's `(if (exists? final-theme-pattern) (vprintf "None.~n"))` prints
"None." when the pattern DOES exist — inverted, but it is verbose output only
and changes no behaviour, so it is left alone rather than fixed here."""
function get_vertical_theme_pattern_to_clamp(unifying_pattern, rng::PyRandom,
                                             net::Slipnet)
    theme_type = unifying_pattern[1]
    pattern_entries = entries(unifying_pattern)
    kept = Any[e for e in pattern_entries if prob(rng, retention_probability(e, net))]
    final_entries = add_direction_entry(replace_bond_category_entry(kept, net), net)
    isempty(final_entries) && return unifying_pattern
    return Any[theme_type, final_entries...]
end
