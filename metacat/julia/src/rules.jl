# Ported from rules.ss: the rule structure, its English transcription, and the
# quality metrics that rank one rule against another.
#
# A RULE is Metacat's answer to "what changed?" — a small symbolic program
# describing how the initial string became the modified one. Its grammar, from
# the comment at the top of rules.ss:
#
#   <intrinsic-rule-clause> ::= (intrinsic (<object-description>) (<change> ...))
#   <extrinsic-rule-clause> ::= (extrinsic (<object-description> ...) (<dimension> ...))
#   <verbatim-rule-clause>  ::= (verbatim (<letter-category> ...))
#   <object-description>    ::= (<object-type> <object-desc-type> <object-descriptor>)
#                             | (string <StrPosCtgy> <whole>)
#   <change>                ::= (<scope> <dimension> <descriptor>)
#   <scope>                 ::= self | subobjects
#
# An INTRINSIC clause changes objects in place ("change letter-category of the
# rightmost letter to its successor"); an EXTRINSIC one swaps a dimension
# between objects ("swap the positions of the leftmost and rightmost letters");
# a VERBATIM one gives up and quotes the answer. A rule with no clauses at all
# is the identity rule.
#
# Deferred, and coming with the rest of rules.ss: abstraction (building a rule
# from horizontal bridges), rule application, the rule codelets, and the
# translation machinery. The fields those need are marked below.

# --- the pieces a rule is made of -------------------------------------------

"""`<object-description>` — which objects a clause is about. `object_type` is a
slipnode, or the symbol `:string` for a clause about the whole string."""
struct ObjectDescription
    object_type::Any
    description_type::Node
    descriptor::Node
end

"""`<change>` — one dimension of one object (or of its constituents) becoming a
new descriptor, which may be a literal or a relation to slide by."""
struct Change
    scope::Symbol            # :self | :subobjects
    dimension::Node
    descriptor::Node
end

"""One clause of a rule. Only the fields its kind uses are populated."""
struct RuleClause
    kind::Symbol             # :intrinsic | :extrinsic | :verbatim
    object_descriptions::Vector{ObjectDescription}
    changes::Vector{Change}
    dimensions::Vector{Node}
    letter_categories::Vector{Node}
end

intrinsic_clause(od::ObjectDescription, changes::Vector{Change}) =
    RuleClause(:intrinsic, ObjectDescription[od], changes, Node[], Node[])
extrinsic_clause(ods::Vector{ObjectDescription}, dims::Vector{Node}) =
    RuleClause(:extrinsic, ods, Change[], dims, Node[])
verbatim_clause(letters::Vector{Node}) =
    RuleClause(:verbatim, ObjectDescription[], Change[], Node[], letters)

is_intrinsic_clause(rc::RuleClause) = rc.kind === :intrinsic
is_extrinsic_clause(rc::RuleClause) = rc.kind === :extrinsic
is_verbatim_clause(rc::RuleClause) = rc.kind === :verbatim

"""`(literal-object-description? od)` — pinned to a particular letter, length or
alphabetic position rather than to a role like "leftmost"."""
literal_object_description(od::ObjectDescription, net::Slipnet) =
    od.description_type === net[:plato_alphabetic_position_category] ||
    od.description_type === net[:plato_letter_category] ||
    od.description_type === net[:plato_length]

literal_change(c::Change, net::Slipnet) = !platonic_relation(c.descriptor, net)

"""`(literal-clause? rc)` — a clause is literal when it names a specific letter
or length anywhere, rather than describing the change in the abstract.

The Scheme's `record-case` has arms for the intrinsic and extrinsic clauses
only, so a verbatim clause falls through and returns Chez's unspecified value —
which is not `#f`, and so counts as true wherever the result is tested. Ported
as `true` to keep the behaviour. It only ever shows through on a rule that
mixes a verbatim clause with another kind, since `literal?` tests `verbatim?`
first and a lone verbatim clause makes the whole rule verbatim."""
literal_clause(rc::RuleClause, net::Slipnet) =
    is_intrinsic_clause(rc) ?
    (any(od -> literal_object_description(od, net), rc.object_descriptions) ||
     any(c -> literal_change(c, net), rc.changes)) :
    is_extrinsic_clause(rc) ?
    any(od -> literal_object_description(od, net), rc.object_descriptions) : true

# --- equality ---------------------------------------------------------------

"""`(object-descriptions-equal? od1 od2)` — NB a group and the whole string
count as the same object type here, since a whole-string group and the string
it spans denote the same thing."""
function object_descriptions_equal(od1::ObjectDescription, od2::ObjectDescription,
                                   net::Slipnet)
    grouplike(t) = t === net[:plato_group] || t === :string
    (od1.object_type === od2.object_type ||
     (grouplike(od1.object_type) && grouplike(od2.object_type))) || return false
    return od1.description_type === od2.description_type &&
           od1.descriptor === od2.descriptor
end

changes_equal(a::Vector{Change}, b::Vector{Change}) =
    length(a) == length(b) &&
    all(i -> a[i].scope === b[i].scope && a[i].dimension === b[i].dimension &&
             a[i].descriptor === b[i].descriptor, eachindex(a))

nodes_equal(a::Vector{Node}, b::Vector{Node}) =
    length(a) == length(b) && all(i -> a[i] === b[i], eachindex(a))

function rule_clauses_equal(rc1::RuleClause, rc2::RuleClause, net::Slipnet)
    rc1.kind === rc2.kind || return false
    if is_verbatim_clause(rc1)
        # the Scheme compares (2nd rc), which for a verbatim clause is the
        # letter-category list
        return nodes_equal(rc1.letter_categories, rc2.letter_categories)
    end
    length(rc1.object_descriptions) == length(rc2.object_descriptions) || return false
    all(i -> object_descriptions_equal(rc1.object_descriptions[i],
                                       rc2.object_descriptions[i], net),
        eachindex(rc1.object_descriptions)) || return false
    return is_intrinsic_clause(rc1) ? changes_equal(rc1.changes, rc2.changes) :
                                      nodes_equal(rc1.dimensions, rc2.dimensions)
end

rule_clause_lists_equal(l1, l2, net::Slipnet) =
    length(l1) == length(l2) &&
    all(i -> rule_clauses_equal(l1[i], l2[i], net), eachindex(l1))

# --- the rule ---------------------------------------------------------------

mutable struct Rule
    rule_type::Symbol                    # :top | :bottom
    rule_clauses::Vector{RuleClause}
    intrinsic_rule_clauses::Vector{RuleClause}
    extrinsic_rule_clauses::Vector{RuleClause}
    bridge_theme_type::Symbol
    english_transcription::Vector{String}
    uniformity::Int
    abstractness::Int
    succinctness::Int
    quality::Int
    """`intrinsic-quality`, marked "temporary. leave this for now" in rules.ss."""
    intrinsic_quality::Int
    # workspace-structure fields
    time_stamp::Int
    strength::Int
    proposal_level::Int
    enclosing_group::Union{Nothing,WSObject}
    # What the rule was abstracted from and what it now rests on. A rule
    # written straight from clauses (or a verbatim one) has none of this until
    # `set-abstracted-rule-information` or `set-verbatim-rule-information` fills
    # it in. Untyped where the element type is defined further down this file.
    rule_clause_templates::Vector{Any}
    tagged_supporting_horizontal_bridges::Vector{Any}
    supporting_horizontal_bridges::Vector{Bridge}
    theme_pattern::Any
    translated::Bool
end

"""`(make-rule rule-type rule-clauses)`. The English transcription is computed
at construction, which is why the rule needs the string it describes."""
function make_rule(rule_type::Symbol, rule_clauses::Vector{RuleClause},
                   s::WorkspaceString, net::Slipnet, codelet_count::Int = 0)
    return Rule(rule_type, rule_clauses,
                RuleClause[rc for rc in rule_clauses if is_intrinsic_clause(rc)],
                RuleClause[rc for rc in rule_clauses if is_extrinsic_clause(rc)],
                rule_type === :top ? :top_bridge : :bottom_bridge,
                transcribe_to_english(rule_clauses, s, net),
                0, 0, 0, 0, 0, codelet_count, 0, 0, nothing,
                Any[], Any[], Bridge[], nothing, false)
end

is_identity_rule(r::Rule) = isempty(r.rule_clauses)
is_verbatim_rule(r::Rule) =
    length(r.rule_clauses) == 1 && is_verbatim_clause(r.rule_clauses[1])
is_literal_rule(r::Rule, net::Slipnet) =
    !is_verbatim_rule(r) && any(rc -> literal_clause(rc, net), r.rule_clauses)
is_abstract_rule(r::Rule, net::Slipnet) =
    !is_verbatim_rule(r) && !is_literal_rule(r, net)

"""`(get-characterization)`."""
rule_characterization(r::Rule, net::Slipnet) =
    is_verbatim_rule(r) ? :verbatim :
    is_literal_rule(r, net) ? :literal : :abstract

get_verbatim_letter_categories(r::Rule) = r.rule_clauses[1].letter_categories

rules_equal(r1::Rule, r2::Rule, net::Slipnet) =
    rule_clause_lists_equal(r1.rule_clauses, r2.rule_clauses, net)

"""`(get-concept-pattern)` — every slipnode the rule mentions, clamped."""
function get_concept_pattern(r::Rule)
    nodes = Node[]
    for rc in r.rule_clauses
        for od in rc.object_descriptions
            od.object_type isa Node && push!(nodes, od.object_type::Node)
            push!(nodes, od.description_type)
            push!(nodes, od.descriptor)
        end
        for c in rc.changes
            push!(nodes, c.dimension); push!(nodes, c.descriptor)
        end
        append!(nodes, rc.dimensions)
        append!(nodes, rc.letter_categories)
    end
    # remq-duplicates keeps the LAST of each duplicate group
    return Node[n for (i, n) in enumerate(nodes) if !any(x -> x === n, nodes[(i + 1):end])]
end

# --- quality ----------------------------------------------------------------

