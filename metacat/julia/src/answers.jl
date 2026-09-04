# Ported from the Rule Translation section of Metacat's answers.ss (1196-1558).
#
# A rule says how the initial string changed into the modified one. To answer
# the problem, that rule has to be re-read in the target string's terms: "the
# rightmost letter becomes its successor" applied to `xyz` may have to become
# "the LEFTMOST letter becomes its PREDECESSOR" if the vertical bridges say
# left and right have swapped. Translation is what performs that rewrite.
#
# It works by pushing every descriptor mentioned in the rule through the
# SLIPPAGES carried by the vertical bridges under the objects the rule refers
# to. Two things make it more than a substitution:
#
#   - it is STOCHASTIC. Which applicable slippages actually get used is decided
#     by `apply_slippages!`, and a whole dimension may be dropped at 0.4 per
#     dimension in `translate_rule_clause`. Translating the same rule twice can
#     give different answers, which is the point: it is a perceptual act, not a
#     mechanical one.
#   - a slippage that does not match a descriptor directly can still drag it
#     along a lateral sliplink labelled the same way -- a COATTAIL slippage.
#     `a => b` under a `successor` label lets `c` slide to `d` on its coattails.
#
# Everything applied is recorded in a `SlippageLog`, which is what the
# commentary and the graphics later read to explain the answer.
#
# Not ported here, with the pieces they belong to:
#   - the translated STRING and its bridges (answers.ss 1035-1195), which need
#     `instantiate-as-letter`/`instantiate-as-group` from images.ss;
#   - `answer-finder` and the commentary (20-1035);
#   - the log's graphics methods (`get-slippage-to-highlight` is ported, since
#     it is pure bookkeeping, but the colour methods are not).

"""Raised where the Scheme calls `(fail)` — it escapes to the
`continuation-point*` at the top of `translate`, and the whole translation
comes back `#f`."""
struct TranslationFailed <: Exception end

# --- the slippage log -------------------------------------------------------

"""`(make-slippage-log rule-type)` — the record of which slippages a
translation actually used, and which of those were dragged in on another's
coattails."""
mutable struct SlippageLog
    rule_type::Symbol                    # :top | :bottom
    directly_applied_slippages::Vector{ConceptMapping}
    """`((<coattail-slippage> <inducing-slippage>) ...)`."""
    coattail_slippage_table::Vector{Tuple{ConceptMapping,ConceptMapping}}
    slippage_bridges::Vector{Bridge}
end

make_slippage_log(rule_type::Symbol) =
    SlippageLog(rule_type, ConceptMapping[],
                Tuple{ConceptMapping,ConceptMapping}[], Bridge[])

translation_direction_of(log::SlippageLog) =
    log.rule_type === :top ? :top_to_bottom : :bottom_to_top

get_directly_applied_slippages(log::SlippageLog) = log.directly_applied_slippages
get_coattail_slippages(log::SlippageLog) = [e[1] for e in log.coattail_slippage_table]
get_coattail_inducing_slippages(log::SlippageLog) =
    [e[2] for e in log.coattail_slippage_table]

"""`(get-applied-slippages)`. NB: `remq-duplicates` keeps the LAST of each
duplicate group."""
get_applied_slippages(log::SlippageLog) =
    remq_duplicates(vcat(log.directly_applied_slippages,
                         get_coattail_inducing_slippages(log)))

coattail_inducing_slippage(log::SlippageLog, slippage::ConceptMapping) =
    any(e -> e[2] === slippage, log.coattail_slippage_table)

get_slippage_bridges(log::SlippageLog) = remq_duplicates(log.slippage_bridges)

"""`(get-bridge slippage)` — the vertical bridge a slippage came from."""
function get_bridge(log::SlippageLog, slippage::ConceptMapping)
    i = findfirst(b -> any(s -> s === slippage, get_slippages(b)),
                  log.slippage_bridges)
    return i === nothing ? nothing : log.slippage_bridges[i]
end

