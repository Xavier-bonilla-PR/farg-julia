# Julia counterpart of metacat/bench/metacat_rules_probe.ss: the rule structure,
# its English transcription, and its quality metrics, driven from hand-written
# rule clauses against a workspace that has bonds and groups in it.
include("../../copycat/julia/src/pyrandom.jl")  # shared MT19937 (Copycat side)
include("../julia/src/schemenum.jl")
include("../julia/src/utilities.jl")
include("../julia/src/slipnet.jl")
include("../julia/src/workspace.jl")
include("../julia/src/concept_mappings.jl")
include("../julia/src/images.jl")
include("../julia/src/bonds.jl")
include("../julia/src/groups.jl")
include("../julia/src/bridges.jl")
include("../julia/src/coderack.jl")
include("../julia/src/themes.jl")
include("../julia/src/context.jl")
include("../julia/src/rules.jl")

nm(n) = n === nothing ? "-" : n.lowercase_name
yn(b) = b ? "y" : "n"
"""Scheme's `~a` on a list of strings."""
slist(xs) = string("(", join(xs, " "), ")")
net = build_slipnet()

function build_bond_chain(s::WorkspaceString)
    result = Any[]
    for p in 1:(string_length(s) - 1)
        o1 = s.letters[p]; o2 = s.letters[p + 1]
        d1 = get_descriptor_for(o1, net[:plato_letter_category])::Node
        d2 = get_descriptor_for(o2, net[:plato_letter_category])::Node
        cat = get_bond_category_between(d1, d2, net)
        if cat === nothing
            push!(result, nothing)
        else
            b = make_bond(net, o1, o2, cat::Node, net[:plato_letter_category], d1, d2)
            build_bond!(b, net)
            push!(result, b)
        end
    end
    return result
end

function make_run!(s::WorkspaceString, run_bonds::Vector{Any})
    cat = run_bonds[1].bond_category
    dir = run_bonds[1].direction
    gcat = get_related_node(cat, net[:plato_group_category], net[:plato_identity])::Node
    objs = WSObject[run_bonds[1].left_object]
    for b in run_bonds
        push!(objs, b.right_object)
    end
    g = make_group(net, s, gcat, net[:plato_letter_category], dir,
                   objs[1], objs[end], objs, run_bonds)
    build_group!(g, net)
    return g
end

function build_runs!(s::WorkspaceString, bonds::Vector{Any})
    run = Any[]
    for b in bonds
        if b === nothing
            isempty(run) || make_run!(s, copy(run))
            run = Any[]
        elseif isempty(run) || (b.bond_category === run[1].bond_category &&
                                b.direction === run[1].direction)
            push!(run, b)
        else
            make_run!(s, copy(run))
            run = Any[b]
        end
    end
    isempty(run) || make_run!(s, copy(run))
end

# ------------------------------------ printing ------------------------------------

function print_rule_clause(rc::RuleClause)
    if is_verbatim_clause(rc)
        println("  CLAUSE\tVERBATIM\t",
                join([n.lowercase_name for n in rc.letter_categories]))
    elseif is_intrinsic_clause(rc)
        println("  CLAUSE\tCHANGE\t",
                format_object_description(rc.object_descriptions[1]))
        for c in rc.changes
            println("    CH\t(", c.scope, " ", format_slipnode(c.dimension), " ",
                    format_slipnode(c.descriptor), ")")
        end
    else
        println("  CLAUSE\tSWAP\t",
                join([format_slipnode(d) for d in rc.dimensions], ", "))
        if length(rc.object_descriptions) == 1
            println("    subobjects\t",
                    format_object_description(rc.object_descriptions[1]))
        else
            for od in rc.object_descriptions
                println("    OD\t", format_object_description(od))
            end
        end
    end
end

function print_rule(label, r::Rule)
    println("RULE\t", label, "\t", r.rule_type)
    for rc in r.rule_clauses
        print_rule_clause(rc)
    end
    println("  N\tintrinsic=", length(r.intrinsic_rule_clauses),
            "\textrinsic=", length(r.extrinsic_rule_clauses))
    println("  FLAGS\tidentity=", yn(is_identity_rule(r)),
            "\tverbatim=", yn(is_verbatim_rule(r)),
            "\tliteral=", yn(is_literal_rule(r, net)),
            "\tabstract=", yn(is_abstract_rule(r, net)),
            "\tchar=", rule_characterization(r, net))
    println("  CHARZN\t(", r.rule_type, " ", rule_characterization(r, net), ")")
    for rc in r.rule_clauses
        println("  LITCLAUSE\t", yn(literal_clause(rc, net)))
    end
    set_quality_values!(r, net)
    println("  Q\tunif=", r.uniformity, "\tabst=", r.abstractness,
            "\tsucc=", r.succinctness, "\tintr=", r.intrinsic_quality,
            "\tqual=", r.quality)
    println("  CONCEPTS\t", slist([e[1].short_name for e in get_concept_pattern(r)[2:end]]))
    if is_verbatim_rule(r)
        println("  VERBLETTERS\t",
                slist([n.lowercase_name for n in get_verbatim_letter_categories(r)]))
    end
    for line in r.english_transcription
        println("  EN\t|", line, "|")
    end