"""`(sigmoid beta m)`."""
sigmoid(beta, m) = x -> sdiv(1, 1 + exp(1 // 25 * beta * (m - x)))

"""`(average ...)` — Metacat's, which is 0 for an empty list."""
savg(l::AbstractVector) = isempty(l) ? 0 : sdiv(ssum(l), length(l))
savg(a, b) = sdiv(a + b, 2)

"""`(100* x)`."""
mul100(x) = sround(100 * x)

"""`(object-description-uniformity ods)` — how far the descriptions agree on
which DIMENSION they pick objects out by."""
function object_description_uniformity(ods::Vector{ObjectDescription})
    types = Node[od.description_type for od in ods]
    groups = spartition((a, b) -> a === b, types)
    return sdiv(maximum(length, groups), length(types))
end

"""`(change-abstractness-uniformity changes)` — 1 when the changes are all
relations or all literals, 0 when they are evenly mixed."""
function change_abstractness_uniformity(changes::Vector{Change}, net::Slipnet)
    n = count(c -> platonic_relation(c.descriptor, net), changes)
    return 2 * abs(sdiv(n, length(changes)) - 1 // 2)
end

"""`(compute-rule-uniformity rule)` — how much of a piece the rule is. A rule
that describes every object the same way and changes them all the same way
scores high; one that mixes literal and abstract changes, or picks objects out
by different dimensions, is penalised sharply (note the `exp(4(x-1))`)."""
function compute_rule_uniformity(r::Rule, net::Slipnet)
    (is_identity_rule(r) || is_verbatim_rule(r)) && return 100
    changes = Change[c for rc in r.intrinsic_rule_clauses for c in rc.changes
                     if c.dimension !== net[:plato_object_category] &&
                        c.dimension !== net[:plato_bond_facet]]
    grouped = spartition((c1, c2) -> c1.dimension === c2.dimension, changes)
    all_intrinsic_ods = ObjectDescription[od for rc in r.intrinsic_rule_clauses
                                          for od in rc.object_descriptions]
    intrinsic_u = isempty(r.intrinsic_rule_clauses) ? 1 :
        savg(prod([change_abstractness_uniformity(Change[c for c in g], net)
                   for g in grouped]; init = 1),
             object_description_uniformity(all_intrinsic_ods))
    extrinsic_u = isempty(r.extrinsic_rule_clauses) ? 1 :
        savg([cube(object_description_uniformity(rc.object_descriptions))
              for rc in r.extrinsic_rule_clauses])
    clause_type_u = sdiv(max(count(is_intrinsic_clause, r.rule_clauses),
                             count(is_extrinsic_clause, r.rule_clauses)),
                         length(r.rule_clauses))
    raw = weighted_average([intrinsic_u, extrinsic_u, clause_type_u], [5, 5, 1])
    return mul100(exp(4 * (raw - 1)))
end

"""`(compute-rule-abstractness rule)` — the average conceptual depth of what the
rule talks about, squashed. The identity rule is maximally abstract; a verbatim
one, which just quotes the answer, is not abstract at all."""
function compute_rule_abstractness(r::Rule, net::Slipnet)
    is_identity_rule(r) && return 100
    is_verbatim_rule(r) && return 0
    adjust_depth = sigmoid(3, 40)
    ods = ObjectDescription[od for rc in r.rule_clauses for od in rc.object_descriptions]
    intrinsic_changes = Change[c for rc in r.intrinsic_rule_clauses for c in rc.changes]
    swap_dimensions = Node[d for rc in r.extrinsic_rule_clauses for d in rc.dimensions]
    depths = [savg([od.description_type.conceptual_depth for od in ods]),
              savg([c.descriptor.conceptual_depth for c in intrinsic_changes]),
              savg([d.conceptual_depth for d in swap_dimensions])]
    return mul100(adjust_depth(savg([d for d in depths if d != 0])))
end

"""`(compute-rule-succinctness rule)` — shorter is better; a multi-object
extrinsic clause counts double."""
function compute_rule_succinctness(r::Rule)
    (is_identity_rule(r) || is_verbatim_rule(r)) && return 100
    total = ssum([is_intrinsic_clause(rc) ? 1 :
                  length(rc.object_descriptions) > 1 ? 2 : 1
                  for rc in r.rule_clauses])
    return mul100(sdiv(4, 3 + total))
end

"""`(compute-rule-quality rule)`."""
compute_rule_quality(r::Rule) =
    sround(pct(r.uniformity) * weighted_average([r.abstractness, r.succinctness], [3, 2]))

"""`(compute-rule-intrinsic-quality rule)`, marked "temporary" in rules.ss but
computed on every rule, so ported as it stands."""
function compute_rule_intrinsic_quality(r::Rule, net::Slipnet)
    is_identity_rule(r) && return 100
    is_verbatim_rule(r) && return 10
    od_types = Node[od.description_type for rc in r.rule_clauses
                    for od in rc.object_descriptions]
    od_depth_factor = sigmoid(3, 30)(savg([n.conceptual_depth for n in od_types]))
    changes = Change[c for rc in r.intrinsic_rule_clauses for c in rc.changes
                     if c.dimension !== net[:plato_object_category]]
    descriptors = Node[c.descriptor for c in changes]
    change_abstractness = isempty(descriptors) ? 1 :
        sdiv(count(d -> platonic_relation(d, net), descriptors), length(descriptors))
    grouped = spartition((c1, c2) -> c1.dimension === c2.dimension, changes)
    intrinsic_ods = ObjectDescription[od for rc in r.intrinsic_rule_clauses
                                      for od in rc.object_descriptions]
    intrinsic_u = isempty(r.intrinsic_rule_clauses) ? 1 :
        prod([change_abstractness_uniformity(Change[c for c in g], net)
              for g in grouped]; init = 1) *
        sq(object_description_uniformity(intrinsic_ods))
    extrinsic_u = isempty(r.extrinsic_rule_clauses) ? 1 :
        savg([cube(object_description_uniformity(rc.object_descriptions))
              for rc in r.extrinsic_rule_clauses])
    cohesion = exp(5 * (savg(intrinsic_u, extrinsic_u) - 1))
    return mul100(cohesion * savg(od_depth_factor, change_abstractness))
end

"""`(set-quality-values)`."""
function set_quality_values!(r::Rule, net::Slipnet)
    r.uniformity = compute_rule_uniformity(r, net)
    r.abstractness = compute_rule_abstractness(r, net)
    r.succinctness = compute_rule_succinctness(r)
    r.intrinsic_quality = compute_rule_intrinsic_quality(r, net)
    r.quality = compute_rule_quality(r)
    return r
end

# --- printing ---------------------------------------------------------------

format_slipnode(n::Node) = string("<", n.short_name, ">")
format_object_description(od::ObjectDescription) =
    string("(", od.object_type === :string ? "string" :
                format_slipnode(od.object_type::Node), " ",
           format_slipnode(od.description_type), " ",
           format_slipnode(od.descriptor), ")")
format_change(c::Change) =
    string("(", c.scope, " ", format_slipnode(c.dimension), " ",
           format_slipnode(c.descriptor), ")")

# --- English transcription --------------------------------------------------
#
# Every rule carries a plain-English rendering, computed at construction. It is
# what the model shows a person, and — because a rule is a symbolic structure
# rather than a sentence — writing it out is a small natural-language generation
# problem in its own right: singular versus plural, "a" versus "an", and a
# fourteen-case table for how object-category, length and letter-category
# changes combine into one phrase.

const MAXIMUM_RULE_LINE_LENGTH = 60

"""`(get-object-description-ref-objects object-description)` — the objects in a
string that an object description picks out."""
function get_object_description_ref_objects(s::WorkspaceString, od::ObjectDescription,
                                            net::Slipnet)
    if od.object_type === :string
        # In abc->aaa a rule made before the group [abc] exists says
        # (string <StrPos> <whole>); once [abc] appears the string itself is no
        # longer the right referent, so a whole group takes precedence.
        wg = whole_group(s, net)
        # NB the string itself, not a workspace object, when no whole group has
        # been built yet — hence the untyped vector.
        return Any[wg === nothing ? s : wg::WSObject]
    end
    pool = od.object_type === net[:plato_letter] ? s.letters : s.groups
    candidates = Any[o for o in pool if descriptor_present(o, od.descriptor)]
    if od.description_type === net[:plato_string_position_category] &&
       length(candidates) > 1
        with_bridges = Any[o for o in candidates if o.vertical_bridge !== nothing]
        return Any[lowest_level_object(isempty(with_bridges) ? candidates :
                                       with_bridges)]
    end
    return candidates
end

"""`(whole-group?)` — the group, if any, described as spanning the string."""
function whole_group(s::WorkspaceString, net::Slipnet)
    i = findfirst(g -> descriptor_present(g, net[:plato_whole]), s.groups)
    return i === nothing ? nothing : s.groups[i]
end

"""`(lowest-level-object objects)` — the most deeply nested one."""
function lowest_level_object(objects)
    levels = [nesting_level(o) for o in objects]
    return objects[findfirst(==(maximum(levels)), levels)]
end

plural_object_phrase(od::ObjectDescription, s::WorkspaceString, net::Slipnet) =
    length(get_object_description_ref_objects(s, od, net)) > 1

"""`(get-dimension-phrase dimension plural?)`."""
function get_dimension_phrase(dimension::Node, plural::Bool)
    n = dimension.name
    n === :plato_direction_category && return plural ? "directions" : "direction"
    n === :plato_group_category && return plural ? "group-types" : "group-type"
    n === :plato_alphabetic_position_category &&
        return plural ? "alphabetic-positions" : "alphabetic-position"
    n === :plato_letter_category && return plural ? "letter-categories" : "letter-category"
    n === :plato_length && return plural ? "lengths" : "length"
    n === :plato_object_category && return plural ? "object-types" : "object-type"
    return plural ? "positions" : "position"
end

"""`(punctuate l)` — "a", "a and b", "a, b, and c"."""
function punctuate(l)
    isempty(l) && return ""
    length(l) == 1 && return l[1]
    length(l) == 2 && return string(l[1], " and ", l[2])
    return string(join([string(x, ", ") for x in l[1:(end - 1)]]), "and ", l[end])
end

"""`(get-object-phrase object-description plural? string)`."""
function get_object_phrase(od::ObjectDescription, plural::Bool, s::WorkspaceString,
                           net::Slipnet)
    object_type = od.object_type
    descriptor = od.descriptor
    if object_type === :string || descriptor === net[:plato_whole]
        return whole_group(s, net) === nothing ? "string" : "whole group"
    end
    if platonic_letter(descriptor, net)
        plural && return string("all `", descriptor.lowercase_name, "' ",
                                (object_type::Node).lowercase_name, "s")
        object_type === net[:plato_letter] &&
            return string("letter `", descriptor.lowercase_name, "'")
        return string("`", descriptor.lowercase_name, "' group")
    end
    plural && return string("all ", descriptor.lowercase_name, " ",
                            (object_type::Node).lowercase_name, "s")
    return string(descriptor.lowercase_name, " ", (object_type::Node).lowercase_name)
end

"""`(get-change-phrase ...)` for the changes that are not object-category or
length; those go through the combined table below."""
function get_change_phrase(c::Change, object_phrase::String, plural::Bool,
                           bond_facet_change::Union{Nothing,Change}, net::Slipnet)
    subs = c.scope === :subobjects
    if c.dimension === net[:plato_direction_category]
        return string("Reverse ", get_dimension_phrase(c.dimension, plural || subs),
                      " of ", subs ? "all objects in " : "", object_phrase)
    elseif c.dimension === net[:plato_group_category]
        if c.scope === :self
            medium = (bond_facet_change::Change).descriptor ===
                     net[:plato_letter_category] ? "letter-categories" : "lengths"
            return string("Reverse starting and ending ", medium, " of ", object_phrase)
        end
        return string("Reverse starting and ending points of all objects in ",
                      object_phrase)
    end
    return string("Change ", get_dimension_phrase(c.dimension, plural || subs), " of ",
                  subs ? "all objects in " : "", object_phrase, " to ",
                  platonic_letter(c.descriptor, net) ?
                  string("`", c.descriptor.lowercase_name, "'") :
                  c.descriptor.lowercase_name)
end

obj_ctgy_or_length_change(c::Change, net::Slipnet) =
    c.dimension === net[:plato_object_category] || c.dimension === net[:plato_length]

"""`(select-change dimension scope changes)` — the FIRST matching change; a
`nothing` scope matches any."""
function select_change(dimension::Node, scope, changes::Vector{Change})
    i = findfirst(c -> (scope === nothing || c.scope === scope) &&
                       c.dimension === dimension, changes)
    return i === nothing ? nothing : changes[i]
end

select_descriptor(dimension::Node, scope, changes::Vector{Change}) =
    (c = select_change(dimension, scope, changes); c === nothing ? nothing : c.descriptor)

"""`(new-object-phrase ...)` — "a letter", "the letter `c'", "an `a' group"."""
function new_object_phrase(new_object_type::Node, lett_ctgy::Union{Nothing,Node},
                           plural::Bool, net::Slipnet)
    an_letters = (:plato_a, :plato_e, :plato_f, :plato_h, :plato_i, :plato_l,
                  :plato_m, :plato_n, :plato_o, :plato_r, :plato_s, :plato_x)
    literal = lett_ctgy !== nothing && !platonic_relation(lett_ctgy::Node, net)
    if new_object_type === net[:plato_letter]
        literal && return string("the letter `", (lett_ctgy::Node).lowercase_name, "'")
        return plural ? "letters" : "a letter"
    end
    if literal
        plural && return string("`", (lett_ctgy::Node).lowercase_name, "' groups")
        article = (lett_ctgy::Node).name in an_letters ? "an" : "a"
        return string(article, " `", (lett_ctgy::Node).lowercase_name, "' group")
    end
    return plural ? "groups" : "a group"
end

change_to_object_type(object_phrase, plural, object_type::Node,
                      lett_ctgy::Union{Nothing,Node}, subobjects::Bool, net::Slipnet) =
    string("Change ", subobjects ? "all objects in " : "", object_phrase, " to ",
           new_object_phrase(object_type, lett_ctgy, plural || subobjects, net))

change_to_group_of_length(object_phrase, plural, len::Node,
                          lett_ctgy::Union{Nothing,Node}, subobjects::Bool,
                          net::Slipnet) =
    string("Change ", subobjects ? "all objects in " : "", object_phrase, " to ",
           new_object_phrase(net[:plato_group], lett_ctgy, plural || subobjects, net),
           " of length ", len.lowercase_name)

function change_length_of(object_phrase, plural, len::Node, subobjects::Bool,
                          net::Slipnet)
    phrase = get_dimension_phrase(net[:plato_length], plural || subobjects)
    where_ = subobjects ? "all objects in " : ""
    len === net[:plato_successor] &&
        return string("Increase ", phrase, " of ", where_, object_phrase, " by one")
    len === net[:plato_predecessor] &&
        return string("Decrease ", phrase, " of ", where_, object_phrase, " by one")
    return string("Change ", phrase, " of ", where_, object_phrase, " to ",
                  len.lowercase_name)
end

"""`(get-ObjCtgy/Length/LettCtgy-change-phrases ...)` — the fourteen-case table
in rules.ss. Object-category, length and letter-category changes are described
together, because "change it to a group of length three" reads far better than
three separate sentences."""
function obj_length_lett_phrases(object_phrase::String, plural::Bool,
                                 changes::Vector{Change}, net::Slipnet)
    oc = net[:plato_object_category]
    len = net[:plato_length]
    lc = net[:plato_letter_category]
    ObjCtgy_self = select_descriptor(oc, :self, changes)
    ObjCtgy_subs = select_descriptor(oc, :subobjects, changes)
    Length_self = select_descriptor(len, :self, changes)
    Length_subs = select_descriptor(len, :subobjects, changes)
    LettCtgy_self = select_descriptor(lc, :self, changes)
    LettCtgy_subs = select_descriptor(lc, :subobjects, changes)
    rel(x) = x !== nothing && platonic_relation(x::Node, net)
    if ObjCtgy_self !== nothing && Length_self !== nothing
        ObjCtgy_self === net[:plato_letter] &&
            return [change_to_object_type(object_phrase, plural, net[:plato_letter],
                                          LettCtgy_self, false, net)]
        rel(Length_self) &&
            return [change_length_of(object_phrase, plural, Length_self::Node, false, net)]
        return [change_to_group_of_length(object_phrase, plural, Length_self::Node,
                                          LettCtgy_self, false, net)]
    elseif ObjCtgy_self !== nothing
        return [change_to_object_type(object_phrase, plural, ObjCtgy_self::Node,
                                      LettCtgy_self, false, net)]
    elseif ObjCtgy_subs !== nothing && Length_self !== nothing && Length_subs !== nothing
        second = ObjCtgy_subs === net[:plato_letter] ?
                 change_to_object_type(object_phrase, plural, net[:plato_letter],
                                       LettCtgy_subs, true, net) :
                 rel(Length_subs) ?
                 change_length_of(object_phrase, plural, Length_subs::Node, true, net) :
                 change_to_group_of_length(object_phrase, plural, Length_subs::Node,
                                           LettCtgy_subs, true, net)
        return [change_length_of(object_phrase, plural, Length_self::Node, false, net),
                second]
    elseif ObjCtgy_subs !== nothing && Length_self !== nothing
        return [change_length_of(object_phrase, plural, Length_self::Node, false, net),
                change_to_object_type(object_phrase, plural, ObjCtgy_subs::Node,
                                      LettCtgy_subs, true, net)]
    elseif ObjCtgy_subs !== nothing && Length_subs !== nothing
        ObjCtgy_subs === net[:plato_letter] &&
            return [change_to_object_type(object_phrase, plural, net[:plato_letter],
                                          LettCtgy_subs, true, net)]
        rel(Length_subs) &&
            return [change_length_of(object_phrase, plural, Length_subs::Node, true, net)]
        return [change_to_group_of_length(object_phrase, plural, Length_subs::Node,
                                          LettCtgy_subs, true, net)]
    elseif ObjCtgy_subs !== nothing
        return [change_to_object_type(object_phrase, plural, ObjCtgy_subs::Node,
                                      LettCtgy_subs, true, net)]
    elseif Length_self !== nothing && Length_subs !== nothing
        return [change_length_of(object_phrase, plural, Length_self::Node, false, net),
                change_length_of(object_phrase, plural, Length_subs::Node, true, net)]
    elseif Length_self !== nothing
        return [change_length_of(object_phrase, plural, Length_self::Node, false, net)]
    elseif Length_subs !== nothing
        return [change_length_of(object_phrase, plural, Length_subs::Node, true, net)]
    end
    return String[]
end

"""`(remove-LettCtgy-change-if-necessary changes)` — drop a letter-category
change that the combined object-category phrase already says."""
function remove_lett_ctgy_change_if_necessary(changes::Vector{Change}, net::Slipnet)
    obj_change = select_change(net[:plato_object_category], nothing, changes)
    obj_change === nothing && return changes
    oc = obj_change::Change
    same_lett = select_change(net[:plato_letter_category], oc.scope, changes)
    same_len = select_change(net[:plato_length], oc.scope, changes)
    if same_lett !== nothing && !platonic_relation((same_lett::Change).descriptor, net) &&
       (same_len === nothing || !platonic_relation((same_len::Change).descriptor, net) ||
        oc.descriptor === net[:plato_letter])
        return Change[c for c in changes if c !== same_lett]
    end
    return changes
end

"""`(get-rule-clause-phrases string)`."""
function get_rule_clause_phrases(rc::RuleClause, s::WorkspaceString, net::Slipnet)
    if is_verbatim_clause(rc)
        return [string("Change string to \"",
                       join([n.lowercase_name for n in rc.letter_categories]), "\"")]
    elseif is_extrinsic_clause(rc)
        objects_phrase = punctuate([get_object_phrase(od,
                                                      plural_object_phrase(od, s, net),
                                                      s, net)
                                    for od in rc.object_descriptions])
        dims_phrase = punctuate([get_dimension_phrase(d, true) for d in rc.dimensions])
        return [length(rc.object_descriptions) == 1 ?
                string("Swap ", dims_phrase, " of all objects in ", objects_phrase) :
                string("Swap ", dims_phrase, " of ", objects_phrase)]
    end
    od = rc.object_descriptions[1]
    plural = plural_object_phrase(od, s, net)
    object_phrase = get_object_phrase(od, plural, s, net)
    combined = obj_length_lett_phrases(object_phrase, plural, rc.changes, net)
    bond_facet_change = select_change(net[:plato_bond_facet], :self, rc.changes)
    others = Change[c for c in remove_lett_ctgy_change_if_necessary(rc.changes, net)
                    if !obj_ctgy_or_length_change(c, net) && c !== bond_facet_change]
    other_phrases = [get_change_phrase(c, object_phrase, plural, bond_facet_change, net)
                     for c in others]
    return vcat(other_phrases, combined)
end

"""`(find-next-space-position s i)` — 0-based, as in the Scheme."""
function find_next_space_position(s::AbstractString, i::Int)
    n = length(s)
    while true
        i >= n && return n
        s[i + 1] == ' ' && return i
        i += 1
    end
end

"""`(separate-into-multiple-lines max-length indent)` — wrap at the first space
at or after the limit, indenting continuations."""
function separate_into_multiple_lines(s::String, max_length::Int, indent::String)
    next_pos = find_next_space_position(s, max_length)
    next_pos == length(s) && return String[s]
    return vcat(String[s[1:next_pos]],
                separate_into_multiple_lines(string(indent, s[(next_pos + 1):end]),
                                             max_length, indent))
end

"""`(transcribe-to-english rule-type rule-clauses)`. The line width is chosen so
that no phrase is split into more pieces than it has to be: each phrase's own
length is divided into the fewest lines that keep it under the limit, and the
widest of those quotients sets the width for all of them."""
function transcribe_to_english(rule_clauses::Vector{RuleClause}, s::WorkspaceString,
                               net::Slipnet)
    clause_strings = isempty(rule_clauses) ? String["Don't change anything"] :
                     String[p for rc in rule_clauses
                            for p in get_rule_clause_phrases(rc, s, net)]
    adjusted = [sceiling(sdiv(length(str),
                              sceiling(sdiv(length(str), MAXIMUM_RULE_LINE_LENGTH))))
                for str in clause_strings]
    max_line_length = isempty(adjusted) ? 0 : maximum(adjusted)
    return String[line for str in clause_strings
                  for line in separate_into_multiple_lines(str, max_line_length, "  ")]
end

# --- change descriptions ----------------------------------------------------
#
# A change description says that one dimension of one object became something
# else. It is the currency of rule abstraction — one is made for every
# horizontal bridge that describes a change — but rule APPLICATION needs them
# too, to notice that two transforms of the same rule contradict each other.
#
# Two kinds. An INTRINSIC change description is about one object; an EXTRINSIC
# one is about a set of objects trading a dimension between them, and carries
# the equivalent intrinsic changes so that the two kinds can be compared.

mutable struct IntrinsicChangeDescription
    reference_object::Any            # a workspace object, or a workspace string
    scope::Symbol                    # :self | :subobjects
    dimension::Node
    descriptor1::Union{Nothing,Node}
    relation::Union{Nothing,Node}
    descriptor2::Union{Nothing,Node}
    descriptors::Vector{Node}
    enclosing_object::Any            # nothing when the referent is a string
end

"""`(make-intrinsic-change-description ...)`."""
function make_intrinsic_change_description(reference_object, scope::Symbol,
                                           dimension::Node,
                                           descriptor1::Union{Nothing,Node},
                                           relation::Union{Nothing,Node},
                                           descriptor2::Union{Nothing,Node})
    descriptors = Node[d for d in (relation, descriptor2) if d !== nothing]
    enclosing = reference_object isa WorkspaceString ? nothing :
                get_enclosing_object(reference_object::WSObject)
    return IntrinsicChangeDescription(reference_object, scope, dimension, descriptor1,
                                      relation, descriptor2, descriptors, enclosing)
end

mutable struct ExtrinsicChangeDescription
    reference_objects::Vector{Any}
    dimension::Node
    descriptors::Vector{Node}
    equivalent_intrinsic_changes::Vector{IntrinsicChangeDescription}
    subobjects_swap::Bool
end

"""`(make-extrinsic-change-description reference-objects dimension descriptors)`
— the equivalent intrinsic changes are "each object takes the OTHER of the two
descriptors"."""
function make_extrinsic_change_description(reference_objects, dimension::Node,
                                           descriptors::Vector{Node})
    equivalents = IntrinsicChangeDescription[
        make_intrinsic_change_description(
            obj, :self, dimension, nothing, nothing,
            get_descriptor_for(obj, dimension) === descriptors[1] ? descriptors[2] :
                                                                    descriptors[1])
        for obj in reference_objects]
    return ExtrinsicChangeDescription(Any[reference_objects...], dimension, descriptors,
                                      equivalents, false)
end

const ChangeDescription = Union{IntrinsicChangeDescription,ExtrinsicChangeDescription}

is_intrinsic_change(::IntrinsicChangeDescription) = true
is_intrinsic_change(::ExtrinsicChangeDescription) = false

change_dimension_is(c::ChangeDescription, dim::Node) = c.dimension === dim
same_dimension(c1::ChangeDescription, c2::ChangeDescription) =
    c1.dimension === c2.dimension
same_scope(ic1::IntrinsicChangeDescription, ic2::IntrinsicChangeDescription) =
    ic1.scope === ic2.scope
change_self(ic::IntrinsicChangeDescription) = ic.scope === :self
change_subobjects(ic::IntrinsicChangeDescription) = ic.scope === :subobjects
lett_ctgy_or_alph_pos_dimension(ic::IntrinsicChangeDescription, net::Slipnet) =
    ic.dimension === net[:plato_letter_category] ||
    ic.dimension === net[:plato_alphabetic_position_category]
same_reference_objects(ic1::IntrinsicChangeDescription,
                       ic2::IntrinsicChangeDescription) =
    ic1.reference_object === ic2.reference_object
same_reference_objects(ec1::ExtrinsicChangeDescription,
                       ec2::ExtrinsicChangeDescription) =
    sets_equal(ec1.reference_objects, ec2.reference_objects)
encloses(ic1::IntrinsicChangeDescription, ic2::IntrinsicChangeDescription) =
    ic1.reference_object === ic2.enclosing_object
encloses_at_any_level(ic1::IntrinsicChangeDescription,
                      ic2::IntrinsicChangeDescription) =
    nested_member(ic1.reference_object, ic2.reference_object)
change_to_letter(ic::IntrinsicChangeDescription, net::Slipnet) =
    ic.descriptor2 === net[:plato_letter]
same_dimension_as_group_ctgy_medium(ic::IntrinsicChangeDescription,
                                    other::IntrinsicChangeDescription, net::Slipnet) =
    ic.dimension === get_bond_facet(other.reference_object, net)
implied_by_opposite_group_ctgy(ic::IntrinsicChangeDescription, net::Slipnet) =
    ic.reference_object isa Group &&
    get_ending_letter_category(ic.reference_object::Group, net) === ic.descriptor2
common_reference_object(ec::ExtrinsicChangeDescription,
                        ic::IntrinsicChangeDescription) =
    any(o -> o === ic.reference_object, ec.reference_objects)
get_change_enclosing_object(ec::ExtrinsicChangeDescription) =
    get_enclosing_object(ec.reference_objects[1])

"""`(mark-as-subobjects-swap-if-possible)` — a swap among exactly the
constituents of one enclosing object is a swap of THAT object's subobjects."""
function mark_as_subobjects_swap_if_possible!(ec::ExtrinsicChangeDescription)
    if sets_equal(get_constituent_objects(get_change_enclosing_object(ec)),
                  ec.reference_objects)
        ec.subobjects_swap = true
    end
    return ec
end

# --- change-description heuristics ------------------------------------------
#
# See pages 110-113 of Marshall's thesis for what each clause of
# `intrinsic-implies-intrinsic?` is for; the cases are set out at length in the
# comment above it in rules.ss. The shape of the idea: a change is redundant
# when some other change already brings it about — changing every subobject's
# length already changes this letter's length, and reversing a group already
# changes which letter it ends on.

"""`(intrinsic-implies-intrinsic? ic1 ic2)` — is ic2 already implicit in ic1?"""
function intrinsic_implies_intrinsic(ic1::IntrinsicChangeDescription,
                                     ic2::IntrinsicChangeDescription, net::Slipnet)
    (same_dimension(ic1, ic2) &&
     ((same_reference_objects(ic1, ic2) && same_scope(ic1, ic2)) ||
      (encloses(ic1, ic2) && change_subobjects(ic1) && change_self(ic2)))) && return true
    (lett_ctgy_or_alph_pos_dimension(ic1, net) &&
     lett_ctgy_or_alph_pos_dimension(ic2, net) &&
     ((same_reference_objects(ic1, ic2) &&
       ((change_dimension_is(ic1, net[:plato_alphabetic_position_category]) &&
         change_dimension_is(ic2, net[:plato_letter_category])) ||
        (same_dimension(ic1, ic2) && change_subobjects(ic2)))) ||
      encloses_at_any_level(ic1, ic2))) && return true
    (change_dimension_is(ic1, net[:plato_length]) &&
     change_dimension_is(ic2, net[:plato_letter_category]) &&
     encloses(ic1, ic2) && change_self(ic1)) && return true
    (change_dimension_is(ic1, net[:plato_group_category]) && change_self(ic1) &&
     same_dimension_as_group_ctgy_medium(ic2, ic1, net) &&
     (encloses(ic1, ic2) ||
      (same_reference_objects(ic1, ic2) &&
       change_dimension_is(ic2, net[:plato_letter_category]) &&
       implied_by_opposite_group_ctgy(ic2, net)))) && return true
    (change_dimension_is(ic1, net[:plato_string_position_category]) &&
     change_dimension_is(ic2, net[:plato_direction_category]) &&
     encloses(ic2, ic1) && change_self(ic2)) && return true
    (change_to_letter(ic1, net) && change_dimension_is(ic2, net[:plato_length]) &&
     ((same_reference_objects(ic1, ic2) && same_scope(ic1, ic2)) ||
      (encloses(ic1, ic2) && change_subobjects(ic1) && change_self(ic2)))) && return true
    return false
end

"""`(conflicts? ic1 ic2)` — implication either way."""
change_conflicts(ic1::IntrinsicChangeDescription, ic2::IntrinsicChangeDescription,
                 net::Slipnet) =
    intrinsic_implies_intrinsic(ic1, ic2, net) ||
    intrinsic_implies_intrinsic(ic2, ic1, net)

extrinsic_implies_intrinsic(ec::ExtrinsicChangeDescription,
                            ic::IntrinsicChangeDescription, net::Slipnet) =
    any(e -> change_conflicts(e, ic, net), ec.equivalent_intrinsic_changes)

extrinsic_implies_extrinsic(ec1::ExtrinsicChangeDescription,
                            ec2::ExtrinsicChangeDescription, net::Slipnet) =
    all(ic1 -> any(ic2 -> change_implies(ic1, ic2, net),
                   ec2.equivalent_intrinsic_changes),
        ec1.equivalent_intrinsic_changes)

"""`(implies? c)`. NB an intrinsic change never implies an extrinsic one."""
change_implies(ic::IntrinsicChangeDescription, c::ChangeDescription, net::Slipnet) =
    c isa IntrinsicChangeDescription ?
    intrinsic_implies_intrinsic(ic, c::IntrinsicChangeDescription, net) : false
change_implies(ec::ExtrinsicChangeDescription, c::ChangeDescription, net::Slipnet) =
    c isa IntrinsicChangeDescription ?
    extrinsic_implies_intrinsic(ec, c::IntrinsicChangeDescription, net) :
    extrinsic_implies_extrinsic(ec, c::ExtrinsicChangeDescription, net)

get_redundant_change(c1::ChangeDescription, c2::ChangeDescription, net::Slipnet) =
    change_implies(c1, c2, net) ? c2 :
    change_implies(c2, c1, net) ? c1 : nothing

"""`(get-symmetric-changes string-position-ec)` — two changes that swap each
other's descriptors between two objects whose positions are being swapped say
nothing the swap does not already say."""
function get_symmetric_changes(string_position_ec::ExtrinsicChangeDescription,
                               ic1::IntrinsicChangeDescription,
                               ic2::IntrinsicChangeDescription)
    if common_reference_object(string_position_ec, ic1) &&
       common_reference_object(string_position_ec, ic2) &&
       same_dimension(ic1, ic2) &&
       ic1.descriptor1 === ic2.descriptor2 && ic1.descriptor2 === ic2.descriptor1
        return ChangeDescription[ic1, ic2]
    end
    return ChangeDescription[]
end

function get_changes_implied_by_swap(intrinsic_cds, other_extrinsic_cds,
                                     string_position_ec::ExtrinsicChangeDescription)
    result = ChangeDescription[ec for ec in other_extrinsic_cds
                               if same_reference_objects(ec, string_position_ec)]
    for pair in pairwise_map((a, b) -> get_symmetric_changes(string_position_ec, a, b),
                             intrinsic_cds)
        append!(result, pair)
    end
    return result
end

function changes_implied_by_string_position_swaps(change_descriptions, net::Slipnet)
    string_position_cds = ChangeDescription[
        c for c in change_descriptions
        if change_dimension_is(c, net[:plato_string_position_category])]
    intrinsic_cds = IntrinsicChangeDescription[c for c in change_descriptions
                                               if c isa IntrinsicChangeDescription]
    other_extrinsic_cds = ChangeDescription[
        c for c in change_descriptions
        if !is_intrinsic_change(c) && !any(x -> x === c, string_position_cds)]
    result = ChangeDescription[]
    for ec in string_position_cds
        append!(result,
                get_changes_implied_by_swap(intrinsic_cds, other_extrinsic_cds,
                                            ec::ExtrinsicChangeDescription))
    end
    return result
end

"""`(remove-redundant-change-descriptions change-descriptions)`."""
function remove_redundant_change_descriptions(change_descriptions, net::Slipnet)
    doomed = ChangeDescription[]
    for c in pairwise_map((a, b) -> get_redundant_change(a, b, net), change_descriptions)
        c === nothing || push!(doomed, c::ChangeDescription)
    end
    append!(doomed, changes_implied_by_string_position_swaps(change_descriptions, net))
    return [c for c in change_descriptions if !any(d -> d === c, doomed)]
end

# --- rule application -------------------------------------------------------
#
# Applying a rule turns it into a list of TRANSFORMS — one dimension of one
# image becoming something else — and runs them against the string's images.
# Nothing in the workspace changes: what changes is what the string LOOKS like
# under the rule, which is exactly what has to be computed before anyone can
# ask whether the rule works.
#
# A transform is `[dimension, descriptor]`, or `[GroupCtgy, Opposite,
# bond-facet]` for a group reversal, which needs to know which medium it is
# reversing. An object-transform pair is `[object, transform]`, and a
# string-position swap is `[StrPosCtgy, object1, object2]` — told apart from an
# object-transform pair by whether its first element is that slipnode.

"""Thrown to abandon a rule application; `apply-rule` catches it and answers
`nothing`, the Scheme's `#f`."""
struct RuleApplicationAborted <: Exception end

"""`ignore-snag` — the failure action that does not care why."""
ignore_snag(failure_result) = :done

"""`(get-reference-objects rule-clause)` — the objects a clause is about. A
verbatim clause is about none."""
get_reference_objects(s::WorkspaceString, rc::RuleClause, net::Slipnet) =
    is_verbatim_clause(rc) ? Any[] :
    Any[o for od in rc.object_descriptions
        for o in get_object_description_ref_objects(s, od, net)]

"""`(generate-image-letters)` — the string's image, flattened to letters."""
generate_image_letters(s::WorkspaceString) = Node[n for n in flatten_nodes(generate(get_image(s)))]

flatten_nodes(x) = x isa Node ? Node[x] : Node[n for e in x for n in flatten_nodes(e)]

"""`(StrPosCtgy-transforms object1 object2)` — a swap transform plus the two
object-transform pairs that record each object's new position descriptor."""
strposctgy_transforms(object1, object2, net::Slipnet) = Any[
    Any[net[:plato_string_position_category], object1, object2],
    Any[object1, Any[net[:plato_string_position_category],
                     get_descriptor_for(object2,
                                        net[:plato_string_position_category])]],
    Any[object2, Any[net[:plato_string_position_category],
                     get_descriptor_for(object1,
                                        net[:plato_string_position_category])]]]

"""`(get-dimension-transforms denoted-objects fail)`."""
function get_dimension_transforms(denoted_objects, dimension::Node, net::Slipnet, fail)
    if dimension === net[:plato_string_position_category]
        length(denoted_objects) > 2 && fail(denoted_objects, dimension)
        return strposctgy_transforms(denoted_objects[1], denoted_objects[2], net)
    end
    # A Length swap on a group with no Length description attaches one, since
    # attempting the swap amounts to noticing the group's length. A letter gets
    # `one` back without any description being attached.
    descriptors = Union{Nothing,Node}[]
    for object in denoted_objects
        if dimension !== net[:plato_length]
            push!(descriptors, get_descriptor_for(object, dimension))
        elseif object isa Letter
            push!(descriptors, net[:plato_one])
        elseif description_type_present(object, net[:plato_length])
            push!(descriptors, get_descriptor_for(object, net[:plato_length]))
        else
            attach_length_description!(object::Group, net)
            push!(descriptors, get_descriptor_for(object, net[:plato_length]))
        end
    end
    all(d -> d !== nothing, descriptors) || fail(denoted_objects, dimension)
    # remq-duplicates keeps the LAST of each duplicate group
    swap_descriptors = Node[d for (i, d) in enumerate(descriptors)
                            if !any(x -> x === d, descriptors[(i + 1):end])]
    length(swap_descriptors) > 2 && fail(denoted_objects, dimension)
    d1 = swap_descriptors[1]
    d2 = length(swap_descriptors) == 1 ? swap_descriptors[1] : swap_descriptors[2]
    return Any[Any[object, Any[dimension, descriptor === d1 ? d2 : d1]]
               for (object, descriptor) in zip(denoted_objects, descriptors)]
end

"""`(get-extrinsic-transforms rule string fail)`. A clause naming ONE object
swaps among that object's constituents; a clause naming several swaps among
those."""
function get_extrinsic_transforms(r::Rule, s::WorkspaceString, net::Slipnet, fail)
    result = Any[]
    for rc in r.extrinsic_rule_clauses
        reference_objects = get_reference_objects(s, rc, net)
        denoted_objects = length(rc.object_descriptions) == 1 ?
            Any[o for ref in reference_objects for o in get_constituent_objects(ref)] :
            reference_objects
        length(denoted_objects) < 2 && continue
        if !pairwise_andmap(disjoint_objects, denoted_objects)
            fail(denoted_objects, rc.dimensions[1])
        end
        for dimension in rc.dimensions
            append!(result,
                    get_dimension_transforms(denoted_objects, dimension, net, fail))
        end
    end
    return result
end

"""`(get-intrinsic-transforms rule string)` — a reference object is what the
clause names; a denoted object is the reference object itself (`self`) or each
of its constituents (`subobjects`)."""
function get_intrinsic_transforms(r::Rule, s::WorkspaceString, net::Slipnet)
    result = Any[]
    for rc in r.intrinsic_rule_clauses
        ref_objects = get_reference_objects(s, rc, net)
        self_transforms = Any[Any[c.dimension, c.descriptor] for c in rc.changes
                              if c.scope === :self]
        subobject_transforms = Any[Any[c.dimension, c.descriptor] for c in rc.changes
                                   if c.scope === :subobjects]
        for (o, t) in cross_product(ref_objects, self_transforms)
            push!(result, Any[o, t])
        end
        if !isempty(subobject_transforms)
            all_subobjects = Any[o for ref in ref_objects
                                 for o in get_constituent_objects(ref)]
            for (o, t) in cross_product(all_subobjects, subobject_transforms)
                push!(result, Any[o, t])
            end
        end
    end
    return result
end

"""`(check-for-conflicts object-transform-pairs fail)` — two transforms of one
rule that say incompatible things about the same object."""
function check_for_conflicts(object_transform_pairs, net::Slipnet, fail)
    cds = IntrinsicChangeDescription[
        make_intrinsic_change_description(ot[1], :self, ot[2][1], nothing, nothing,
                                          ot[2][2])
        for ot in object_transform_pairs]
    # `fail` escapes, so WHICH conflicting pair is reported depends on the order
    # `pairwise-map` gets round to them — see `pairwise_apply_order`.
    for (i, j) in pairwise_apply_order(length(cds))
        if change_conflicts(cds[i], cds[j], net)
            fail(cds[i].reference_object, cds[i].dimension,
                 cds[j].reference_object, cds[j].dimension)
        end
    end
    return :done
end

"""`(apply-before? platonic-image-length)` — the order transforms have to run
in. Deliberately NOT a transitive relation, so which order it actually produces
depends on the sort algorithm; `chez_sort` is Chez's, exactly."""
apply_before(platonic_image_length::Union{Nothing,Node}, net::Slipnet) =
    (t1, t2) ->
        t1[1] === net[:plato_group_category] ||
        t1[2] === net[:plato_letter] ||
        (t1[1] === net[:plato_length] &&
         change_length_first(t1[2], platonic_image_length, net)) ||
        (t2[1] === net[:plato_length] &&
         !change_length_first(t2[2], platonic_image_length, net))

"""`(transform-image image transform fail)`.

A BondFacet "transform" has no effect of its own: it rides along with a
GroupCtgy reversal to say which medium — letter categories or lengths — is
being reversed, so that the information survives abstraction. StrPosCtgy swaps
are handled separately, after everything else."""
function transform_image(image, transform, net::Slipnet, fail)
    dimension = transform[1]
    descriptor = transform[2]
    n = dimension.name
    if n === :plato_object_category
        return descriptor === net[:plato_letter] ? letter!(image, net, fail) :
                                                   group!(image, net, fail)
    elseif n === :plato_letter_category
        return new_start_letter!(image, descriptor, net, fail)
    elseif n === :plato_length
        return new_length!(image, descriptor, net, fail)
    elseif n === :plato_direction_category
        return reverse_direction!(image, net, fail)
    elseif n === :plato_group_category
        return reverse_medium!(image, transform[3], net, fail)
    elseif n === :plato_alphabetic_position_category
        return new_alpha_position_category!(image, descriptor, net, fail)
    end
    # plato-bond-facet and plato-string-position-category: nothing to do.
    return :done
end

"""`(apply-transforms transforms image fail)`."""
function apply_transforms(transforms, image, net::Slipnet, fail)
    ordered = chez_sort(apply_before(get_length(image, net), net), transforms)
    for transform in ordered
        if transform[1] === net[:plato_group_category]
            i = findfirst(t -> t[1] === net[:plato_bond_facet], transforms)
            medium = transforms[i][2]
            augmented = Any[net[:plato_group_category], net[:plato_opposite], medium]
            transform_image(image, augmented, net, fail(augmented))
        else
            transform_image(image, transform, net, fail(transform))
        end
    end
    return :done
end

"""`(apply-string-position-swap object1 object2)` — the two images trade states
outright, and each remembers the other so that the answer can be read back."""
function apply_string_position_swap(object1, object2)
    image1 = get_image(object1)
    image2 = get_image(object2)
    state1 = get_state(image1)
    state2 = get_state(image2)
    new_state!(image1, state2)
    new_state!(image2, state1)
    image1.swapped_image = image2
    image2.swapped_image = image1
    return :done
end

"""`(apply-rule rule string failure-action)` — returns the transforms grouped by
object, `Any[]` for a verbatim rule, or `nothing` when the rule cannot be
applied. Deepest objects are transformed first, so that a group's own change
sees its subobjects already changed."""
function apply_rule(r::Rule, s::WorkspaceString, net::Slipnet, failure_action)
    if is_verbatim_rule(r)
        new_appearance!(get_image(s), get_verbatim_letter_categories(r), net)
        return Any[]
    end
    try
        reset_image!(get_image(s))
        swap_fail = (objects, dimension) -> begin
            failure_action(Any[:SWAP, objects, dimension])
            throw(RuleApplicationAborted())
        end
        extrinsic_transforms = get_extrinsic_transforms(r, s, net, swap_fail)
        string_position_swaps =
            Any[x for x in extrinsic_transforms
                if x[1] === net[:plato_string_position_category]]
        extrinsic_pairs = Any[x for x in extrinsic_transforms
                              if !any(y -> y === x, string_position_swaps)]
        intrinsic_pairs = get_intrinsic_transforms(r, s, net)
        all_pairs = vcat(extrinsic_pairs, intrinsic_pairs)
        check_for_conflicts(all_pairs, net,
                            (o1, d1, o2, d2) -> begin
                                failure_action(Any[:CONFLICT, o1, d1, o2, d2])
                                throw(RuleApplicationAborted())
                            end)
        grouped = Any[Any[cls[1][1], Any[ot[2] for ot in cls]]
                      for cls in spartition((ot1, ot2) -> ot1[1] === ot2[1], all_pairs)]
        grouped = chez_sort((l1, l2) -> nesting_level(l1[1]) > nesting_level(l2[1]),
                            grouped)
        for l in grouped
            object = l[1]
            transforms = l[2]
            fail = transform -> () -> begin
                failure_action(Any[:CHANGE, object, transform])
                throw(RuleApplicationAborted())
            end
            apply_transforms(transforms, get_image(object), net, fail)
        end
        for swap in string_position_swaps
            apply_string_position_swap(swap[2], swap[3])
        end
        return grouped
    catch e
        e isa RuleApplicationAborted && return nothing
        rethrow()
    end
end

# --- rule abstraction -------------------------------------------------------
#
# See section 3.3.6 of Marshall's thesis. A rule is not composed; it is READ
# OFF the horizontal bridges the model has already built between the initial
# string and the modified one. Each bridge's slippages become intrinsic change
# descriptions; bridges that trade a descriptor between them become extrinsic
# ones; and changes shared by every bridge of a cluster are lifted into a single
# statement about the enclosing object's subobjects. What survives is turned
# into rule-clause TEMPLATES, which hold reference objects and lists of possible
# descriptors, and only then instantiated into a rule — that last step is where
# the model chooses how to describe each object and which descriptor to use.

"""`(rule-describable-bridge? bridge)` — whether the change from object1 to
object2 is expressible at all.

A letter can turn directly only into a letter-category sameness group; a group
turns into a letter only if it is built on letter categories; and two groups
must share a bond facet and have related group categories."""
function rule_describable_bridge(b::Bridge, net::Slipnet)
    o1 = b.object1
    o2 = b.object2
    o1 isa Letter && o2 isa Letter && return true
    o1 isa Letter && o2 isa Group &&
        return (o2::Group).group_bond_facet === net[:plato_letter_category] &&
               (o2::Group).group_category === net[:plato_samegrp]
    o1 isa Group && o2 isa Letter &&
        return (o1::Group).group_bond_facet === net[:plato_letter_category]
    return (o1::Group).group_bond_facet === (o2::Group).group_bond_facet &&
           related((o1::Group).group_category, (o2::Group).group_category)
end

# --- schemas ---------------------------------------------------------------
#
# <schema> ::= (<dimension> <descriptor1> <relation> <descriptor2>), with `nothing`
# wherever the bridges of a cluster do not agree. `(Length two Identity two)` for
# [aa]-->[bb]; `(ObjCtgy letter nothing group)` for a-->[bb].

struct Schema
    dimension::Node
    descriptor1::Union{Nothing,Node}
    relation::Union{Nothing,Node}
    descriptor2::Union{Nothing,Node}
end

"""`(concept-mappings->schema cms)` — `nothing` unless the mappings agree on a
relation or on where they land."""
function concept_mappings_to_schema(cms)
    common(f) = (vals = [f(cm) for cm in cms];
                 all(v -> v === vals[1], vals) ? vals[1] : nothing)
    relation = common(cm -> cm.label)
    descriptor2 = common(cm -> cm.descriptor2)
    (relation === nothing && descriptor2 === nothing) && return nothing
    return Schema(cm_type(cms[1]), common(cm -> cm.descriptor1), relation, descriptor2)
end

"""`(get-common-schemas cluster)` — one schema per dimension that EVERY bridge
in the cluster maps."""
function get_common_schemas(cluster)
    num_bridges = length(cluster)
    all_cms = ConceptMapping[cm for b in cluster for cm in b.concept_mappings]
    classes = spartition((cm1, cm2) -> cm_type(cm1) === cm_type(cm2), all_cms)
    result = Schema[]
    for p in classes
        length(p) < num_bridges && continue
        sch = concept_mappings_to_schema(p)
        sch === nothing || push!(result, sch::Schema)
    end
    return result
end

"""`(get-common-change-schemas cluster)` — the common schemas that actually say
something changed."""
get_common_change_schemas(cluster, net::Slipnet) =
    Schema[s for s in get_common_schemas(cluster) if s.relation !== net[:plato_identity]]

format_schema(s::Schema) =
    string(s.dimension.short_name, " : ",
           s.descriptor1 === nothing ? "*" : (s.descriptor1::Node).short_name, " ",
           s.relation === nothing ? "*" : (s.relation::Node).short_name, " ",
           s.descriptor2 === nothing ? "*" : (s.descriptor2::Node).short_name)

# --- swaps -----------------------------------------------------------------
#
# <swap> ::= ((<object> ...) <dimension> (<descriptor> <descriptor>))

struct Swap
    objects::Vector{Any}
    dimension::Node
    descriptors::Vector{Node}
end

"""`(slippages->swap slippages)` — a set of slippages in one dimension is a SWAP
when what they come from is exactly what they go to, and there are two of
them."""
function slippages_to_swap(slippages)
    dedup(xs) = Node[x for (i, x) in enumerate(xs) if !any(y -> y === x, xs[(i + 1):end])]
    from = dedup(Node[s.descriptor1 for s in slippages])
    to = dedup(Node[s.descriptor2 for s in slippages])
    (sets_equal(from, to) && length(from) == 2) || return nothing
    return Swap(Any[s.object1 for s in slippages], cm_type(slippages[1]), from)
end

"""`(get-all-swaps cluster)`."""
function get_all_swaps(cluster)
    all_slippages = ConceptMapping[cm for b in cluster
                                   for cm in get_non_symmetric_non_bond_slippages(b)]
    result = Swap[]
    for p in spartition((s1, s2) -> cm_type(s1) === cm_type(s2), all_slippages)
        sw = slippages_to_swap(p)
        sw === nothing || push!(result, sw::Swap)
    end
    return result
end

select_swap(dimension::Node, swaps) =
    (i = findfirst(s -> s.dimension === dimension, swaps);
     i === nothing ? nothing : swaps[i])

# --- the clusters ----------------------------------------------------------

all_subobjects_describable(object, description_type::Node,
                           descriptor::Union{Nothing,Node}) =
    descriptor !== nothing &&
    all(o -> get_descriptor_for(o, description_type) === descriptor,
        get_constituent_objects(object))

same_left_enclosing_objects(b1::Bridge, b2::Bridge) =
    enclosing_group1(b1) === enclosing_group1(b2)
disjoint_left_objects(b1::Bridge, b2::Bridge) =
    disjoint_objects(b1.object1, b2.object1)
common_right_enclosing_object(bridges) =
    all_same(Any[enclosing_group2(b) for b in bridges])
get_left_enclosing_object(bridges) = get_enclosing_object(bridges[1].object1)
get_right_enclosing_object(bridges) = get_enclosing_object(bridges[1].object2)

"""`(spans-left-side? bridges)` — the cluster's left objects are exactly the
constituents of their enclosing object."""
spans_left_side(bridges) =
    sets_equal(Any[b.object1 for b in bridges],
               get_constituent_objects(get_left_enclosing_object(bridges)))
spans_right_side(bridges) =
    sets_equal(Any[b.object2 for b in bridges],
               get_constituent_objects(get_right_enclosing_object(bridges)))

const SWAP_ABSTRACTION_PROBABILITY = 0.75
const SUBOBJECTS_ABSTRACTION_PROBABILITY = 0.75

"""`(abstract-change-descriptions bridges)` — read a set of change descriptions
off the horizontal bridges. Stochastic throughout: which swaps get abstracted,
whether a swap is recorded as a swap of some object's subobjects, and whether a
change common to a whole cluster is lifted."""
function abstract_change_descriptions(bridges, rng::PyRandom, net::Slipnet)
    all_cds = ChangeDescription[]
    function add_extrinsic!(objects, dim::Node, descs::Vector{Node},
                            abstraction_possible::Bool)
        cd = make_extrinsic_change_description(objects, dim, descs)
        abstraction_possible && mark_as_subobjects_swap_if_possible!(cd)
        pushfirst!(all_cds, cd)
        return :done
    end
    function add_intrinsic!(object, scope::Symbol, dim::Node,
                            desc1::Union{Nothing,Node}, relation::Union{Nothing,Node},
                            desc2::Union{Nothing,Node})
        # Individual string-position changes are not allowed; only a swap can
        # say that something moved.
        if dim !== net[:plato_string_position_category]
            pushfirst!(all_cds, make_intrinsic_change_description(object, scope, dim,
                                                                  desc1, relation, desc2))
        end
        return :done
    end
    for b in bridges, slippage in get_non_symmetric_non_bond_slippages(b)
        add_intrinsic!(b.object1, :self, cm_type(slippage), slippage.descriptor1,
                       slippage.label, slippage.descriptor2)
    end
    swaps_partition = isempty(bridges) ? Vector{Any}[] :
        bounded_random_partition(rng, disjoint_left_objects, bridges,
                                 random_int(rng, length(bridges)) + 1)
    for cluster in swaps_partition
        all_swaps = get_all_swaps(cluster)
        length_swap = select_swap(net[:plato_length], all_swaps)
        objctgy_swap = select_swap(net[:plato_object_category], all_swaps)
        remaining = Swap[s for s in all_swaps
                         if !(s === length_swap) && !(s === objctgy_swap)]
        # Length and ObjCtgy swaps go in together or not at all, which keeps the
        # resulting rule clause uniform.
        if stochastic_if(rng, SWAP_ABSTRACTION_PROBABILITY)
            abstract_subobjects = prob(rng, SUBOBJECTS_ABSTRACTION_PROBABILITY)
            if length_swap !== nothing
                add_extrinsic!((length_swap::Swap).objects, net[:plato_length],
                               (length_swap::Swap).descriptors, abstract_subobjects)
            end
            if objctgy_swap !== nothing
                add_extrinsic!((objctgy_swap::Swap).objects, net[:plato_object_category],
                               (objctgy_swap::Swap).descriptors, abstract_subobjects)
            end
        end
        for swap in remaining
            if stochastic_if(rng, SWAP_ABSTRACTION_PROBABILITY)
                add_extrinsic!(swap.objects, swap.dimension, swap.descriptors,
                               prob(rng, SUBOBJECTS_ABSTRACTION_PROBABILITY))
            end
        end
    end
    for cluster in spartition(same_left_enclosing_objects, bridges)
        left_enclosing = get_left_enclosing_object(cluster)
        singleton_group(left_enclosing) && continue
        # Two StrPosCtgy:Opposite slippages across a cluster that spans its
        # enclosing object mean the whole thing turned round.
        if spans_left_side(cluster) &&
           count(b -> strposctgy_opposite_slippage(b, net), cluster) == 2
            if stochastic_if(rng, SUBOBJECTS_ABSTRACTION_PROBABILITY)
                add_intrinsic!(left_enclosing, :self, net[:plato_direction_category],
                               nothing, net[:plato_opposite], nothing)
            end
        end
        for schema in get_common_change_schemas(cluster, net)
            liftable =
                (spans_left_side(cluster) && !common_right_enclosing_object(cluster)) ||
                (spans_left_side(cluster) && common_right_enclosing_object(cluster) &&
                 spans_right_side(cluster)) ||
                (spans_left_side(cluster) && common_right_enclosing_object(cluster) &&
                 all_subobjects_describable(get_right_enclosing_object(cluster),
                                            schema.dimension, schema.descriptor2)) ||
                (common_right_enclosing_object(cluster) && spans_right_side(cluster) &&
                 all_subobjects_describable(left_enclosing, schema.dimension,
                                            schema.descriptor1))
            if liftable && stochastic_if(rng, SUBOBJECTS_ABSTRACTION_PROBABILITY)
                add_intrinsic!(left_enclosing, :subobjects, schema.dimension,
                               schema.descriptor1, schema.relation, schema.descriptor2)
            end
        end
    end
    return all_cds
end

# --- templates -------------------------------------------------------------
#
# A TEMPLATE is a rule clause with the choices not yet made: it holds the
# reference OBJECTS rather than descriptions of them, and a list of possible
# descriptors rather than one. Instantiating it is what commits the model to a
# particular way of saying the same thing.

struct ChangeTemplate
    scope::Symbol
    dimension::Node
    descriptors::Vector{Node}
end

struct RuleClauseTemplate
    kind::Symbol                 # :intrinsic | :extrinsic
    ref_object::Any              # :intrinsic
    change_templates::Vector{ChangeTemplate}
    ref_objects::Vector{Any}     # :extrinsic
    dimensions::Vector{Node}
end

is_intrinsic_template(t::RuleClauseTemplate) = t.kind === :intrinsic
is_extrinsic_template(t::RuleClauseTemplate) = t.kind === :extrinsic

"""`(make-change-template)` — a literal DirCtgy or GroupCtgy change makes no
sense (there is no such thing as "DirCtgy:left"), so those keep only the
relation."""
make_change_template(ic::IntrinsicChangeDescription, net::Slipnet) =
    (ic.dimension === net[:plato_direction_category] ||
     ic.dimension === net[:plato_group_category]) ?
    ChangeTemplate(ic.scope, ic.dimension,
                   Node[d for d in ic.descriptors if d !== ic.descriptor2]) :
    ChangeTemplate(ic.scope, ic.dimension, copy(ic.descriptors))

"""`(get-BondFacet-change)` — a group-category reversal carries the medium it
reverses along with it, so that the information survives abstraction."""
get_bond_facet_change(ic::IntrinsicChangeDescription, net::Slipnet) =
    (ic.reference_object isa Group && ic.dimension === net[:plato_group_category] &&
     ic.scope === :self) ?
    ChangeTemplate(:self, net[:plato_bond_facet],
                   Node[get_bond_facet(ic.reference_object::Group, net)::Node]) :
    nothing

"""The predicate `rule-scout` partitions the surviving change descriptions by:
same kind, and about the same objects. `&&` short-circuits, so the mixed case
never reaches `same_reference_objects`, which has no method for it — exactly as
the Scheme's `same-change-type?` guards its `same-reference-objects?`."""
change_descriptions_groupable(c1::ChangeDescription, c2::ChangeDescription) =
    is_intrinsic_change(c1) == is_intrinsic_change(c2) &&
    same_reference_objects(c1, c2)

"""`(change-descriptions->rule-clause-template change-descriptions)`."""
function change_descriptions_to_rule_clause_template(cds, net::Slipnet)
    if cds[1] isa IntrinsicChangeDescription
        first = cds[1]::IntrinsicChangeDescription
        templates = ChangeTemplate[make_change_template(c::IntrinsicChangeDescription,
                                                        net) for c in cds]
        bond_facet_change = get_bond_facet_change(first, net)
        bond_facet_change === nothing ||
            pushfirst!(templates, bond_facet_change::ChangeTemplate)
        return RuleClauseTemplate(:intrinsic, first.reference_object, templates,
                                  Any[], Node[])
    end
    first = cds[1]::ExtrinsicChangeDescription
    objects = any(c -> (c::ExtrinsicChangeDescription).subobjects_swap, cds) ?
        Any[get_change_enclosing_object(first)] :
        chez_sort((a, b) -> left_string_pos(a) < left_string_pos(b),
                  first.reference_objects)
    return RuleClauseTemplate(:extrinsic, nothing, ChangeTemplate[], objects,
                              Node[(c::ExtrinsicChangeDescription).dimension
                                   for c in cds])
end

"""`(sort-templates rule-clause-templates)` — intrinsic clauses before
extrinsic, wider swaps first, and intrinsic clauses by nesting then string
position. Another comparator that is not a strict weak ordering."""
sort_templates(templates) =
    chez_sort((t1, t2) ->
                  (is_intrinsic_template(t1) && is_extrinsic_template(t2)) ||
                  (is_extrinsic_template(t1) && is_extrinsic_template(t2) &&
                   length(t1.dimensions) > length(t2.dimensions)) ||
                  (is_intrinsic_template(t1) && is_intrinsic_template(t2) &&
                   (nested_member(t2.ref_object, t1.ref_object) ||
                    (disjoint_objects(t1.ref_object, t2.ref_object) &&
                     left_string_pos(t1.ref_object) < left_string_pos(t2.ref_object)))),
              templates)

const RULE_DIMENSION_ORDER_NAMES =
    (:plato_direction_category, :plato_group_category,
     :plato_alphabetic_position_category, :plato_letter_category, :plato_length,
     :plato_object_category, :plato_string_position_category, :plato_bond_facet)

rule_dimension_order(net::Slipnet) = Node[net[n] for n in RULE_DIMENSION_ORDER_NAMES]

sort_rule_dimensions(dimensions, net::Slipnet) =
    sort_wrt_order(dimensions, rule_dimension_order(net))

"""`(sort-change-templates change-templates)` — self before subobjects, then by
the fixed dimension order."""
function sort_change_templates(change_templates, net::Slipnet)
    order = rule_dimension_order(net)
    return chez_sort((ct1, ct2) ->
                         (ct1.scope === :self && ct2.scope === :subobjects) ||
                         (ct1.scope === ct2.scope &&
                          list_index(order, ct1.dimension) <
                          list_index(order, ct2.dimension)),
                     change_templates)
end

object_description_possible(object, net::Slipnet) =
    object isa WorkspaceString ||
    !isempty(get_descriptions_for_rule(object::WSObject, net))

"""`(possible-to-instantiate? templates)` — every object the templates name has
to be describable, or there is no rule to write."""
possible_to_instantiate(templates, net::Slipnet) =
    all(t -> is_intrinsic_template(t) ?
             object_description_possible(t.ref_object, net) :
             all(o -> object_description_possible(o, net), t.ref_objects),
        templates)

"""`(reference-object->object-description object)` — choose how to name it."""
function reference_object_to_object_description(object, rng::PyRandom, net::Slipnet)
    object isa WorkspaceString &&
        return ObjectDescription(:string, net[:plato_string_position_category],
                                 net[:plato_whole])
    chosen = choose_description_for_rule(rng, object::WSObject, net)
    return ObjectDescription(get_descriptor_for(object::WSObject,
                                                net[:plato_object_category]),
                             (chosen::Description).description_type,
                             (chosen::Description).descriptor)
end

"""`(instantiate-change-template object-description)` — pick a descriptor by
conceptual depth.

The last clause avoids rules like "change letter-category of the object with
letter-category `c' to successor" by substituting the literal `d` for the
relation."""
function instantiate_change_template(ct::ChangeTemplate, od::ObjectDescription,
                                     rng::PyRandom, net::Slipnet)
    chosen = stochastic_pick(rng, ct.descriptors,
                             temp_adjusted_values([d.conceptual_depth
                                                   for d in ct.descriptors]))
    descriptor = (ct.dimension === od.description_type &&
                  platonic_relation(chosen, net)) ?
                 get_related_node(od.descriptor, chosen, net[:plato_identity]) : chosen
    return Change(ct.scope, ct.dimension, descriptor)
end

"""`(instantiate-rule-clause-template template)`."""
function instantiate_rule_clause_template(t::RuleClauseTemplate, rng::PyRandom,
                                          net::Slipnet)
    # Both `map`s here draw — `instantiate-change-template` picks a descriptor
    # and `reference-object->object-description` picks a description — so they
    # go through `chez_map`, which applies in Chez's order rather than left to
    # right. Same draws either way; different picks.
    if is_intrinsic_template(t)
        od = reference_object_to_object_description(t.ref_object, rng, net)
        changes = Change[chez_map(ct -> instantiate_change_template(ct, od, rng, net),
                                  sort_change_templates(t.change_templates, net))...]
        return intrinsic_clause(od, changes)
    end
    sorted = chez_sort((a, b) -> left_string_pos(a) < left_string_pos(b), t.ref_objects)
    return extrinsic_clause(
        ObjectDescription[chez_map(o -> reference_object_to_object_description(o, rng,
                                                                               net),
                                   sorted)...],
        sort_rule_dimensions(t.dimensions, net))
end

# --- what a rule rests on ---------------------------------------------------
#
# A rule abstracted from bridges is only as good as the bridges under it, and
# those can be broken by other codelets at any time. Each rule therefore
# remembers which horizontal bridges support it, TAGGED with whether the support
# is provisional: a template that changes an object which has no bridge of its
# own falls back on its subobjects' bridges, and the tag says so, so that the
# support can be revised upward if that object's own bridge appears later.

unsupported_self_change(tagged) = tagged[1]::Bool
tagged_bridges(tagged) = tagged[2]::Vector{Bridge}

"""`(get-tagged-supporting-horizontal-bridges rule-clause-template)`."""
function get_tagged_supporting_horizontal_bridges(t::RuleClauseTemplate)
    if is_extrinsic_template(t)
        bridges = length(t.ref_objects) == 1 ?
            get_subobject_bridges(t.ref_objects[1], :horizontal) :
            Bridge[get_bridge(o, :horizontal) for o in t.ref_objects]
        return Any[false, bridges]
    end
    self_bridge = t.ref_object isa WorkspaceString ? nothing :
                  get_bridge(t.ref_object::WSObject, :horizontal)
    subobject_bridges = any(ct -> ct.scope === :subobjects, t.change_templates) ?
        get_subobject_bridges(t.ref_object, :horizontal) : Bridge[]
    change_self = any(ct -> ct.scope === :self, t.change_templates)
    supporting = !change_self ? subobject_bridges :
        self_bridge !== nothing ? vcat(Bridge[self_bridge::Bridge], subobject_bridges) :
        get_subobject_bridges(t.ref_object, :horizontal)
    return Any[change_self && self_bridge === nothing, supporting]
end

"""`(set-abstracted-rule-information templates)` — record what the rule rests
on, attach a Length description to any group whose bridge slips length (the
rule is about to talk about that length), and take a snapshot of the dominant
themes."""
function set_abstracted_rule_information!(r::Rule, templates, ctx)
    net = ctx.net
    r.rule_clause_templates = collect(templates)
    r.tagged_supporting_horizontal_bridges =
        Any[get_tagged_supporting_horizontal_bridges(t) for t in templates]
    r.supporting_horizontal_bridges =
        Bridge[b for tagged in r.tagged_supporting_horizontal_bridges
               for b in tagged_bridges(tagged)]
    for bridge in r.supporting_horizontal_bridges
        slippage_type_present(bridge, net[:plato_length]) || continue
        for o in (bridge.object1, bridge.object2)
            if o isa Group && !description_type_present(o, net[:plato_length])
                attach_length_description!(o::Group, net)
            end
        end
    end
    r.theme_pattern = get_dominant_theme_pattern(ctx.themespace, r.bridge_theme_type)
    return r
end

"""`(set-verbatim-rule-information)` — a verbatim rule rests on nothing."""
function set_verbatim_rule_information!(r::Rule)
    r.rule_clause_templates = RuleClauseTemplate[]
    r.tagged_supporting_horizontal_bridges = Any[]
    r.supporting_horizontal_bridges = Bridge[]
    r.theme_pattern = Any[r.bridge_theme_type]
    return r
end

"""`(revise-abstracted-rule-information proposed-rule)` — an existing rule that
a new proposal duplicates takes the proposal's support where its own was only
provisional."""
function revise_abstracted_rule_information!(r::Rule, proposed::Rule)
    if any(unsupported_self_change, r.tagged_supporting_horizontal_bridges)
        r.tagged_supporting_horizontal_bridges =
            Any[(unsupported_self_change(old) && !unsupported_self_change(new)) ?
                new : old
                for (old, new) in zip(r.tagged_supporting_horizontal_bridges,
                                      proposed.tagged_supporting_horizontal_bridges)]
        all_bridges = Bridge[b for tagged in r.tagged_supporting_horizontal_bridges
                             for b in tagged_bridges(tagged)]
        # remq-duplicates keeps the LAST of each duplicate group
        r.supporting_horizontal_bridges =
            Bridge[b for (i, b) in enumerate(all_bridges)
                   if !any(x -> x === b, all_bridges[(i + 1):end])]
    end
    r.theme_pattern = proposed.theme_pattern
    return r
end

"""`(supported?)` — every bridge the rule rests on is still in the workspace."""
rule_supported(r::Rule, ctx) =
    all(b -> bridge_present(ctx, b), r.supporting_horizontal_bridges)

"""`(get-degree-of-support)` — the product of the supporting bridges'
strengths, as a percentage of a percentage."""
get_degree_of_support(r::Rule, ctx) =
    mul100(prod([pct(get_equivalent_bridge(ctx, b).strength)
                 for b in r.supporting_horizontal_bridges]; init = 1))

"""`(get-relative-quality)` — a rule is ranked against the other rules of its
type rather than judged absolutely, so the best rule in the workspace is always
worth 100."""
function get_relative_quality(r::Rule, ctx)
    ranked = chez_sort((r1, r2) -> r1.quality < r2.quality, get_rules(ctx, r.rule_type))
    i = findfirst(x -> x === r, ranked)
    return i === nothing ? r.quality : mul100(sdiv(i, length(ranked)))
end

calculate_internal_strength(r::Rule, ctx) = get_relative_quality(r, ctx)
calculate_external_strength(r::Rule, ctx) = calculate_internal_strength(r, ctx)

"""`(update-strength)` for a rule. A rule is one of the structures with no
thematic compatibility of its own — it takes the `workspace-structure` default
of 0 — so its strength reduces to its quality relative to the other rules."""
function update_structure_strength!(r::Rule, ctx)
    TEMPERATURE[] = ctx.temperature
    internal = calculate_internal_strength(r, ctx)
    external = calculate_external_strength(r, ctx)
    intrinsic = weighted_average([internal, external],
                                 [internal, sub_from_100(internal)])
    r.strength = sround(weighted_average([0, intrinsic], [0, 1]))
    return r
end

"""`(currently-works?)` — apply the rule to its own string and see whether what
comes out is the string it is supposed to explain. A BOTTOM rule is checked
against the answer string, which only exists in justify mode; that mode is not
ported, and nothing proposes a bottom rule without it."""
function currently_works(r::Rule, ctx)
    string1 = r.rule_type === :top ? ctx.initial_string : ctx.target_string
    string2 = ctx.modified_string
    result = apply_rule(r, string1, ctx.net, ignore_snag)
    return result !== nothing &&
           generate_image_letters(string1) == string2.letter_categories
end

"""`(activate-rule-descriptors-from-workspace rule)`."""
function activate_rule_descriptors_from_workspace(r::Rule)
    for clause in r.rule_clauses
        is_verbatim_clause(clause) && continue
        for od in clause.object_descriptions
            activate_from_workspace!(od.descriptor)
        end
        if is_intrinsic_clause(clause)
            for c in clause.changes
                activate_from_workspace!(c.descriptor)
            end
        end
    end
    return r
end

# --- the rule codelets ------------------------------------------------------

const VERBATIM_RULE_PROBABILITY = 0.01

"""`rule-scout` — propose a rule.

One time in a hundred it gives up and proposes a VERBATIM rule, which simply
quotes the modified string. Otherwise it abstracts one from the describable
horizontal bridges: read change descriptions off them, drop the redundant ones,
group what is left into rule-clause templates, and instantiate. NB the verbatim
coin is drawn on EVERY run, whether or not it comes up."""
function rule_scout(ctx::MetacatCtx, args::Vector{Any})
    net = ctx.net
    if stochastic_if(ctx.rng, VERBATIM_RULE_PROBABILITY)
        # `%justify-mode%` is off, so the rule type is always `top`.
        rule_type = :top
        letter_categories = ctx.modified_string.letter_categories
        clauses = RuleClause[verbatim_clause(copy(letter_categories))]
        proposed = make_rule(rule_type, clauses, ctx.initial_string, net,
                             ctx.codelet_count)
        set_quality_values!(proposed, net)
        set_verbatim_rule_information!(proposed)
        proposed.proposal_level = PROPOSED
        post!(ctx.coderack,
              make_codelet(CODELET_TYPES[:rule_evaluator], LOW_URGENCY, Any[proposed]),
              ctx.codelet_count, ctx.rng, ctx.temperature)
        return
    end
    possible_rule_types = get_possible_rule_types(ctx)
    isempty(possible_rule_types) && return
    rule_type = random_pick(ctx.rng, possible_rule_types)::Symbol
    describable = Bridge[b for b in get_bridges(ctx, rule_type)
                         if rule_describable_bridge(b, net)]
    all_cds = abstract_change_descriptions(describable, ctx.rng, net)
    final_cds = remove_redundant_change_descriptions(all_cds, net)
    templates = sort_templates(RuleClauseTemplate[
        change_descriptions_to_rule_clause_template(cls, net)
        for cls in spartition(change_descriptions_groupable, final_cds)])
    possible_to_instantiate(templates, net) || return
    clauses = RuleClause[chez_map(t -> instantiate_rule_clause_template(t, ctx.rng, net),
                                  templates)...]
    string1 = rule_type === :top ? ctx.initial_string : ctx.target_string
    proposed = make_rule(rule_type, clauses, string1, net, ctx.codelet_count)
    set_quality_values!(proposed, net)
    set_abstracted_rule_information!(proposed, templates, ctx)
    proposed.proposal_level = PROPOSED
    post!(ctx.coderack,
          make_codelet(CODELET_TYPES[:rule_evaluator], HIGH_URGENCY, Any[proposed]),
          ctx.codelet_count, ctx.rng, ctx.temperature)
    return
end

"""`rule-evaluator` — a rule that does not actually turn the initial string into
the modified one is no rule at all; then the usual strength coin."""
function rule_evaluator(ctx::MetacatCtx, args::Vector{Any})
    proposed = args[1]::Rule
    currently_works(proposed, ctx) || return
    update_structure_strength!(proposed, ctx)
    strength = proposed.strength
    # stochastic-if* on (1- p): fires when the rule is NOT strong enough, and
    # always draws
    coin = random_real(ctx.rng, 1.0)
    coin < sub_from_1(pct(strength)) && return
    proposed.proposal_level = EVALUATED
    post!(ctx.coderack,
          make_codelet(CODELET_TYPES[:rule_builder], HIGH_URGENCY, Any[proposed]),
          ctx.codelet_count, ctx.rng, ctx.temperature)
    return
end

"""`rule-builder` — add it to the workspace, unless an equivalent rule is
already there, in which case the existing one takes over whatever support the
proposal had that it lacked.

Building a rule is what sets the model looking for an answer, so this posts an
`answer-finder`. That codelet is `answers.ss` and is not ported yet: the type
is registered without a procedure, so it can be posted and counted but not
run."""
function rule_builder(ctx::MetacatCtx, args::Vector{Any})
    proposed = args[1]::Rule
    activate_rule_descriptors_from_workspace(proposed)
    equivalent = get_equivalent_rule(ctx, proposed)
    if equivalent !== nothing
        revise_abstracted_rule_information!(equivalent::Rule, proposed)
        return
    end
    proposed.proposal_level = BUILT
    add_rule!(ctx, proposed)
    post!(ctx.coderack,
          make_codelet(CODELET_TYPES[:answer_finder], EXTREMELY_HIGH_URGENCY, Any[]),
          ctx.codelet_count, ctx.rng, ctx.temperature)
    return
end

# `answer-finder` is `answers.ss`, which is not ported. The type is registered
# so that `rule-builder` can post one — the coderack has to hold it and count
# it, and a run that reaches an answer will need it — but running one is an
# error rather than a silent no-op.
register_codelet_type!(:answer_finder,
                       (ctx, args) -> error("answer-finder is not ported yet"))

register_codelet_type!(:rule_scout, rule_scout)
register_codelet_type!(:rule_evaluator, rule_evaluator)
register_codelet_type!(:rule_builder, rule_builder)