"""`(get-slippage-to-highlight slippage)` — a symmetric slippage is displayed
through its non-symmetric twin."""
function get_slippage_to_highlight(log::SlippageLog, slippage::ConceptMapping)
    bridge = get_bridge(log, slippage)
    bridge === nothing && return nothing
    non_symmetric = get_non_symmetric_slippages(bridge)
    any(s -> s === slippage, non_symmetric) && return slippage
    i = findfirst(s -> cm_symmetric(s, slippage), non_symmetric)
    return i === nothing ? nothing : non_symmetric[i]
end

"""`(applied slippage)`. NB: both lists are CONSed, so they end up in reverse
order of application."""
function log_applied!(log::SlippageLog, slippage::ConceptMapping)
    pushfirst!(log.directly_applied_slippages, slippage)
    bridge = (slippage.object1::WSObject).vertical_bridge
    bridge === nothing || pushfirst!(log.slippage_bridges, bridge::Bridge)
    return log
end

"""`(coattail node1 label node2 inducing-slippage)` — records a slippage that
was not in any bridge but was dragged along a sliplink by one that was. The
CM it builds is marked with the `:coattail` symbol where an object would go."""
function log_coattail!(log::SlippageLog, node1::Node, node2::Node,
                       inducing_slippage::ConceptMapping, net::Slipnet)
    category = get_category(node1)::Node
    coattail_slippage = make_concept_mapping(net, :coattail, category, node1,
                                             :coattail, category, node2)
    pushfirst!(log.coattail_slippage_table, (coattail_slippage, inducing_slippage))
    bridge = (inducing_slippage.object1::WSObject).vertical_bridge
    bridge === nothing || pushfirst!(log.slippage_bridges, bridge::Bridge)
    return log
end

# --- pushing a descriptor through the slippages -----------------------------

"""`(coattail-slippage-probability ...)` — just the sliplink's association."""
coattail_slippage_probability(sliplink::Sliplink) =
    pct(link_degree_of_assoc(sliplink))

"""`(apply-slippages slippages sliplog)` on a slipnode: walk the applicable
slippages in order and return what this node becomes.

Three outcomes per slippage, in the Scheme's order: it maps this very node, so
take its target; it cannot apply at all, so move on; or it MIGHT drag this node
along a lateral sliplink labelled the same way, which is decided by a draw.

NB: the draw happens only in that third branch, so the number of random numbers
consumed depends on the descriptors, not just on the slippage list."""
function apply_slippages!(rng::PyRandom, node::Node,
                          slippages::AbstractVector{ConceptMapping},
                          log::SlippageLog, net::Slipnet)
    category = get_category(node)
    for slippage in slippages
        if slippage.descriptor1 === node
            log_applied!(log, slippage)
            return slippage.descriptor2
        end
        # Otherwise see if a coattail slippage can be made.
        label = slippage.label
        # A slippage with no label, or one already about this node's own
        # dimension, cannot drag it anywhere.
        (label === nothing || (category !== nothing &&
                               is_cm_type(slippage, category::Node))) && continue
        j = findfirst(l -> l.label_node === label, node.lateral_sliplinks)
        # NB: `(and (exists? sliplink) (prob? ...))` short-circuits, so a
        # missing sliplink consumes NO random number.
        j === nothing && continue
        prob(rng, coattail_slippage_probability(node.lateral_sliplinks[j])) || continue
        node2 = get_related_node(node, label::Node, net[:plato_identity])
        # The Scheme does not test this: it logs the coattail and returns
        # whatever `get-related-node` gave, `#f` included. A sliplink labelled
        # `label` leaves `node`, so the related node is always found; raise
        # rather than quietly taking a different branch if that ever fails.
        node2 === nothing &&
            error("coattail slippage: no $(label.lowercase_name) node from " *
                  "$(node.lowercase_name)")
        log_coattail!(log, node, node2::Node, slippage, net)
        return node2::Node
    end
    return node
end

apply_to_change(rng::PyRandom, change::Change,
                slippages::AbstractVector{ConceptMapping}, log::SlippageLog,
                net::Slipnet) =
    Change(change.scope,
           apply_slippages!(rng, change.dimension, slippages, log, net),
           apply_slippages!(rng, change.descriptor, slippages, log, net))

