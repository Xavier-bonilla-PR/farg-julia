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

# --- the translated string (answers.ss 1035-1195) ---------------------------
#
# Translating a rule says what the answer's RULE is. Building the translated
# string says what the answer LOOKS like: apply the rule to the string, then
# instantiate the resulting image back into real letters and groups.
#
# `process-snag` is deliberately not ported here. It needs `*trace*`,
# `*memory*`, `make-snag-event` and `post-initial-codelets` — trace.ss,
# memory.ss and run.ss — so it belongs with them.

"""`(attach-length-to-appropriate-groups object-transforms)`.

A Length transform means the group's size changed, so the size has to be said
out loud: on the ORIGINAL group when it had no Length description (the change
is what makes the length interesting), otherwise on the instantiated one. A
BondFacet transform onto Length means the group's SUBOBJECTS are now measured
by length, so each of them gets a Length description instead."""
function attach_length_to_appropriate_groups!(object_transforms, net::Slipnet)
    for ot in object_transforms
        object = ot[1]
        transforms = ot[2]
        instantiated = get_instantiated_image_object(object)
        length_transform = assq(net[:plato_length], transforms)
        bond_facet_transform = assq(net[:plato_bond_facet], transforms)
        if instantiated !== nothing && instantiated isa Group
            if length_transform !== nothing
                if object isa Group &&
                   !description_type_present(object, net[:plato_length])
                    attach_length_description!(object::Group, net)
                else
                    attach_length_description!(instantiated::Group, net)
                end
            end
        elseif bond_facet_transform !== nothing &&
               bond_facet_transform[2] === net[:plato_length]
            for sub in get_constituent_objects(instantiated::Group)
                sub isa Group && attach_length_description!(sub::Group, net)
            end
        end
    end
    return object_transforms
end

"""`(assq key alist)` — the first entry whose head is `key`, by identity."""
function assq(key, alist)
    i = findfirst(e -> e[1] === key, alist)
    return i === nothing ? nothing : alist[i]
end

"""`(make-translated-rule-bridges object-transforms string-transform)` — one
horizontal bridge per object that the rule touched, plus one per subobject of
a whole-string transform that the rule did NOT touch, so the whole string is
covered."""
function make_translated_rule_bridges(object_transforms, string_transform, net::Slipnet)
    unmapped_string_subobjects = WSObject[]
    if string_transform !== nothing
        touched = Any[ot[1] for ot in object_transforms]
        for o in get_constituent_objects(string_transform[1])
            any(x -> x === o, touched) || push!(unmapped_string_subobjects, o)
        end
    end
    instantiated_object_transforms =
        [ot for ot in object_transforms
         if get_instantiated_image_object(ot[1]) !== nothing]

    horizontal_bridges = Bridge[]
    for ot in instantiated_object_transforms
        push!(horizontal_bridges,
              make_bridge(:horizontal, ot[1],
                          get_instantiated_image_object(ot[1])::WSObject,
                          ConceptMapping[], net))
    end
    for sub in unmapped_string_subobjects
        push!(horizontal_bridges,
              make_bridge(:horizontal, sub,
                          get_instantiated_image_object(sub)::WSObject,
                          ConceptMapping[], net))
    end
    foreach(mark_as_translated_rule_bridge!, horizontal_bridges)
    return horizontal_bridges
end

"""`(irrelevant-translated-string-group? horizontal-bridges)`.

Example: swapping `m` and `[jjj]` in `[m][rr][jjj]` gives `[[jjj]][rr]m`, whose
outer `[[jjj]]` group is an artefact of the swap and belongs to nothing. A
group nothing maps to is irrelevant and gets deleted."""
function irrelevant_translated_string_groups(horizontal_bridges::Vector{Bridge})
    mapped = Any[b.object2 for b in horizontal_bridges]
    mapped_nested_groups = WSObject[]
    for o in mapped
        o isa Group && append!(mapped_nested_groups, get_all_nested_groups(o))
    end
    return g -> !any(x -> x === g, mapped_nested_groups)
end

