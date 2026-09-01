# Julia counterpart of bench/metacat_wsvalues_probe.ss.
include("../julia/src/pyrandom.jl")
include("../julia/src/metacat/schemenum.jl")
include("../julia/src/metacat/utilities.jl")
include("../julia/src/metacat/slipnet.jl")
include("../julia/src/metacat/workspace.jl")
include("../julia/src/metacat/concept_mappings.jl")
include("../julia/src/metacat/images.jl")
include("../julia/src/metacat/bonds.jl")
include("../julia/src/metacat/groups.jl")
include("../julia/src/metacat/bridges.jl")
include("../julia/src/metacat/themes.jl")
include("../julia/src/metacat/coderack.jl")
include("../julia/src/metacat/context.jl")
include("../julia/src/metacat/codelets_bonds.jl")
include("../julia/src/metacat/codelets_descriptions.jl")
include("../julia/src/metacat/codelets_groups.jl")

nm(n) = n === nothing ? "-" : n.lowercase_name
yn(b) = b ? "y" : "n"
fmtnum(v) = v isa AbstractFloat ? string(v) :
            (v isa Rational ? string(numerator(v), "/", denominator(v)) : string(v))
emit(label, v) = println(label, "\t", is_exact(v) ? "E" : "F", "\t", fmtnum(v))
net = build_slipnet()

function build_chain_and_group!(s::WorkspaceString)
    n = string_length(s)
    bonds = Any[]
    for p in 1:(n - 1)
        o1 = s.letters[p]; o2 = s.letters[p + 1]
        d1 = get_descriptor_for(o1, net[:plato_letter_category])::Node
        d2 = get_descriptor_for(o2, net[:plato_letter_category])::Node
        cat = get_bond_category_between(d1, d2, net)
        cat === nothing && continue
        b = make_bond(net, o1, o2, cat::Node, net[:plato_letter_category], d1, d2)
        build_bond!(b)
        push!(bonds, b)
    end
    (isempty(bonds) || length(bonds) != n - 1) && return
    cat = bonds[1].bond_category
    dir = bonds[1].direction
    gcat = get_related_node(cat, net[:plato_group_category], net[:plato_identity])::Node
    objs = WSObject[bonds[1].left_object]
    for b in bonds
        push!(objs, b.right_object)
    end
    build_group!(make_group(net, s, gcat, net[:plato_letter_category], dir,
                            objs[1], objs[end], objs, bonds), net)
    return
end

function dump_workspace(ctx, tag)
    emit("AVG-INTRA/$tag", ctx.average_intra_string_unhappiness)
    emit("AVG-TOP/$tag", ctx.average_top_inter_string_unhappiness)
    emit("AVG-VERT/$tag", ctx.average_vertical_inter_string_unhappiness)
    emit("AVG-ALL/$tag", ctx.average_unhappiness)
    emit("MAP-TOP/$tag", ctx.top_mapping_strength)
    emit("MAP-VERT/$tag", ctx.vertical_mapping_strength)
    println("SPAN\t", tag, "\t", yn(spanning_bridge_exists(ctx, :top)), "\t",
            yn(spanning_bridge_exists(ctx, :vertical)))
    println("MAXMAP\t", tag, "\t", yn(maximal_mapping(ctx, :top)), "\t",
            yn(maximal_mapping(ctx, :vertical)))
    println("SGP\t", tag, "\t", yn(spanning_group_possible(ctx.initial_string, net)), "\t",
            yn(spanning_group_possible(ctx.modified_string, net)), "\t",
            yn(spanning_group_possible(ctx.target_string, net)))
    println("NBRIDGES\t", tag, "\t", length(get_bridges(ctx, :top)), "\t",
            length(get_bridges(ctx, :vertical)))
    for (k, cm) in enumerate(get_all_slippages(ctx, :vertical))
        println("VSLIP\t", tag, "\t", k - 1, "\t", cm_print_name(cm, net))
    end
end

function probe(i, m, t, seed, group)
    println("PROBLEM\t", i, "\t", m, "\t", t, "\t", seed, "\t", group ? "#t" : "#f")
    foreach(reset!, net.nodes)
    strings = [make_workspace_string(net, :initial, i),
               make_workspace_string(net, :modified, m),
               make_workspace_string(net, :target, t)]
    for s in strings
        add_string_position_descriptions_to_letters!(net, s)
    end
    for s in strings, o in objects(s), d in o.descriptions
        set_activation!(d.descriptor, MAX_ACTIVATION)
    end
    for nd in (net[:plato_object_category], net[:plato_letter_category],
               net[:plato_string_position_category], net[:plato_successor],
               net[:plato_predecessor], net[:plato_sameness], net[:plato_group_category],
               net[:plato_direction_category], net[:plato_length],
               net[:plato_alphabetic_position_category], net[:plato_bond_category],
               net[:plato_bond_facet])
        set_activation!(nd, MAX_ACTIVATION)
    end
    ctx = MetacatCtx(net, PyRandom(0), Coderack(), strings[1], strings[2], strings[3],
                     50, 0)
    TEMPERATURE[] = 50
    update_workspace_values!(ctx)
    dump_workspace(ctx, "bare")
    ctx.rng = PyRandom(seed)
    if group
        for s in strings
            build_chain_and_group!(s)
        end
    end
    update_workspace_values!(ctx)
    dump_workspace(ctx, "structured")
    for (orientation, s1, s2) in ((:vertical, strings[1], strings[3]),
                                  (:horizontal, strings[1], strings[2]))
        for o1 in objects(s1), o2 in objects(s2)
            lone_spanning_object(o1, o2) && continue
            get_bridge(o1, orientation) === nothing || continue
            get_bridge(o2, orientation) === nothing || continue
            cms = all_possible_bridge_cms(orientation, o1, o1.descriptions,
                                          o2, o2.descriptions, net)
            isempty(cms) && continue
            build_bridge!(ctx, make_bridge(orientation, o1, o2, cms, net))
        end
    end
    update_workspace_values!(ctx)
    dump_workspace(ctx, "bridged")
    for s in strings, o in objects(s)
        println("OBJ\t", s.string_type, "\t", ascii_name(o), "\t",
                o.horizontal_inter_string_unhappiness, "\t",
                o.vertical_inter_string_unhappiness, "\t",
                o.average_unhappiness, "\t", o.relative_importance)
    end
end

probe("abc", "abd", "ijk", 11, false)
probe("abc", "abd", "ijk", 12, true)
probe("abc", "cba", "pqrs", 13, true)
probe("iijjkk", "iijjll", "mmnnoo", 14, true)
probe("abcde", "abcdf", "pqrst", 15, false)