apply_to_dimension(rng::PyRandom, dimension::Node,
                   slippages::AbstractVector{ConceptMapping}, log::SlippageLog,
                   net::Slipnet) =
    apply_slippages!(rng, dimension, slippages, log, net)

"""`(apply-to-object-description ...)`. The `'string` object type is a symbol
rather than a node, so it passes through untouched."""
apply_to_object_description(rng::PyRandom, od::ObjectDescription,
                            slippages::AbstractVector{ConceptMapping},
                            log::SlippageLog, net::Slipnet) =
    ObjectDescription(od.object_type === :string ? od.object_type :
                      apply_slippages!(rng, od.object_type::Node, slippages, log, net),
                      apply_slippages!(rng, od.description_type, slippages, log, net),
                      apply_slippages!(rng, od.descriptor, slippages, log, net))

# --- validity ---------------------------------------------------------------

"""`(valid-object-description? od)` — the descriptor must actually belong to
the dimension the description claims."""
valid_object_description(od::ObjectDescription) =
    get_category(od.descriptor) === od.description_type

"""`(valid-change? change)`."""
valid_change(change::Change, net::Slipnet) =
    platonic_relation(change.descriptor, net) ||
    get_category(change.descriptor) === change.dimension

"""`(valid-rule-clause? rc)`. An extrinsic clause naming a single LETTER is
rejected: "the letter changes its LetterCtgy" says nothing."""
function valid_rule_clause(rc::RuleClause, net::Slipnet)
    is_verbatim_clause(rc) && return true
    if is_extrinsic_clause(rc)
        all(valid_object_description, rc.object_descriptions) &&
            (length(rc.object_descriptions) > 1 ||
             rc.object_descriptions[1].object_type !== net[:plato_letter]) &&
            return true
    end
    return is_intrinsic_clause(rc) &&
           valid_object_description(rc.object_descriptions[1]) &&
           all(c -> valid_change(c, net), rc.changes)
end

# --- redundant ObjCtgy ------------------------------------------------------

"""`(remove-redundant-ObjCtgy-change rule-clause)`.

For an intrinsic clause this drops the `(self <ObjCtgy> <group>)` change when
the object description already says "group" -- it is not a change at all. For
an extrinsic clause over several objects of the same type, the ObjCtgy
dimension says nothing either. Returns `nothing` when removing it would leave
the clause empty.

NB: nothing in Metacat calls this. It is ported because it sits in the section
and is well-defined, but its `record-case` has only extrinsic and intrinsic
arms, so a VERBATIM clause returns void there — passing one is a caller error
in the Scheme too, and the probe does not."""
function remove_redundant_objctgy_change(rc::RuleClause, net::Slipnet)
    if is_extrinsic_clause(rc)
        if any(d -> d === net[:plato_object_category], rc.dimensions) &&
           length(rc.object_descriptions) != 1 &&
           all_same(Any[od.object_type for od in rc.object_descriptions])
            new_dimensions = Node[d for d in rc.dimensions
                                  if d !== net[:plato_object_category]]
            isempty(new_dimensions) && return nothing
            return extrinsic_clause(rc.object_descriptions, new_dimensions)
        end
        return rc
    end
    if is_intrinsic_clause(rc)
        change = select_change(net[:plato_object_category], :self, rc.changes)
        object_type = rc.object_descriptions[1].object_type
        if change !== nothing && (change::Change).descriptor === object_type
            new_changes = Change[c for c in rc.changes if c !== change]
            isempty(new_changes) && return nothing
            return intrinsic_clause(rc.object_descriptions[1], new_changes)
        end
    end
    return rc
end

# --- whole-string object descriptions ---------------------------------------

"""`(whole-string-object-description? od)`. The `'string` test is redundant
with the `plato-whole` one, and is kept for the same reason the Scheme keeps
it."""
whole_string_object_description(od::ObjectDescription, net::Slipnet) =
    od.object_type === :string || od.descriptor === net[:plato_whole]

"""`(translate-whole-string-object-description od to-string)` — "the whole
string" becomes "the whole group" when the target string has one."""
translate_whole_string_object_description(to_string::WorkspaceString, net::Slipnet) =
    ObjectDescription(spanning_group_exists(to_string) ? net[:plato_group] : :string,
                      net[:plato_string_position_category], net[:plato_whole])

