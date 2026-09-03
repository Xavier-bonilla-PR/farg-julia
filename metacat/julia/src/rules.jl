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
                0, 0, 0, 0, 0, codelet_count, 0, 0, nothing)
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
