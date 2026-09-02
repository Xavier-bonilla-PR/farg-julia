# Julia counterpart of metacat/bench/metacat_bench.ss: identical workloads, and
# same checksums, which is what shows both implementations did the same work.
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
include("../julia/src/themes.jl")

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
        build_bond!(b, net)
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

#--- workload 5: themespace activation cycles -------------------------------
const ts = make_themespace(net)

function themespace_workload()
    initialize!(ts)
    for type in (:top_bridge, :bottom_bridge, :vertical_bridge)
        set_theme_type_activations!(ts, type, 60)
    end
    set_theme_activation!(ts, :top_bridge, ts.dimensions[1], net[:plato_identity], 100)
    # accumulate across cycles: the activations decay to zero by the end, so
    # only the trajectory is a checksum worth comparing.
    acc = 0
    for _ in 1:50
        spread_activation!(ts)
        acc += ssum([absolute_activation(t) for t in ts.all_themes]) +
               count(is_dominant, ts.all_themes)
    end
    return acc
end

timeit("slipnet-50-cycles", 400, slipnet_cycle_workload)
timeit("workspace-init", 2000, workspace_init_workload)
workspace_init_workload()
timeit("concept-mappings", 2000, cm_workload)
timeit("bonds-and-groups", 2000, bonds_groups_workload)
timeit("themespace-50-cycles", 200, themespace_workload)