# --- translating one object description --------------------------------------

"""`(translate-object-description ...)`, returning
`(translated_od, applicable_slippages, enclosing_bond_slippages)`.

`applicable_slippages` are the ones that COULD apply; which actually do is the
probabilistic decision inside `apply_slippages!`, recorded in the log.

Throws `TranslationFailed` where the Scheme calls `(fail)`, which is a
`continuation-point*` escape all the way out of `translate`."""
function translate_object_description(rng::PyRandom, od::ObjectDescription,
                                      from_string::WorkspaceString,
                                      to_string::WorkspaceString,
                                      log::SlippageLog, net::Slipnet)
    from_objects = get_object_description_ref_objects(from_string, od, net)
    isempty(from_objects) && throw(TranslationFailed())

    vertical_bridges = Any[o isa WorkspaceString ? nothing : o.vertical_bridge
                           for o in from_objects]
    if any(b -> b === nothing, vertical_bridges)
        # Nothing to slide along: keep the description, except that "the whole
        # string" has to be re-read for the string it is moving to.
        translated = whole_string_object_description(od, net) ?
                     translate_whole_string_object_description(to_string, net) : od
        return (translated, ConceptMapping[], ConceptMapping[])
    end
    bridges = Bridge[b::Bridge for b in vertical_bridges]

    all_enclosing_groups1 = Any[enclosing_group1(b) for b in bridges]
    all_enclosing_groups2 = Any[enclosing_group2(b) for b in bridges]
    (all_same(all_enclosing_groups1) && all_same(all_enclosing_groups2)) ||
        throw(TranslationFailed())

    all_bridge_slippages = ConceptMapping[]
    for b in bridges
        append!(all_bridge_slippages, get_slippages(b))
    end
    # Going DOWN (initial->target) the symmetric slippages are the redundant
    # ones; coming back UP it is the non-symmetric ones.
    symmetric_bridge_slippages = ConceptMapping[]
    for b in bridges
        append!(symmetric_bridge_slippages,
                top_string(from_string) ? b.symmetric_slippages :
                                          get_non_symmetric_slippages(b))
    end
    applicable = ConceptMapping[s for s in all_bridge_slippages
                                if !(any(x -> x === s, symmetric_bridge_slippages) &&
                                     s.label !== net[:plato_opposite])]

    translated = apply_to_object_description(rng, od, applicable, log, net)

    enclosing_group_1 = all_enclosing_groups1[1]
    enclosing_group_2 = all_enclosing_groups2[1]
    enclosing_bridge = nothing
    if enclosing_group_1 !== nothing && enclosing_group_2 !== nothing &&
       bridge_between(:vertical, enclosing_group_1, enclosing_group_2)
        enclosing_bridge = (enclosing_group_1::WSObject).vertical_bridge
    end
    enclosing_bond_slippages = enclosing_bridge === nothing ? ConceptMapping[] :
                               get_bond_slippages(enclosing_bridge::Bridge, net)

    return (translated, applicable, enclosing_bond_slippages)
end

# --- translating one clause --------------------------------------------------

