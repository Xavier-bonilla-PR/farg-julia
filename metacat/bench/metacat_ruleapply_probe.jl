# Julia counterpart of metacat/bench/metacat_ruleapply_probe.ss: applying rules
# to strings, and reading the result back out of the images.
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
include("../julia/src/codelets_bonds.jl")
include("../julia/src/codelets_descriptions.jl")
include("../julia/src/codelets_groups.jl")
include("../julia/src/rules.jl")

nm(n) = n === nothing ? "-" : n.lowercase_name
yn(b) = b ? "y" : "n"
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

"""A whole-string group over the top-level objects, so that rules naming
`(<group> <StrPos> <whole>)` have something to name."""
function make_whole_group!(s::WorkspaceString)
    objs = get_constituent_objects(s)
    bonds = Any[o.right_bond for o in objs[1:(end - 1)] if o.right_bond !== nothing]
    (length(objs) > 1 && length(bonds) == length(objs) - 1) || return nothing
    cat = bonds[1].bond_category
    dir = bonds[1].direction
    gcat = get_related_node(cat, net[:plato_group_category], net[:plato_identity])::Node
    g = make_group(net, s, gcat, net[:plato_letter_category], dir,
                   objs[1], objs[end], WSObject[objs...], bonds)
    build_group!(g, net)
    return g
end

# ------------------------------------ printing ------------------------------------

object_tag(o) = o isa WorkspaceString ? string("string:", o.string_type) : ascii_name(o)

format_transform(t) =
    length(t) == 3 ?
    string("(", format_slipnode(t[1]), " ", format_slipnode(t[2]), " ",
           format_slipnode(t[3]), ")") :
    string("(", format_slipnode(t[1]), " ",
           t[2] === nothing ? "#f" : format_slipnode(t[2]), ")")

const SNAG = String[]

function record_snag(failure_result)
    kind = failure_result[1]
    push!(SNAG,
          kind === :SWAP ?
          string("SWAP ", slist([object_tag(o) for o in failure_result[2]]), " ",
                 format_slipnode(failure_result[3])) :
          kind === :CONFLICT ?
          string("CONFLICT ", object_tag(failure_result[2]), " ",
                 format_slipnode(failure_result[3]), " ",
                 object_tag(failure_result[4]), " ",
                 format_slipnode(failure_result[5])) :
          string("CHANGE ", object_tag(failure_result[2]), " ",
                 format_transform(failure_result[3])))
    return :done
end

"""A letter image generates a bare node, not a list of them."""
listify(x) = x isa Node ? Node[x] : flatten_nodes(x)

function apply_and_report(label, r::Rule, s::WorkspaceString)
    println("APPLY\t", label, "\t", s.string_type)
    empty!(SNAG)
    result = apply_rule(r, s, net, record_snag)
    if result === nothing
        println("  RESULT\tfailed")
    elseif isempty(result)
        println("  RESULT\t", is_verbatim_rule(r) ? "verbatim" : "empty")
    else
        println("  RESULT\tok\t", length(result))
        for l in result
            println("    OT\t", object_tag(l[1]), "\t",
                    slist([format_transform(t) for t in l[2]]))
        end
    end
    for msg in SNAG
        println("  SNAG\t", msg)
    end
    println("  IMAGE\t", join([n.lowercase_name for n in generate_image_letters(s)]))
    for o in get_constituent_objects(s)
        println("  OBJIMG\t", object_tag(o), "\t",
                join([n.lowercase_name for n in listify(generate(get_image(o)))]),
                "\tswapped=", yn(get_image(o).swapped_image !== nothing))
    end
    reset_image!(get_image(s))
    println("  AFTERRESET\t",
            join([n.lowercase_name for n in generate_image_letters(s)]))
end

# ------------------------------------- clauses -------------------------------------

od(ot, dt, d) = ObjectDescription(ot, dt, d)
ch(scope, dim, d) = Change(scope, dim, d)
ich(o, cs) = intrinsic_clause(o, Change[cs...])
ech(os, ds) = extrinsic_clause(ObjectDescription[os...], Node[ds...])
const N = net