"""`(make-translated-string rule string1)` — apply the rule to a string and
build the string it turns into, as real letters and groups.

The two walks are the whole construction: `leaf_walk` makes the letters left to
right, then `postorder_interior_walk` makes each group once the objects under
it exist."""
function make_translated_string(rule::Rule, string1::WorkspaceString, ctx,
                                net::Slipnet)
    result = apply_rule(rule, string1, net, ignore_snag)
    letter_categories = generate_image_letters(string1)
    string_type = string1.string_type === :initial ? :modified : :answer
    string2 = new_workspace_string(net, string_type, letter_categories)
    object_transforms = [r for r in result if !(r[1] isa WorkspaceString)]
    string_transform_index = findfirst(r -> r[1] isa WorkspaceString, result)
    string_transform = string_transform_index === nothing ? nothing :
                       result[string_transform_index]
    image1 = get_image(string1)

    mark_string_as_translated!(string2)
    position = Ref(0)
    do_walk(leaf_walk, im -> begin
                instantiate_as_letter!(im, string2, position[], net)
                position[] += 1
            end, image1)
    set_letter_list!(string2)
    do_walk(postorder_interior_walk,
            im -> instantiate_as_group!(im, string2, net), image1)

    attach_length_to_appropriate_groups!(object_transforms, net)
    horizontal_bridges = make_translated_rule_bridges(object_transforms,
                                                      string_transform, net)
    irrelevant = irrelevant_translated_string_groups(horizontal_bridges)
    for group in [g for g in string2.groups if irrelevant(g)]
        remove_group!(string2, group::Group)
    end
    set_translated_rule_information!(rule, horizontal_bridges, ctx, net)
    return string2
end

"""`(get-rule-supporting-groups top-rule bottom-rule)` — every group the two
rules rest on, whether as a reference object or through a supporting bridge."""
function get_rule_supporting_groups(top_rule::Rule, bottom_rule::Rule, ctx,
                                    net::Slipnet)
    supporting_horizontal_bridges =
        vcat(top_rule.supporting_horizontal_bridges,
             bottom_rule.supporting_horizontal_bridges)
    top_rule_ref_objects = get_all_reference_objects(ctx.initial_string, top_rule, net)
    bottom_rule_ref_objects = get_all_reference_objects(ctx.target_string,
                                                        bottom_rule, net)
    all_rule_reference_groups = Any[o for o in vcat(top_rule_ref_objects,
                                                    bottom_rule_ref_objects)
                                    if o isa Group]
    groups = Any[all_rule_reference_groups...]
    for b in supporting_horizontal_bridges
        append!(groups, get_all_nested_groups(b.object1))
        append!(groups, get_all_nested_groups(b.object2))
    end
    return remq_duplicates(groups)
end

# --- answers.ss (C): what an answer event is abstracted FROM -----------------
#
# The helpers below live in answers.ss's commentary half (108-265), but nothing
# in the prose needs them — the MEMORY does, to turn an answer or snag event
# into a description it can compare against what it already remembers. They
# come here with step (C) rather than with the commentary.

"""`(answer-quality-phrase quality)` — how Metacat describes an answer's quality
to itself, in the comment it writes when it finds one."""
function answer_quality_phrase(quality)
    quality < 50 && return "really terrible"
    quality < 60 && return "pretty bad"
    quality < 70 && return "pretty dumb"
    quality < 75 && return "pretty mediocre"
    quality < 80 && return "halfway decent"
    quality < 85 && return "pretty good"
    quality < 90 && return "very good"
    return "great"
end

"""`(pick-most-recent-event events)` — the youngest of a cluster, by age."""
pick_most_recent_event(events, ctx) =
    select_extreme(minimum, e -> get_age(e, ctx), events)

"""`(most-recent-group-and-concept-mapping-events)` — one event per distinct
group or concept mapping that is still relevant to an answer description, each
the most recent of its equivalents. A structure built, broken and rebuilt shows
up once, at its latest moment."""
function most_recent_group_and_concept_mapping_events(ctx)
    tr = ctx.trace
    tr === nothing && return Any[]
    relevant = Any[]
    for e in get_all_events(tr::TemporalTrace)
        t = get_event_type(e)
        (t === :concept_mapping || t === :group) || continue
        ok = t === :group ? relevant_for_answer_description(e::GroupEvent) :
                            relevant_for_answer_description(e::ConceptMappingEvent, ctx)
        ok && push!(relevant, e)
    end
    clusters = partition_pred((e1, e2) -> trace_events_equal(e1, e2, ctx), relevant)
    return Any[pick_most_recent_event(c, ctx) for c in clusters]