"""`(translate-rule-clause from-string to-string slippage-log fail)`, returning
`(translated_clause, all_applicable_slippages)`.

NB the 0.4 draw: each DISTINCT dimension among the possible transform slippages
gets one draw, and a dimension that comes up is dropped from the translation
entirely. That is what lets a translation be partial."""
function translate_rule_clause(rng::PyRandom, rc::RuleClause,
                               from_string::WorkspaceString,
                               to_string::WorkspaceString,
                               log::SlippageLog, net::Slipnet)
    is_verbatim_clause(rc) && return (rc, ConceptMapping[])

    results = [translate_object_description(rng, od, from_string, to_string, log, net)
               for od in rc.object_descriptions]
    translated_object_descriptions = ObjectDescription[r[1] for r in results]
    applicable_object_description_slippages = ConceptMapping[]
    for r in results
        append!(applicable_object_description_slippages, r[2])
    end
    enclosing_slippages = ConceptMapping[]
    for r in results
        append!(enclosing_slippages, r[3])
    end
    enclosing_slippages = remq_duplicates(enclosing_slippages)

    possible_transform_slippages = vcat(applicable_object_description_slippages,
                                        enclosing_slippages)
    ignored_dimensions = Node[d for d in
                              remq_duplicates(Node[s.description_type1
                                                   for s in possible_transform_slippages])
                              if prob(rng, 0.4)]
    applicable_transform_slippages =
        ConceptMapping[s for s in possible_transform_slippages
                       if !any(d -> d === s.description_type1, ignored_dimensions)]

    translated = if is_extrinsic_clause(rc)
        extrinsic_clause(translated_object_descriptions,
                         Node[apply_to_dimension(rng, d, applicable_transform_slippages,
                                                 log, net)
                              for d in rc.dimensions])
    else
        RuleClause(:intrinsic, translated_object_descriptions,
                   Change[apply_to_change(rng, c, applicable_transform_slippages,
                                          log, net)
                          for c in rc.changes],
                   Node[], Node[])
    end

    return (translated, vcat(applicable_object_description_slippages,
                             applicable_transform_slippages))
end

# --- translating a whole rule ------------------------------------------------

"""What `translate` hands back when it succeeds. The Scheme returns a six-element
list; naming the fields keeps the call sites readable."""
struct Translation
    translated_rule::Rule
    supporting_vertical_bridges::Vector{Bridge}
    slippage_log::SlippageLog
    vertical_mapping_supporting_groups::Vector{WSObject}
    from_string_ref_objects::Vector{Any}
    to_string_ref_objects::Vector{Any}
end

"""`(translate rule)` — re-read a rule in the other string's terms, or
`nothing` if it cannot be.

Two ways to fail: an object description that cannot be resolved or whose
objects disagree about their enclosing groups (the `(fail)` escape), and a
translated clause that comes out invalid."""
function translate(rng::PyRandom, rule::Rule, initial_string::WorkspaceString,
                   target_string::WorkspaceString, net::Slipnet)
    rule_type = rule.rule_type
    from_string = rule_type === :top ? initial_string : target_string
    to_string = rule_type === :top ? target_string : initial_string
    log = make_slippage_log(rule_type)

    results = try
        [translate_rule_clause(rng, rc, from_string, to_string, log, net)
         for rc in rule.rule_clauses]
    catch e
        e isa TranslationFailed || rethrow()
        return nothing
    end
    translated_clauses = RuleClause[r[1] for r in results]
    all(rc -> valid_rule_clause(rc, net), translated_clauses) || return nothing

    # `transcribe-to-english` reads a TOP rule against the initial string and a
    # BOTTOM rule against the target one, so the translated rule transcribes
    # against `to_string`.
    translated_rule = make_rule(rule_type === :top ? :bottom : :top,
                                translated_clauses, to_string, net)

    from_string_ref_objects = Any[o for o in
                                  get_all_reference_objects(from_string, rule, net)
                                  if !(o isa WorkspaceString)]
    to_string_ref_objects = Any[o for o in
                                get_all_reference_objects(to_string, translated_rule, net)
                                if !(o isa WorkspaceString)]

    from_bridges = Bridge[b for b in
                          (o.vertical_bridge for o in from_string_ref_objects)
                          if b !== nothing]
    to_bridges = Bridge[b for b in
                        (o.vertical_bridge for o in to_string_ref_objects)
                        if b !== nothing]
    shared = Bridge[b for b in from_bridges if any(x -> x === b, to_bridges)]
    supporting_vertical_bridges =
        remq_duplicates(vcat(get_slippage_bridges(log), shared))

    groups = WSObject[]
    for b in supporting_vertical_bridges
        append!(groups, get_all_nested_groups(b.object1))
        append!(groups, get_all_nested_groups(b.object2))
    end
    vertical_mapping_supporting_groups = remq_duplicates(groups)

    mark_as_translated!(translated_rule, rule,
                        rule_type === :top ? :top_to_bottom : :bottom_to_top)

    return Translation(translated_rule, supporting_vertical_bridges, log,
                       vertical_mapping_supporting_groups,
                       from_string_ref_objects, to_string_ref_objects)
end