function rule_specs()
    return [
      ("identity", RuleClause[]),
      ("verbatim-xyz",
       RuleClause[verbatim_clause(Node[N[:plato_x], N[:plato_y], N[:plato_z]])]),
      ("rmost-letter-succ",
       RuleClause[ich(od(N[:plato_letter], N[:plato_string_position_category],
                         N[:plato_rightmost]),
                      [ch(:self, N[:plato_letter_category], N[:plato_successor])])]),
      ("lmost-letter-pred",
       RuleClause[ich(od(N[:plato_letter], N[:plato_string_position_category],
                         N[:plato_leftmost]),
                      [ch(:self, N[:plato_letter_category], N[:plato_predecessor])])]),
      ("rmost-letter-literal-d",
       RuleClause[ich(od(N[:plato_letter], N[:plato_string_position_category],
                         N[:plato_rightmost]),
                      [ch(:self, N[:plato_letter_category], N[:plato_d])])]),
      ("string-subobjs-succ",
       RuleClause[ich(od(:string, N[:plato_string_position_category], N[:plato_whole]),
                      [ch(:subobjects, N[:plato_letter_category],
                          N[:plato_successor])])]),
      ("string-subobjs-literal-a",
       RuleClause[ich(od(:string, N[:plato_string_position_category], N[:plato_whole]),
                      [ch(:subobjects, N[:plato_letter_category], N[:plato_a])])]),
      ("string-subobjs-length-succ",
       RuleClause[ich(od(:string, N[:plato_string_position_category], N[:plato_whole]),
                      [ch(:subobjects, N[:plato_length], N[:plato_successor])])]),
      ("string-subobjs-to-group-two",
       RuleClause[ich(od(:string, N[:plato_string_position_category], N[:plato_whole]),
                      [ch(:subobjects, N[:plato_object_category], N[:plato_group]),
                       ch(:subobjects, N[:plato_length], N[:plato_two])])]),
      ("whole-group-length-succ",
       RuleClause[ich(od(N[:plato_group], N[:plato_string_position_category],
                         N[:plato_whole]),
                      [ch(:self, N[:plato_length], N[:plato_successor])])]),
      ("whole-group-length-pred",
       RuleClause[ich(od(N[:plato_group], N[:plato_string_position_category],
                         N[:plato_whole]),
                      [ch(:self, N[:plato_length], N[:plato_predecessor])])]),
      ("whole-group-direction-opp",
       RuleClause[ich(od(N[:plato_group], N[:plato_string_position_category],
                         N[:plato_whole]),
                      [ch(:self, N[:plato_direction_category],
                          N[:plato_opposite])])]),
      ("whole-group-ctgy-opp",
       RuleClause[ich(od(N[:plato_group], N[:plato_string_position_category],
                         N[:plato_whole]),
                      [ch(:self, N[:plato_group_category], N[:plato_opposite]),
                       ch(:self, N[:plato_bond_facet],
                          N[:plato_letter_category])])]),
      ("whole-group-to-letter",
       RuleClause[ich(od(N[:plato_group], N[:plato_string_position_category],
                         N[:plato_whole]),
                      [ch(:self, N[:plato_object_category], N[:plato_letter])])]),
      ("whole-group-alphapos-last",
       RuleClause[ich(od(N[:plato_group], N[:plato_string_position_category],
                         N[:plato_whole]),
                      [ch(:self, N[:plato_alphabetic_position_category],
                          N[:plato_alphabetic_last])])]),
      ("whole-group-alphapos-first",
       RuleClause[ich(od(N[:plato_group], N[:plato_string_position_category],
                         N[:plato_whole]),
                      [ch(:self, N[:plato_alphabetic_position_category],
                          N[:plato_alphabetic_first])])]),
      # Length before LettCtgy, and the other way round: apply-before? decides
      ("whole-group-length-and-letter",
       RuleClause[ich(od(N[:plato_group], N[:plato_string_position_category],
                         N[:plato_whole]),
                      [ch(:self, N[:plato_letter_category], N[:plato_successor]),
                       ch(:self, N[:plato_length], N[:plato_successor])])]),
      ("whole-group-shorten-and-letter",
       RuleClause[ich(od(N[:plato_group], N[:plato_string_position_category],
                         N[:plato_whole]),
                      [ch(:self, N[:plato_letter_category], N[:plato_successor]),
                       ch(:self, N[:plato_length], N[:plato_predecessor])])]),
      # deliberately impossible: z has no successor
      ("all-letters-to-z-then-succ",
       RuleClause[ich(od(:string, N[:plato_string_position_category], N[:plato_whole]),
                      [ch(:subobjects, N[:plato_letter_category], N[:plato_z])]),
                  ich(od(N[:plato_letter], N[:plato_string_position_category],
                         N[:plato_rightmost]),
                      [ch(:self, N[:plato_letter_category], N[:plato_successor])])]),
      # deliberately conflicting: two changes to the same dimension of one object
      ("conflicting-rmost",
       RuleClause[ich(od(N[:plato_letter], N[:plato_string_position_category],
                         N[:plato_rightmost]),
                      [ch(:self, N[:plato_letter_category], N[:plato_successor])]),
                  ich(od(N[:plato_letter], N[:plato_letter_category], N[:plato_c]),
                      [ch(:self, N[:plato_letter_category],
                          N[:plato_predecessor])])]),
      ("swap-string-letters",
       RuleClause[ech([od(:string, N[:plato_string_position_category],
                          N[:plato_whole])],
                      [N[:plato_letter_category]])]),
      ("swap-string-positions",
       RuleClause[ech([od(:string, N[:plato_string_position_category],
                          N[:plato_whole])],
                      [N[:plato_string_position_category]])]),
      ("swap-lmost-rmost-letters",
       RuleClause[ech([od(N[:plato_letter], N[:plato_string_position_category],
                          N[:plato_leftmost]),
                       od(N[:plato_letter], N[:plato_string_position_category],
                          N[:plato_rightmost])],
                      [N[:plato_letter_category]])]),
      ("swap-lmost-rmost-positions",
       RuleClause[ech([od(N[:plato_letter], N[:plato_string_position_category],
                          N[:plato_leftmost]),
                       od(N[:plato_letter], N[:plato_string_position_category],
                          N[:plato_rightmost])],
                      [N[:plato_string_position_category]])]),
      ("swap-whole-group-lengths",
       RuleClause[ech([od(N[:plato_group], N[:plato_string_position_category],
                          N[:plato_whole])],
                      [N[:plato_length]])]),
      ("swap-and-change",
       RuleClause[ech([od(N[:plato_letter], N[:plato_string_position_category],
                          N[:plato_leftmost]),
                       od(N[:plato_letter], N[:plato_string_position_category],
                          N[:plato_rightmost])],
                      [N[:plato_letter_category]]),
                  ich(od(:string, N[:plato_string_position_category],
                         N[:plato_whole]),
                      [ch(:subobjects, N[:plato_length], N[:plato_successor])])]),
    ]