end

# ------------------------------------- clauses -------------------------------------

od(object_type, description_type, descriptor) =
    ObjectDescription(object_type, description_type, descriptor)
ch(scope, dimension, descriptor) = Change(scope, dimension, descriptor)
ich(o, cs) = intrinsic_clause(o, Change[cs...])
ech(os, ds) = extrinsic_clause(ObjectDescription[os...], Node[ds...])

const N = net

function clause_table()
    return [
      ("letter-rmost-succ",
       ich(od(N[:plato_letter], N[:plato_string_position_category], N[:plato_rightmost]),
           [ch(:self, N[:plato_letter_category], N[:plato_successor])])),
      ("letter-lmost-literal",
       ich(od(N[:plato_letter], N[:plato_letter_category], N[:plato_a]),
           [ch(:self, N[:plato_letter_category], N[:plato_d])])),
      ("string-subobjs-a",
       ich(od(:string, N[:plato_string_position_category], N[:plato_whole]),
           [ch(:subobjects, N[:plato_letter_category], N[:plato_a])])),
      ("group-whole-dir-opp",
       ich(od(N[:plato_group], N[:plato_string_position_category], N[:plato_whole]),
           [ch(:self, N[:plato_direction_category], N[:plato_opposite])])),
      ("group-whole-grpctgy",
       ich(od(N[:plato_group], N[:plato_string_position_category], N[:plato_whole]),
           [ch(:self, N[:plato_group_category], N[:plato_opposite]),
            ch(:self, N[:plato_bond_facet], N[:plato_letter_category])])),
      ("group-whole-grpctgy-len",
       ich(od(N[:plato_group], N[:plato_string_position_category], N[:plato_whole]),
           [ch(:subobjects, N[:plato_group_category], N[:plato_opposite]),
            ch(:self, N[:plato_bond_facet], N[:plato_length])])),
      ("objctgy-self-letter",
       ich(od(N[:plato_group], N[:plato_string_position_category], N[:plato_rightmost]),
           [ch(:self, N[:plato_object_category], N[:plato_letter]),
            ch(:self, N[:plato_length], N[:plato_one]),
            ch(:self, N[:plato_letter_category], N[:plato_e])])),
      ("objctgy-self-group-rel-len",
       ich(od(N[:plato_group], N[:plato_string_position_category], N[:plato_rightmost]),
           [ch(:self, N[:plato_object_category], N[:plato_group]),
            ch(:self, N[:plato_length], N[:plato_successor])])),
      ("objctgy-self-group-lit-len",
       ich(od(N[:plato_letter], N[:plato_string_position_category], N[:plato_rightmost]),
           [ch(:self, N[:plato_object_category], N[:plato_group]),
            ch(:self, N[:plato_length], N[:plato_three]),
            ch(:self, N[:plato_letter_category], N[:plato_a])])),
      ("objctgy-self-only",
       ich(od(N[:plato_letter], N[:plato_string_position_category], N[:plato_leftmost]),
           [ch(:self, N[:plato_object_category], N[:plato_group]),
            ch(:self, N[:plato_letter_category], N[:plato_x])])),
      ("objsubs-lenself-lensubs-letter",
       ich(od(:string, N[:plato_string_position_category], N[:plato_whole]),
           [ch(:subobjects, N[:plato_object_category], N[:plato_letter]),
            ch(:self, N[:plato_length], N[:plato_successor]),
            ch(:subobjects, N[:plato_length], N[:plato_one]),
            ch(:subobjects, N[:plato_letter_category], N[:plato_successor])])),
      ("objsubs-lenself-lensubs-rel",
       ich(od(:string, N[:plato_string_position_category], N[:plato_whole]),
           [ch(:subobjects, N[:plato_object_category], N[:plato_group]),
            ch(:self, N[:plato_length], N[:plato_three]),
            ch(:subobjects, N[:plato_length], N[:plato_successor])])),
      ("objsubs-lenself-lensubs-lit",
       ich(od(:string, N[:plato_string_position_category], N[:plato_whole]),
           [ch(:subobjects, N[:plato_object_category], N[:plato_group]),
            ch(:self, N[:plato_length], N[:plato_predecessor]),
            ch(:subobjects, N[:plato_length], N[:plato_two]),
            ch(:subobjects, N[:plato_letter_category], N[:plato_o])])),
      ("objsubs-lenself",
       ich(od(:string, N[:plato_string_position_category], N[:plato_whole]),
           [ch(:subobjects, N[:plato_object_category], N[:plato_group]),
            ch(:self, N[:plato_length], N[:plato_four]),
            ch(:subobjects, N[:plato_letter_category], N[:plato_m])])),
      ("objsubs-lensubs-letter",
       ich(od(N[:plato_group], N[:plato_string_position_category], N[:plato_whole]),
           [ch(:subobjects, N[:plato_object_category], N[:plato_letter]),
            ch(:subobjects, N[:plato_length], N[:plato_one])])),
      ("objsubs-lensubs-rel",
       ich(od(N[:plato_group], N[:plato_string_position_category], N[:plato_whole]),
           [ch(:subobjects, N[:plato_object_category], N[:plato_group]),
            ch(:subobjects, N[:plato_length], N[:plato_predecessor])])),
      ("objsubs-lensubs-lit",
       ich(od(N[:plato_group], N[:plato_string_position_category], N[:plato_whole]),
           [ch(:subobjects, N[:plato_object_category], N[:plato_group]),
            ch(:subobjects, N[:plato_length], N[:plato_five]),
            ch(:subobjects, N[:plato_letter_category], N[:plato_i])])),
      ("objsubs-only",
       ich(od(N[:plato_group], N[:plato_string_position_category], N[:plato_whole]),
           [ch(:subobjects, N[:plato_object_category], N[:plato_letter]),
            ch(:subobjects, N[:plato_letter_category], N[:plato_successor])])),
      ("lenself-lensubs",
       ich(od(N[:plato_group], N[:plato_string_position_category], N[:plato_whole]),
           [ch(:self, N[:plato_length], N[:plato_successor]),
            ch(:subobjects, N[:plato_length], N[:plato_predecessor])])),
      ("lenself-only",
       ich(od(N[:plato_group], N[:plato_string_position_category], N[:plato_whole]),
           [ch(:self, N[:plato_length], N[:plato_two])])),
      ("lensubs-only",
       ich(od(N[:plato_group], N[:plato_string_position_category], N[:plato_whole]),
           [ch(:subobjects, N[:plato_length], N[:plato_successor])])),
      ("alphapos-clause",
       ich(od(N[:plato_letter], N[:plato_alphabetic_position_category],
              N[:plato_alphabetic_first]),
           [ch(:self, N[:plato_alphabetic_position_category],
               N[:plato_alphabetic_last])])),
      ("swap-one-od",
       ech([od(:string, N[:plato_string_position_category], N[:plato_whole])],
           [N[:plato_letter_category]])),
      ("swap-two-ods",
       ech([od(N[:plato_letter], N[:plato_string_position_category], N[:plato_leftmost]),
            od(N[:plato_letter], N[:plato_string_position_category], N[:plato_rightmost])],
           [N[:plato_letter_category], N[:plato_length]])),
      ("swap-three-dims",
       ech([od(N[:plato_letter], N[:plato_string_position_category], N[:plato_leftmost]),
            od(N[:plato_group], N[:plato_letter_category], N[:plato_c])],
           [N[:plato_letter_category], N[:plato_length],
            N[:plato_direction_category]])),
      ("verbatim",
       verbatim_clause(Node[N[:plato_a], N[:plato_b], N[:plato_d]])),
      ("objctgy-self-group-nolett",
       ich(od(N[:plato_letter], N[:plato_string_position_category], N[:plato_leftmost]),
           [ch(:self, N[:plato_object_category], N[:plato_group])])),
      ("objctgy-self-letter-nolett",
       ich(od(N[:plato_group], N[:plato_string_position_category], N[:plato_whole]),
           [ch(:self, N[:plato_object_category], N[:plato_letter])])),
      ("objsubs-group-nolett",
       ich(od(N[:plato_group], N[:plato_string_position_category], N[:plato_whole]),
           [ch(:subobjects, N[:plato_object_category], N[:plato_group])])),
      ("objsubs-letter-nolett",
       ich(od(:string, N[:plato_string_position_category], N[:plato_whole]),
           [ch(:subobjects, N[:plato_object_category], N[:plato_letter])])),
      # `c' is not one of the an-letters, so this is the "a `c' group" article
      ("lit-group-article-a",
       ich(od(N[:plato_letter], N[:plato_string_position_category], N[:plato_rightmost]),
           [ch(:self, N[:plato_object_category], N[:plato_group]),
            ch(:self, N[:plato_length], N[:plato_three]),
            ch(:self, N[:plato_letter_category], N[:plato_c])])),
      # a relation Length change keeps the literal LettCtgy change, which then
      # gets a phrase of its own
      ("objctgy-group-rellen-litlett",
       ich(od(N[:plato_letter], N[:plato_string_position_category], N[:plato_rightmost]),
           [ch(:self, N[:plato_object_category], N[:plato_group]),
            ch(:self, N[:plato_length], N[:plato_successor]),
            ch(:self, N[:plato_letter_category], N[:plato_b])])),
      ("strpos-change",
       ich(od(N[:plato_letter], N[:plato_string_position_category], N[:plato_leftmost]),
           [ch(:self, N[:plato_string_position_category], N[:plato_rightmost])])),
      ("groupctgy-descriptor",
       ich(od(N[:plato_group], N[:plato_group_category], N[:plato_samegrp]),
           [ch(:self, N[:plato_direction_category], N[:plato_opposite])])),
      ("long-phrase",
       ich(od(N[:plato_group], N[:plato_string_position_category], N[:plato_rightmost]),
           [ch(:subobjects, N[:plato_alphabetic_position_category],
               N[:plato_alphabetic_last])])),
    ]