end

"""`equal?` across the two event types this clustering mixes."""
function trace_events_equal(e1, e2, ctx)
    e1 isa GroupEvent && return events_equal(e1, e2)
    e1 isa ConceptMappingEvent && return events_equal(e1, e2, ctx.net)
    return false
end

"""`(get-entry dimension pattern/s)` — `assq` over one pattern's entries, or
over the entries of a LIST of patterns."""
function get_entry(dimension, patterns)
    isempty(patterns) && return nothing
    entries_of = patterns[1] isa Symbol ? patterns[2:end] :
                 Any[e for p in patterns for e in p[2:end]]
    i = findfirst(e -> e[1] === dimension, entries_of)
    return i === nothing ? nothing : entries_of[i]
end

in_patterns(dimension, patterns) = get_entry(dimension, patterns) !== nothing

"""`(whole-string-identity-concept-mapping? cm-type initial-group target-group)`
— whether the spanning vertical bridge maps this dimension to ITSELF. Used to
notice a theme that holds trivially between the two whole strings."""
function whole_string_identity_concept_mapping(dimension, initial_group,
                                               target_group, net)
    (initial_group === nothing || target_group === nothing) && return false
    bridge = get_bridge_between(:vertical, initial_group, target_group)
    bridge === nothing && return false
    # NB `get-concept-mapping` searches ALL the concept mappings, bond ones
    # included, not just the bridge's own list.
    i = findfirst(cm -> cm_type(cm) === dimension,
                  (bridge::Bridge).all_concept_mappings)
    i === nothing && return false
    return (bridge::Bridge).all_concept_mappings[i].identity
end

"""`(abstract-answer-description-theme-pattern important-events)` — the vertical
theme pattern an answer is really about.

Only five dimensions contribute. For each, the concept-mapping events of the
run are consulted first; string-position gets three fallbacks (agree with
Direction if there is one, else the dominant StringPos theme, else identity —
a string-position theme is ALWAYS included, whatever happens); bond-facet
identity is never included; and anything else is included only when the two
whole strings map it to itself."""
function abstract_answer_description_theme_pattern(important_events, ctx)
    net = ctx.net
    dominant = get_dominant_theme_pattern(ctx.themespace, :vertical_bridge)
    whole_initial = nothing
    whole_target = nothing
    for e in important_events
        e isa GroupEvent || continue
        if is_event_string_type(e, :initial) && whole_initial === nothing
            whole_initial = e
        elseif is_event_string_type(e, :target) && whole_target === nothing
            whole_target = e
        end
    end
    initial_group = whole_initial === nothing ? nothing : get_group(whole_initial)
    target_group = whole_target === nothing ? nothing : get_group(whole_target)
    cm_patterns = Any[get_theme_pattern(e) for e in important_events
                      if e isa ConceptMappingEvent]
    entries_out = Any[]
    for dim in (net[:plato_alphabetic_position_category],
                net[:plato_string_position_category],
                net[:plato_direction_category],
                net[:plato_group_category],
                net[:plato_bond_facet])
        if in_patterns(dim, cm_patterns)
            push!(entries_out, get_entry(dim, cm_patterns))
        elseif dim === net[:plato_string_position_category]
            if in_patterns(net[:plato_direction_category], cm_patterns)
                # StringPos and Direction themes should agree if possible
                push!(entries_out,
                      Any[net[:plato_string_position_category],
                          get_entry(net[:plato_direction_category], cm_patterns)[2]])
            else
                dom = get_entry(net[:plato_string_position_category], Any[dominant])
                push!(entries_out, dom !== nothing ? dom :
                      Any[net[:plato_string_position_category], net[:plato_identity]])
            end
        elseif dim === net[:plato_bond_facet]
            continue  # bond-facet identity themes are never included
        elseif whole_string_identity_concept_mapping(dim, initial_group, target_group,
                                                     net)
            push!(entries_out, Any[dim, net[:plato_identity]])
        end
    end
    return Any[:vertical_bridge, entries_out...]
end

