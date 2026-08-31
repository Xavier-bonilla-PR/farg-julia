# Julia counterpart of bench/metacat_groups_probe.ss.
include("../julia/src/pyrandom.jl")
include("../julia/src/metacat/schemenum.jl")
include("../julia/src/metacat/utilities.jl")
include("../julia/src/metacat/slipnet.jl")
include("../julia/src/metacat/workspace.jl")
include("../julia/src/metacat/concept_mappings.jl")
include("../julia/src/metacat/images.jl")
include("../julia/src/metacat/bonds.jl")
include("../julia/src/metacat/groups.jl")

nm(n) = n === nothing ? "-" : n.lowercase_name
yn(b) = b ? "y" : "n"
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
            build_bond!(b)
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
            isempty(run) || make_run!(s, reverse(reverse(run)))
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

function probe(i, m, t, seed)
    println("PROBLEM\t", i, "\t", m, "\t", t, "\t", seed)
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
    for n in (net[:plato_object_category], net[:plato_letter_category],
              net[:plato_string_position_category], net[:plato_successor],
              net[:plato_predecessor], net[:plato_sameness], net[:plato_group_category],
              net[:plato_direction_category], net[:plato_length])
        set_activation!(n, MAX_ACTIVATION)
    end
    update_workspace_values!(strings)
    rng = PyRandom(seed)
    for s in strings
        build_runs!(s, build_bond_chain(s))
    end
    update_workspace_values!(strings, rng, net)
    for s in strings
        for g in reverse(s.groups)
            println("GRP\t", s.string_type, "\t", ascii_name(g), "\t",
                    g.print_name === nothing ? "-" : g.print_name, "\t",
                    nm(g.group_category), "\t", nm(g.bond_category), "\t",
                    nm(g.direction), "\t", nm(g.group_bond_facet), "\t",
                    g.left_string_pos, "\t", g.right_string_pos, "\t", g.group_length,
                    "\t", nm(g.platonic_length), "\t", yn(spans_whole_string(g)), "\t",
                    yn(leftmost_in_string(g)), "\t", yn(middle_in_string(g)), "\t",
                    yn(rightmost_in_string(g)), "\t", calculate_internal_strength(g, net),
                    "\t", get_num_of_local_supporting_groups(g))
            for (k, d) in enumerate(g.descriptions)
                println("GDESC\t", s.string_type, "\t", ascii_name(g), "\t", k - 1,
                        "\t", nm(d.description_type), "\t", nm(d.descriptor))
            end
            for (k, d) in enumerate(g.bond_descriptions)
                println("GBDESC\t", s.string_type, "\t", ascii_name(g), "\t", k - 1,
                        "\t", nm(d.description_type), "\t", nm(d.descriptor))
            end
        end
        for o in vcat(s.letters, s.groups)
            println("OBJ\t", s.string_type, "\t", ascii_name(o), "\t",
                    o.enclosing_group === nothing ? "-" : ascii_name(o.enclosing_group),
                    "\t", o.intra_string_unhappiness, "\t", o.intra_string_salience,
                    "\t", yn(middle_in_string(o)), "\t", length(o.descriptions))
        end
    end
end

probe("abc", "abd", "ijk", 101)
probe("abc", "abd", "mrrjjj", 202)
probe("abcde", "abcdf", "pqrst", 303)
probe("aabbcc", "aabbdd", "ijkk", 404)