end

function rule_specs(table)
    cl(name) = table[findfirst(e -> e[1] == name, table)][2]
    specs = Tuple{String,Vector{RuleClause}}[("identity", RuleClause[])]
    for (name, rc) in table
        push!(specs, (name, RuleClause[rc]))
    end
    append!(specs, [
      ("two-intrinsic-same-dim",
       RuleClause[cl("letter-rmost-succ"),
                  ich(od(N[:plato_letter], N[:plato_string_position_category],
                         N[:plato_leftmost]),
                      [ch(:self, N[:plato_letter_category], N[:plato_predecessor])])]),
      ("two-intrinsic-mixed-abstractness",
       RuleClause[cl("letter-rmost-succ"), cl("letter-lmost-literal")]),
      ("two-intrinsic-mixed-dims",
       RuleClause[cl("letter-rmost-succ"), cl("alphapos-clause")]),
      ("intrinsic-plus-extrinsic",
       RuleClause[cl("letter-rmost-succ"), cl("swap-two-ods")]),
      ("two-extrinsic",
       RuleClause[cl("swap-one-od"), cl("swap-two-ods")]),
      ("three-mixed",
       RuleClause[cl("letter-rmost-succ"), cl("alphapos-clause"),
                  cl("swap-two-ods")]),
    ])
    return specs