"""`(get-theme-supporting-concept-mappings theme-pattern bridges)` — the
mappings that actually hold the pattern up. A BondCtgy mapping counts for a
GroupCtgy entry with the same relation: bonding a run one way is what makes the
group that way."""
function get_theme_supporting_concept_mappings(theme_pattern, bridges, net::Slipnet)
    all_cms = ConceptMapping[]
    for b in bridges
        append!(all_cms, (b::Bridge).all_concept_mappings)
    end
    kept = remove_whole_single_concept_mappings(all_cms, net)
    pattern_entries = theme_pattern[2:end]
    result = ConceptMapping[]
    for cm in kept
        entry = Any[cm_type(cm), cm.label]
        matches = member_equal(entry, pattern_entries) ||
                  (entry[1] === net[:plato_bond_category] &&
                   member_equal(Any[net[:plato_group_category], entry[2]],
                                pattern_entries))
        matches && push!(result, cm)
    end
    return result
end

"""`(get-unjustified-theme-pattern unjustified-slippages)` — the themes an
answer rests on but could not account for.

A BondFacet theme implies groups, so a group-category and a direction theme are
added alongside it when they are not already there. The BondFacet theme alone
says nothing about WHICH group-category or direction, so identity is the
default in both cases."""
function get_unjustified_theme_pattern(unjustified_slippages, net::Slipnet)
    pattern_entries = Any[Any[cm_type(s), s.label] for s in unjustified_slippages]
    has(dim) = findfirst(e -> e[1] === dim, pattern_entries)
    has(net[:plato_bond_facet]) === nothing &&
        return Any[:vertical_bridge, pattern_entries...]
    gi = has(net[:plato_group_category])
    di = has(net[:plato_direction_category])
    group_entry = gi === nothing ?
        Any[net[:plato_group_category], net[:plato_identity]] : pattern_entries[gi]
    direction_entry = di === nothing ?
        Any[net[:plato_direction_category], net[:plato_identity]] : pattern_entries[di]
    combined = Any[group_entry, direction_entry, pattern_entries...]
    # remove-duplicates is VALUE equality and keeps the LAST of each group
    deduped = Any[x for (i, x) in enumerate(combined)
                  if !any(y -> y == x, combined[(i + 1):end])]
    return Any[:vertical_bridge, deduped...]
end

# --- answers.ss (C): finding an answer and reporting it ---------------------

"""`(suspend)` — the Scheme hands control back to the repl, and the headless
harness redirects that to an escape continuation, so `(suspend)` never returns.
An exception is the Julia equivalent: the run loop catches it."""
struct RunFinished <: Exception
    reason::Symbol            # :answer | :give_up
end

suspend(reason::Symbol = :answer) = throw(RunFinished(reason))

"""`(report-new-answer ...)` — record the answer and END THE RUN.

The comment window is graphics, so the prose Metacat writes about the answer is
not here (it is `answer_quality_phrase` and the commentary of step (D)); what
IS here is the answer event, the memory entry abstracted from it, and the
suspend that stops the run."""
function report_new_answer!(answer_string, top_rule::Rule, bottom_rule::Rule,
                            supporting_vertical_bridges, supporting_groups,
                            top_rule_ref_objects, bottom_rule_ref_objects,
                            slippage_log::SlippageLog, unjustified_slippages,
                            mem, ctx)
    update_everything!(ctx)
    tr = ctx.trace
    if tr !== nothing && (tr::TemporalTrace).within_clamp_period
        undo_last_clamp!(tr::TemporalTrace, ctx)
    end
    answer_event = make_answer_event(ctx.initial_string, ctx.modified_string,
                                     ctx.target_string, answer_string, top_rule,
                                     bottom_rule, supporting_vertical_bridges,
                                     supporting_groups, top_rule_ref_objects,
                                     bottom_rule_ref_objects, slippage_log,
                                     unjustified_slippages, ctx)
    tr === nothing || add_event!(tr::TemporalTrace, answer_event, ctx)
    # Build an abstract characterization of the answer and store it in memory.
    mem === nothing || abstract_answer_description!(answer_event, mem::Memory, ctx)
    suspend(:answer)
end

