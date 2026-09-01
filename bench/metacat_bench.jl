# Julia counterpart of bench/metacat_bench.ss: identical workloads, and the
# same checksums, which is what shows both implementations did the same work.
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

const net = build_slipnet()
current_strings = WorkspaceString[]

function timeit(name, iterations, thunk)
    thunk()                                   # warm up (also triggers JIT)
    t0 = time_ns()
    checksum = 0
    for _ in 1:iterations
        checksum += thunk()
    end
    elapsed = (time_ns() - t0) / 1e9
    println("BENCH\t", name, "\t", iterations, "\t", elapsed, "\t", checksum)
end

#--- workload 1: slipnet activation cycles ---------------------------------
function slipnet_cycle_workload()
    foreach(reset!, net.nodes)
    rng = PyRandom(777)
    activate_from_workspace!(net[:plato_a])
    activate_from_workspace!(net[:plato_successor])
    activate_from_workspace!(net[:plato_letter_category])
    for _ in 1:50
        update_slipnet_activations!(net, rng)
    end
    return ssum([n.activation for n in net.nodes])
end

#--- workload 2: workspace initialisation ----------------------------------
function workspace_init_workload()
    foreach(reset!, net.nodes)
    strings = [make_workspace_string(net, :initial, "abcde"),
               make_workspace_string(net, :modified, "abcdf"),
               make_workspace_string(net, :target, "pqrst")]
    for s in strings
        add_string_position_descriptions_to_letters!(net, s)
    end
    for s in strings, o in objects(s), d in o.descriptions
        set_activation!(d.descriptor, MAX_ACTIVATION)
    end
    update_workspace_values!(strings)
    global current_strings = strings
    return ssum([o.average_salience for s in strings for o in objects(s)])
end

#--- workload 3: concept mappings ------------------------------------------
function cm_workload()
    acc = 0
    for o1 in objects(current_strings[1]), o2 in objects(current_strings[3])
        for d1 in o1.descriptions, d2 in o2.descriptions
            cm = make_concept_mapping(net, o1, d1.description_type, d1.descriptor,
                                      o2, d2.description_type, d2.descriptor)
            acc += cm_strength(cm) + cm_slippability(cm) +
                   (cm_distinguishing(cm, net) ? 1 : 0)
        end
    end
    return acc
end

#--- workload 4: bonds and groups ------------------------------------------
function build_chain_and_groups!(s::WorkspaceString)
    bonds = Any[]
    for p in 1:(string_length(s) - 1)
        o1 = s.letters[p]; o2 = s.letters[p + 1]
        d1 = get_descriptor_for(o1, net[:plato_letter_category])::Node
        d2 = get_descriptor_for(o2, net[:plato_letter_category])::Node
        cat = get_bond_category_between(d1, d2, net)
        cat === nothing && continue
        b = make_bond(net, o1, o2, cat::Node, net[:plato_letter_category], d1, d2)
        build_bond!(b)
        push!(bonds, b)
    end
    isempty(bonds) && return
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

function bonds_groups_workload()
    foreach(reset!, net.nodes)
    strings = [make_workspace_string(net, :initial, "abcde"),
               make_workspace_string(net, :modified, "abcdf"),
               make_workspace_string(net, :target, "pqrst")]
    for s in strings
        add_string_position_descriptions_to_letters!(net, s)
    end
    for s in strings, o in objects(s), d in o.descriptions
        set_activation!(d.descriptor, MAX_ACTIVATION)
    end
    update_workspace_values!(strings)
    rng = PyRandom(555)
    for s in strings
        build_chain_and_groups!(s)
    end
    update_workspace_values!(strings, rng, net)
    return ssum([b.strength for s in strings for b in s.bonds]) +
           ssum([g.strength for s in strings for g in s.groups])
end

#--- workload 5: themespace settling ---------------------------------------
const themespace = make_themespace(net)
const theme_specs = (
    (:top_bridge, net[:plato_letter_category], net[:plato_successor], 100),
    (:top_bridge, net[:plato_letter_category], net[:plato_identity], 40),
    (:top_bridge, net[:plato_letter_category], nothing, -60),
    (:top_bridge, net[:plato_string_position_category], net[:plato_identity], 75),
    (:top_bridge, net[:plato_string_position_category], net[:plato_opposite], -30),
    (:top_bridge, net[:plato_length], net[:plato_successor], 65),
    (:vertical_bridge, net[:plato_letter_category], net[:plato_successor], 90),
    (:vertical_bridge, net[:plato_letter_category], net[:plato_predecessor], -55),
    (:vertical_bridge, net[:plato_object_category], nothing, 55),
    (:vertical_bridge, net[:plato_group_category], net[:plato_identity], 80),
    (:vertical_bridge, net[:plato_length], net[:plato_predecessor], -100),
    (:bottom_bridge, net[:plato_direction_category], net[:plato_opposite], 65))

function themespace_workload()
    delete_everything!(themespace)
    unfreeze_everything!(themespace)
    thematic_pressure_on!(themespace)
    for (tt, dim, rel, act) in theme_specs
        set_theme_activation!(themespace, tt, dim, rel, act)
    end
    for _ in 1:20
        spread_theme_activation!(themespace)
    end
    return ssum([get_activation(t) for t in get_all_themes(themespace)])
end

timeit("slipnet-50-cycles", 400, slipnet_cycle_workload)
timeit("workspace-init", 2000, workspace_init_workload)
workspace_init_workload()
timeit("concept-mappings", 2000, cm_workload)
timeit("bonds-and-groups", 2000, bonds_groups_workload)
timeit("themespace-settling", 2000, themespace_workload)