end

# -------------------------------------- probe --------------------------------------

function probe(i, m, t, with_groups)
    println("PROBLEM\t", i, "\t", m, "\t", t, "\tgroups=", yn(with_groups))
    foreach(reset!, net.nodes)
    initial = make_workspace_string(net, :initial, i)
    modified = make_workspace_string(net, :modified, m)
    target = make_workspace_string(net, :target, t)
    strings = [initial, modified, target]
    for s in strings
        add_string_position_descriptions_to_letters!(net, s)
    end
    if with_groups
        for s in (initial, target)
            build_runs!(s, build_bond_chain(s))
            make_whole_group!(s)
        end
    end
    update_workspace_values!(strings)
    for s in (initial, target)
        objs = get_constituent_objects(s)
        println("STRING\t", s.string_type, "\twhole-group=",
                yn(whole_group(s, net) !== nothing), "\tobjects=", length(objs), "\t",
                slist([object_tag(o) for o in objs]))
    end
    for (name, clauses) in rule_specs()
        for (rule_type, s) in ((:top, initial), (:bottom, target))
            apply_and_report(name, make_rule(rule_type, clauses, s, net), s)
        end
    end
end

probe("abc", "abd", "ijk", false)
probe("abc", "abd", "ijk", true)
probe("aabc", "aabd", "ijkk", true)
probe("xyz", "xyd", "rssttt", true)
probe("aabbcc", "aabbdd", "mrrjjj", true)