"""`(process-snag rule translated-rule ...)` — returns the failure ACTION that
`apply-rule` calls when the translated rule cannot be applied.

A snag is not a failure to be swallowed: the model records it, remembers it if
it is new, throws away every proposal it was in the middle of, pins the
temperature at 100 so nothing looks settled, holds the snagged objects in view,
wipes the rack and starts over. That is the impasse the self-watching layers
exist to notice."""
function process_snag(rule::Rule, translated_rule::Rule, supporting_vertical_bridges,
                      slippage_log::SlippageLog, rule_ref_objects, mem, ctx)
    return function (failure_result)
        snag_event = make_snag_event(failure_result, rule, translated_rule,
                                     supporting_vertical_bridges, slippage_log,
                                     rule_ref_objects, ctx)
        tr = ctx.trace
        tr === nothing || add_event!(tr::TemporalTrace, snag_event, ctx)
        if mem !== nothing && !snag_present(mem::Memory, rule, ctx, ctx.net)
            abstract_snag_description!(snag_event, mem::Memory, ctx)
        end
        for s in all_strings(ctx)
            delete_all_proposed_bonds!(s)
            delete_all_proposed_groups!(s)
        end
        delete_all_proposed_bridges!(ctx)
        ctx.temperature = 100
        ctx.temperature_clamped = true
        tr === nothing || activate!(snag_event, tr::TemporalTrace, ctx)
        # Deleting all codelets automatically erases every proposed bond, group
        # and bridge they were carrying.
        delete_all_codelets!(ctx.coderack, ctx)
        post_initial_codelets!(ctx)
        update_everything!(ctx)
        return :done
    end
end

"""`answer-finder` — the codelet that tries to turn a rule into an answer.

Two stochastic gates first: the mappings have to be strong (cubed, so a weak
one kills it), and the chosen rule has to be well supported. Then the rule is
translated into the target string's terms, applied — which is where a snag can
happen — and, if the answer is new, reported."""
function answer_finder(ctx::MetacatCtx, args::Vector{Any})
    TEMPERATURE[] = ctx.temperature
    net = ctx.net
    mem = ctx.memory
    top_strength = get_mapping_strength(ctx, :top)
    vertical_strength = get_mapping_strength(ctx, :vertical)
    # stochastic-if* on (1- x) ALWAYS draws: fizzle with probability 1-x.
    random_real(ctx.rng, 1.0) <
        sub_from_1(cube(pct(top_strength) * pct(vertical_strength))) && return
    supported_rules = get_supported_rules(ctx, :top)
    isempty(supported_rules) && return
    rule_weights = temp_adjusted_values([r.strength for r in supported_rules])
    rule = stochastic_pick(ctx.rng, supported_rules, rule_weights)::Rule
    degree_of_support = get_degree_of_support(rule, ctx)
    random_real(ctx.rng, 1.0) < sub_from_1(pct(degree_of_support)) && return
    currently_works(rule, ctx) || return
    result = translate(ctx.rng, rule, ctx.initial_string, ctx.target_string, net)
    result === nothing && return
    translated_rule = result.translated_rule
    snag_action = process_snag(rule, translated_rule,
                               result.supporting_vertical_bridges,
                               result.slippage_log, result.from_string_ref_objects,
                               mem, ctx)
    applied = apply_rule(translated_rule, ctx.target_string, net, snag_action)
    applied === nothing && return
    if mem !== nothing &&
       answer_present(mem::Memory, generate_image_letters(ctx.target_string),
                      rule, translated_rule, ctx, net)
        return
    end
    set_quality_values!(translated_rule, net)
    # make-translated-string sets the translated rule's supporting bridges and
    # theme pattern, so it has to happen before the answer is reported.
    translated_string = make_translated_string(translated_rule, ctx.target_string,
                                               ctx, net)
    all_supporting_groups = remq_duplicates(
        Any[result.vertical_mapping_supporting_groups...,
            get_rule_supporting_groups(rule, translated_rule, ctx, net)...])
    report_new_answer!(translated_string, rule, translated_rule,
                       result.supporting_vertical_bridges, all_supporting_groups,
                       result.from_string_ref_objects, result.to_string_ref_objects,
                       result.slippage_log, ConceptMapping[], mem, ctx)
    return
end

register_codelet_type!(:answer_finder, answer_finder)