end

# -------------------------------------- probe --------------------------------------

function probe(i, m, t)
    println("PROBLEM\t", i, "\t", m, "\t", t)
    foreach(reset!, net.nodes)
    initial = make_workspace_string(net, :initial, i)
    modified = make_workspace_string(net, :modified, m)
    target = make_workspace_string(net, :target, t)
    strings = [initial, modified, target]
    for s in strings
        add_string_position_descriptions_to_letters!(net, s)
    end
    for s in (initial, target)
        build_runs!(s, build_bond_chain(s))
    end
    update_workspace_values!(strings)
    for s in (initial, target)
        println("STRING\t", s.string_type, "\twhole-group=",
                yn(whole_group(s, net) !== nothing), "\tletters=", length(s.letters),
                "\tgroups=", length(s.groups))
    end
    table = clause_table()
    for (name, rc) in table
        is_verbatim_clause(rc) && continue
        for object_description in rc.object_descriptions, s in (initial, target)
            refs = get_object_description_ref_objects(s, object_description, net)
            plural = plural_object_phrase(object_description, s, net)
            println("REF\t", name, "\t", s.string_type, "\t",
                    format_object_description(object_description), "\t", length(refs),
                    "\t", yn(plural), "\t",
                    get_object_phrase(object_description, plural, s, net))
        end
    end
    for (name, clauses) in rule_specs(table), rule_type in (:top, :bottom)
        print_rule(string(name, "/", rule_type),
                   make_rule(rule_type, clauses,
                             rule_type === :top ? initial : target, net))
    end
    specs = rule_specs(table)
    names = [sp[1] for sp in specs]
    rules = [make_rule(:top, sp[2], initial, net) for sp in specs]
    rebuilt = [make_rule(:top, sp[2], initial, net) for sp in rule_specs(clause_table())]
    for k in eachindex(names)
        println("SELFEQ\t", names[k], "\t", yn(rules_equal(rules[k], rebuilt[k], net)))
    end
    for a in eachindex(rules), b in eachindex(rules)
        rules_equal(rules[a], rules[b], net) &&
            println("EQ\t", names[a], "\t", names[b])
    end
end

probe("abc", "abd", "ijk")
probe("aabc", "aabd", "ijkk")
probe("eqe", "qqq", "mrrjjj")
probe("aabbcc", "aabbdd", "mrrjjj")
