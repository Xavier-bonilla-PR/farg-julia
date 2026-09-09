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
# The file is in two halves. The first is the unification machinery, which is
# pure structure — it never reads the workspace — and so is testable on its own
# (probe `justify`). The second, at the bottom, is `clamp-rules` and the
# `answer-justifier` codelet, which are justify mode proper and need a running
# model to say anything (probe `justifymode`).
#
# The unification half is: the traversal, the two procs that ride it, the
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

# --- clamping two rules together (justify.ss 162-180) -----------------------

"""`(clamp-rules rules vertical-theme-pattern . concept-patterns)` — the model
deciding to WORK ON a justification it cannot yet see.

A justify clamp says: these two rules ought to be two readings of the same
idea; hold the themes that would make them so, hold the concepts they name, and
push the top-down and thematic codelets, until the workspace either bears that
out or the clamp period runs out. It is the one clamp type built from RULES
rather than from something that went wrong.

NB the ordering comment in the Scheme: the event is added to the trace BEFORE
it is activated, so that the concept-activation events the clamp causes appear
in the trace after the clamp itself rather than before it."""
function clamp_rules!(rules, vertical_theme_pattern, concept_patterns, ctx)
    all_patterns = Any[]
    for r in rules
        push!(all_patterns, (r::Rule).theme_pattern)
    end
    push!(all_patterns, vertical_theme_pattern)
    append!(all_patterns, concept_patterns)
    push!(all_patterns, top_down_codelet_pattern())
    push!(all_patterns, thematic_codelet_pattern())
    clamp_event = make_clamp_event(:justify_clamp, all_patterns, rules, :workspace, ctx)
    tr = ctx.trace::TemporalTrace
    add_event!(tr, clamp_event, ctx)
    activate!(clamp_event, tr, ctx)
    return clamp_event
end

# --- the answer-justifier (justify.ss 20-160) -------------------------------
#
# The codelet justify mode exists for. Where the `answer-finder` asks "what
# answer does this rule give?", the answer-justifier already HAS the answer and
# asks "do the two halves of this analogy say the same thing?".
#
# It picks a supported rule from either half, translates it into the other
# half's terms, and then looks for the rule it should have matched:
#
#   * a rule already in the workspace that EQUALS the translation — the two
#     halves agree, and if that rule is still supported the answer is reported;
#   * no such rule, but the translation WORKS when applied — so it is built,
#     added, and the answer reported through it;
#   * neither — the model cannot see the justification yet, so it CLAMPS the
#     rules it has together and tries to make the workspace produce it.
#
# The last case is the interesting one, and it is why justify mode needs the
# trace: the clamp is an act of self-direction, recorded as an event, and the
# jootser watches for the model doing it over and over.

"""`answer-justifier` — try to justify the answer the run was given."""
function answer_justifier(ctx::MetacatCtx, args::Vector{Any})
    TEMPERATURE[] = ctx.temperature
    net = ctx.net
    mem = ctx.memory
    answer_string = ctx.answer_string::WorkspaceString
    # NB the Scheme binds the three mapping strengths first and never reads
    # them again. They draw nothing, so the only visible difference would be
    # their absence.
    supported = get_all_supported_rules(ctx)
    # `stochastic-pick` on an empty list falls through to `random-pick`, which
    # returns #f WITHOUT drawing; the codelet then fizzles.
    isempty(supported) && return
    chosen_rule = stochastic_pick(ctx.rng, supported,
                                  [(r::Rule).strength for r in supported])
    rule = chosen_rule::Rule
    rule_type = rule.rule_type
    other_rules = get_rules(ctx, rule_type === :top ? :bottom : :top)
    result = translate(ctx.rng, rule, ctx.initial_string, ctx.target_string, net)
    if result !== nothing
        translated_rule = result.translated_rule
        ref_objs1 = rule_type === :top ? result.from_string_ref_objects :
                                         result.to_string_ref_objects
        ref_objs2 = rule_type === :top ? result.to_string_ref_objects :
                                         result.from_string_ref_objects
        i = findfirst(r -> rules_equal(r::Rule, translated_rule, net), other_rules)
        matching_rule = i === nothing ? nothing : other_rules[i]::Rule
        if matching_rule !== nothing
            rule1 = rule_type === :top ? rule : matching_rule::Rule
            rule2 = rule_type === :top ? matching_rule::Rule : rule
            mem !== nothing &&
                answer_present(mem::Memory, answer_string.letter_categories,
                               rule1, rule2, ctx, net) && return
            rule_supported(matching_rule::Rule, ctx) || return report_or_clamp_fizzle(
                ctx, rule, matching_rule::Rule, net)
            all_supporting_groups = remq_duplicates(
                Any[result.vertical_mapping_supporting_groups...,
                    get_rule_supporting_groups(rule1, rule2, ctx, net)...])
            return report_new_answer!(answer_string, rule1, rule2,
                                      result.supporting_vertical_bridges,
                                      all_supporting_groups, ref_objs1, ref_objs2,
                                      result.slippage_log, ConceptMapping[], mem, ctx)
        end
        # No matching rule. The translated rule itself may still work — but only
        # if it refers to something: the `ref-objs1` test rules out a bottom
        # rule that translates to a top rule which works VACUOUSLY, saying
        # nothing about the initial string (the Scheme's example is
        # "xqd -> xqd; mrrjjj -> mrrjjjj", where "increase the length of the j
        # group" becomes "increase the length of the letter j").
        if currently_works(translated_rule, ctx) && !isempty(ref_objs1)
            rule1 = rule_type === :top ? rule : translated_rule
            rule2 = rule_type === :top ? translated_rule : rule
            mem !== nothing &&
                answer_present(mem::Memory, answer_string.letter_categories,
                               rule1, rule2, ctx, net) && return
            set_quality_values!(translated_rule, net)
            # make-translated-string sets the translated rule's supporting
            # bridges and theme pattern, so it has to happen before the answer
            # is reported — or before the rule is clamped.
            make_translated_string(translated_rule,
                                   rule_type === :top ? ctx.target_string :
                                                        ctx.initial_string,
                                   ctx, net)
            add_rule!(ctx, translated_rule)
            ctx.trace === nothing || monitor_new_rules(translated_rule, ctx)
            rule_supported(translated_rule, ctx) || return report_or_clamp_fizzle(
                ctx, rule, translated_rule, net)
            all_supporting_groups = remq_duplicates(
                Any[result.vertical_mapping_supporting_groups...,
                    get_rule_supporting_groups(rule1, rule2, ctx, net)...])
            return report_new_answer!(answer_string, rule1, rule2,
                                      result.supporting_vertical_bridges,
                                      all_supporting_groups, ref_objs1, ref_objs2,
                                      result.slippage_log, ConceptMapping[], mem, ctx)
        end
    end
    # The unification section, reached both when the rule would not translate at
    # all and when the translation did not work.
    isempty(other_rules) && return
    permission_to_clamp(ctx.trace::TemporalTrace, ctx) || return
    strength = rule.strength
    other_weights = [sub_from_100(abs(strength - (r::Rule).strength)) for r in other_rules]
    other_rule = stochastic_pick(ctx.rng, other_rules, other_weights)::Rule
    unifying_theme_pattern = unify_rules(rule, other_rule, net)
    unifying_theme_pattern === nothing && return
    clamp_rules!(Any[rule, other_rule],
                 get_vertical_theme_pattern_to_clamp(unifying_theme_pattern, ctx.rng, net),
                 Any[get_concept_pattern(rule), get_concept_pattern(other_rule)], ctx)
    return
end

"""The two "not currently supported" arms, which are the same: ask the trace for
permission, clamp the two rules with the dominant vertical theme pattern and the
unmatched rule's concepts, and fizzle either way."""
function report_or_clamp_fizzle(ctx::MetacatCtx, chosen_rule::Rule, other::Rule,
                                net::Slipnet)
    permission_to_clamp(ctx.trace::TemporalTrace, ctx) || return
    # NB `get_dominant_theme_pattern` returns only the ENTRIES; the Scheme's
    # `(cons theme-type ...)` is the caller's job here.
    dominant = Any[:vertical_bridge,
                   get_dominant_theme_pattern(ctx.themespace, :vertical_bridge)...]
    clamp_rules!(Any[chosen_rule, other], dominant,
                 Any[get_concept_pattern(other)], ctx)
    return
end

register_codelet_type!(:answer_justifier, answer_justifier)
