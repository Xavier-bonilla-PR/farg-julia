# Julia counterpart of metacat/bench/metacat_themes_probe.ss.
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

nm(n) = n === nothing ? "-" : n.lowercase_name
yn(b) = b ? "y" : "n"
descr_print_name(d::Description) = string(d.description_type.short_name, ":",
                                          d.descriptor.short_name)

"""Exact rendering of a number, matching the Scheme probe: exact values print
as themselves, inexact ones as the exact rational the double really is, so a
one-ulp drift shows up as a different numerator."""
function num(v)
    if is_exact(v)
        x = snorm(v)
        return x isa Integer ? string(x) : string(numerator(x), "/", denominator(x))
    end
    r = Rational{BigInt}(v)
    return string("F", numerator(r), "/", denominator(r))
end

"""Scheme's `~a` rendering of a list."""
slist(xs) = string("(", join(xs, " "), ")")

const TYPE_NAMES = Dict(:top_bridge => "top-bridge", :bottom_bridge => "bottom-bridge",
                        :vertical_bridge => "vertical-bridge")
tn(t::Symbol) = TYPE_NAMES[t]

net = build_slipnet()
ts = make_themespace(net)

const TYPES = Symbol[:top_bridge, :bottom_bridge, :vertical_bridge]
dim_at(i) = ts.dimensions[i + 1]
rel_at(type, i, j) = get_relations(ts, type, dim_at(i))[j + 1]

# --- structure --------------------------------------------------------------

println("DIMS\t", length(ts.dimensions))
for i in 0:(length(ts.dimensions) - 1)
    d = dim_at(i)
    relations = get_relations(ts, :top_bridge, d)
    println("DIM\t", i, "\t", d.short_name, "\t", length(relations))
    for (j, r) in enumerate(relations)
        println("REL\t", i, "\t", j - 1, "\t", nm(r))
    end
end
println("TYPES\t", slist(map(tn, get_possible_theme_types())))
println("ACTIVE\t", slist(map(tn, ts.active_theme_types)))
println("PRESSURE\t", yn(has_thematic_pressure(ts)))

# --- themespace dump --------------------------------------------------------

function dump_themespace(tag)
    for type in TYPES, c in get_clusters(ts, type)
        isempty(c.themes) && continue
        d = c.dominant_theme
        println("CLUSTER\t", tag, "\t", tn(type), "\t", c.dimension.short_name, "\t",
                length(c.themes), "\t", yn(c.frozen), "\t",
                d === nothing ? "-" : theme_ascii_name(d::BridgeTheme))
        for th in c.themes
            println("THEME\t", tag, "\t", tn(type), "\t", theme_ascii_name(th), "\t",
                    th.activation, "\t", yn(is_dominant(th)), "\t", yn(is_frozen(th)),
                    "\t", yn(th.frozen))
        end
    end
    println("ALLTHEMES\t", tag, "\t", slist(map(theme_ascii_name, ts.all_themes)))
    println("PCTDOM\t", tag, "\t", num(get_percentage_of_dominant_themes(ts)))
end

# --- dynamics ---------------------------------------------------------------

function seed_themes()
    delete_everything!(ts)
    unfreeze_everything!(ts)
    set_theme_activation!(ts, :top_bridge, dim_at(0), rel_at(:top_bridge, 0, 3), 100)
    set_theme_activation!(ts, :top_bridge, dim_at(0), rel_at(:top_bridge, 0, 2), 40)
    set_theme_activation!(ts, :top_bridge, dim_at(0), rel_at(:top_bridge, 0, 0), -60)
    set_theme_activation!(ts, :top_bridge, dim_at(0), rel_at(:top_bridge, 0, 1), 0)
    set_theme_activation!(ts, :vertical_bridge, dim_at(1), rel_at(:vertical_bridge, 1, 1), 80)
    set_theme_activation!(ts, :vertical_bridge, dim_at(1), rel_at(:vertical_bridge, 1, 2), -30)
    set_theme_activation!(ts, :top_bridge, dim_at(7), rel_at(:top_bridge, 7, 0), 95)
    set_theme_activation!(ts, :top_bridge, dim_at(7), rel_at(:top_bridge, 7, 1), 95)
end

seed_themes()
dump_themespace("seeded")

for cycle in 0:11
    spread_activation!(ts)
    dump_themespace(string("cycle", cycle))
end

# --- freezing / deleting ----------------------------------------------------

seed_themes()
freeze_theme!(ts, :top_bridge, dim_at(0), rel_at(:top_bridge, 0, 3))
freeze_theme_cluster!(ts, :top_bridge, dim_at(7))
dump_themespace("frozen")
spread_activation!(ts)
dump_themespace("frozen-spread")
println("FROZENQ\t",
        yn(theme_frozen(ts, :top_bridge, dim_at(0), rel_at(:top_bridge, 0, 3))), "\t",
        yn(cluster_frozen(ts, :top_bridge, dim_at(7))), "\t",
        yn(theme_type_frozen(ts, :top_bridge)))
unfreeze_theme_cluster!(ts, :top_bridge, dim_at(7))
spread_activation!(ts)
dump_themespace("unfrozen-spread")
delete_theme!(ts, :top_bridge, dim_at(0), rel_at(:top_bridge, 0, 2))
dump_themespace("deleted")
delete_theme_type!(ts, :top_bridge)
dump_themespace("deleted-type")

# --- pressure and active themes ---------------------------------------------

delete_everything!(ts)
unfreeze_everything!(ts)
thematic_pressure_off!(ts)
seed_themes()
println("PRESSURE\t", yn(has_thematic_pressure(ts)))
thematic_pressure_on!(ts, :vertical_bridge)
println("ACTIVE\t", slist(map(tn, ts.active_theme_types)))
println("ACTIVETHEMES\t", slist(map(theme_ascii_name, get_all_active_themes(ts))))
println("MAXPOS\t", get_max_positive_theme_activation(ts, :top_bridge), "\t",
        get_max_positive_theme_activation(ts, :vertical_bridge), "\t",
        get_max_positive_theme_activation(ts, get_active_bridge_theme_types(ts)))
thematic_pressure_on!(ts)
println("ACTIVE\t", slist(map(tn, ts.active_theme_types)))
println("ACTIVEBRIDGE\t", slist(map(tn, get_active_bridge_theme_types(ts))))
println("DOMPATTERNS\t",
        slist([slist(vcat([tn(type)],
                          [slist([e[1].short_name, nm(e[2])])
                           for e in get_dominant_theme_pattern(ts, type)]))
               for type in get_possible_theme_types()]))
println("NONZERO\t",
        slist(vcat([tn(:top_bridge)],
                   [slist([e[1].short_name, nm(e[2]), e[3]])
                    for e in get_nonzero_theme_pattern(ts, :top_bridge)])))

# --- the rest of the themespace API ----------------------------------------
#
# Cluster-level queries, the wholesale freeze/unfreeze/delete paths, and the
# stochastic theme pick, which draws and so has to agree draw for draw.

println("CMAXPOS\t",
        get_max_positive_theme_activation(get_cluster(ts, :top_bridge, dim_at(0))), "\t",
        get_max_positive_theme_activation(get_cluster(ts, :vertical_bridge, dim_at(1))), "\t",
        get_max_positive_theme_activation(get_cluster(ts, :top_bridge, dim_at(4))))
let rng = PyRandom(91)
    for k in 0:7
        th = pick_positive_theme(rng, get_cluster(ts, :top_bridge, dim_at(0)))
        println("PICK\t", k, "\t", th === nothing ? "-" : theme_ascii_name(th::BridgeTheme))
    end
end
println("EVERYFROZEN\t", yn(everything_frozen(ts)))
freeze_theme_type!(ts, :top_bridge)
println("EVERYFROZEN\t", yn(theme_type_frozen(ts, :top_bridge)), "\t",
        yn(everything_frozen(ts)))
freeze_everything!(ts)
println("EVERYFROZEN\t", yn(everything_frozen(ts)))
unfreeze_theme!(ts, :top_bridge, dim_at(0), rel_at(:top_bridge, 0, 3))
dump_themespace("all-frozen")
unfreeze_everything!(ts)
delete_theme_cluster!(ts, :top_bridge, dim_at(0))
dump_themespace("cluster-deleted")
set_theme_cluster_activations!(ts, :top_bridge, dim_at(2), 55)
set_theme_type_activations!(ts, :vertical_bridge, 30)
dump_themespace("bulk-set")
set_all_theme_activations!(ts, 15)
dump_themespace("all-set")
let held = get_theme(ts, :top_bridge, dim_at(2), rel_at(:top_bridge, 2, 1))::BridgeTheme
    println("PRESENT\t", yn(theme_present(ts, held)), "\t",
            theme_ascii_name(get_equivalent_theme(ts, held)::BridgeTheme))
    # a theme object outlives its deletion from the themespace
    delete_theme!(ts, :top_bridge, dim_at(2), rel_at(:top_bridge, 2, 1))
    println("PRESENT\t", yn(theme_present(ts, held)), "\t",
            get_equivalent_theme(ts, held) === nothing ? "-" : "?")
end

# --- theme support in a workspace -------------------------------------------

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
        build_bond!(b, net)
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

function support_probe(i, m, t, seed)
    println("PROBLEM\t", i, "\t", m, "\t", t, "\t", seed)
    foreach(reset!, net.nodes)
    initialize!(ts)
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
              net[:plato_direction_category], net[:plato_length],
              net[:plato_alphabetic_position_category], net[:plato_bond_category],
              net[:plato_bond_facet])
        set_activation!(n, MAX_ACTIVATION)
    end
    update_workspace_values!(strings)
    rng = PyRandom(seed)
    for s in strings
        build_chain_and_group!(s)
    end
    update_workspace_values!(strings, rng, net)
    # A theme pattern to judge the bridges against: LettCtgy maps by identity,
    # StringPos by opposite, ObjCtgy by identity, and Direction is asserted NOT
    # to map by identity.
    thematic_pressure_on!(ts)
    for type in (:top_bridge, :vertical_bridge)
        set_theme_activation!(ts, type, dim_at(0), rel_at(type, 0, 3), 100)
        set_theme_activation!(ts, type, dim_at(1), rel_at(type, 1, 1), 90)
        set_theme_activation!(ts, type, dim_at(7), rel_at(type, 7, 0), 70)
        set_theme_activation!(ts, type, dim_at(3), rel_at(type, 3, 1), -80)
    end
    dump_themespace("support")
    for s in strings, o in objects(s), d in o.descriptions
        update_strength!(d, ts)
        println("DESCR\t", ascii_name(o), "\t", descr_print_name(d), "\t",
                slist(map(num, get_theme_support_values(d, ts))), "\t",
                num(get_thematic_compatibility(d, ts)), "\t", d.strength)
    end
    specs = ((:vertical, strings[1], strings[3]), (:horizontal, strings[1], strings[2]))
    for (orientation, s1, s2) in specs
        for o1 in objects(s1), o2 in objects(s2)
            cms = all_possible_bridge_cms(orientation, o1, o1.descriptions,
                                          o2, o2.descriptions, net)
            isempty(cms) && continue
            b = make_bridge(orientation, o1, o2, cms, net)
            tag = string(orientation, ":", ascii_name(o1), ">", ascii_name(o2))
            update_structure_strength!(b, net, Bridge[], ts)
            println("BRSUP\t", tag, "\t",
                    slist(map(num, get_theme_support_values(b, ts, net))), "\t",
                    num(get_average_theme_support(b, ts, net)), "\t",
                    num(get_thematic_compatibility(b, ts, net)), "\t", b.strength)
            for th in get_active_themes(ts, bridge_type_to_theme_type(b.bridge_type))
                println("BRTH\t", tag, "\t", theme_ascii_name(th), "\t",
                        yn(incompatible_with_theme(b, th, ts, net)), "\t",
                        yn(supported_by_theme(b, th, net)))
            end
            println("BRREL\t", tag, "\t",
                    slist([slist([e[1].short_name, nm(e[2])])
                           for e in get_associated_thematic_relations(b, net)]))
            for cm in b.all_concept_mappings
                println("BRACT\t", tag, "\t", cm_print_name(cm, net), "\t",
                        yn(supported_by_active_theme(ts, cm, b)))
            end
        end
    end
    # boosting: every bridge votes for the themes its mappings realise
    for (orientation, s1, s2) in specs
        for o1 in objects(s1), o2 in objects(s2)
            cms = all_possible_bridge_cms(orientation, o1, o1.descriptions,
                                          o2, o2.descriptions, net)
            isempty(cms) && continue
            b = make_bridge(orientation, o1, o2, cms, net)
            update_structure_strength!(b, net, Bridge[], ts)
            boost_themespace_activations!(b, ts, net)
        end
    end
    dump_themespace("boosted")
    # and the themes push back on the slipnet
    for cycle in 0:2
        update_slipnet_activations!(net, rng, ts)
        for n in net.nodes
            println("NODE\t", cycle, "\t", nm(n), "\t", n.activation)
        end
    end
end

support_probe("abc", "abd", "ijk", 81)
support_probe("abc", "cba", "pqrs", 82)
support_probe("abc", "abd", "mrrjjj", 83)

#--------------------------------------------------------------- exactness ---
#
# The two places where the themespace's arithmetic depends on Scheme's
# EXACTNESS and not just on its numbers. Both were open divergences in the
# port; this section is what stops them reopening, and it is why `num`
# distinguishes an exact value from an inexact one that happens to be whole.
# See `sexp` and `smax`/`smin` in `schemenum.jl`.

println("SECTION\texactness")

# `num` runs the value through `snorm`, so it renders an exact 1 and an exact
# 1//1 alike -- which is the whole point of the `max` case, and would hide it.
# `rep` names the REPRESENTATION instead. Scheme has no unnormalised 1/1, so
# "int" here is a claim the port has to earn.
rep(x) = !is_exact(x) ? "flo" : x isa Integer ? "int" : "rat"

for x in Real[0, 0.0, 1, -1, 1//2, -1//2, 9//10, 1//100, -3//4, -1//1000]
    y = bridge_theme_compatibility_sigmoid(x)
    println("SIG\t", num(x), "\t", rep(x), "\t", num(y), "\t", rep(y))
end

for l in Any[Real[], Real[0], Real[9//10, 1], Real[1, 9//10], Real[1//2, 1//4],
             Real[0, 0, 9//10], Real[1, 1, 1], Real[100, 3//4, 0],
             Real[3, 2.0], Real[2.0, 3], Real[1//2, 0.25]]
    hi = smaximum(l)
    lo = sminimum(l)
    println("EXTREME\t", isempty(l) ? "-" : slist(map(num, l)), "\t",
            num(hi), "\t", rep(hi), "\t", num(lo), "\t", rep(lo))
end

# And through the model: a description and a bridge with the themespace EMPTY,
# which is the state the sigmoid's exact zero comes from.
foreach(reset!, net.nodes)
initialize!(ts)
let strings = [make_workspace_string(net, :initial, "abc"),
               make_workspace_string(net, :modified, "abd"),
               make_workspace_string(net, :target, "ijk")]
    add_string_position_descriptions_to_letters!(net, strings[1])
    add_string_position_descriptions_to_letters!(net, strings[3])
    update_workspace_values!(strings)
    d = strings[1].letters[1].descriptions[1]
    update_strength!(d, ts)
    println("NOTHEMES\tdescr\t", descr_print_name(d), "\t",
            num(get_thematic_compatibility(d, ts)), "\t",
            rep(get_thematic_compatibility(d, ts)), "\t", d.strength)
    # TWO active themes on the SAME dimension, one at 100 and one at 90, so the
    # description's support values are the exact INTEGER 1 and the exact RATIO
    # 9//10. Scheme's `max` returns the integer; Julia's promotes to 1//1 --
    # the same number, a different thing, and the only shape in which that
    # difference is observable.
    thematic_pressure_on!(ts)
    let dim = d.description_type, rels = get_relations(ts, :vertical_bridge, dim)
        set_theme_activation!(ts, :vertical_bridge, dim, rels[1], 100)
        set_theme_activation!(ts, :vertical_bridge, dim, rels[2], 90)
        update_strength!(d, ts)
        println("MIXED\t", descr_print_name(d), "\t",
                slist(map(num, get_theme_support_values(d, ts))), "\t",
                num(get_thematic_compatibility(d, ts)), "\t",
                rep(get_thematic_compatibility(d, ts)), "\t", d.strength)
    end
    initialize!(ts)

    o1 = strings[1].letters[1]
    o2 = strings[3].letters[1]
    cms = all_possible_bridge_cms(:vertical, o1, o1.descriptions, o2,
                                  o2.descriptions, net)
    b = make_bridge(:vertical, o1, o2, cms, net)
    update_structure_strength!(b, net, Bridge[], ts)
    println("NOTHEMES\tbridge\t", num(get_average_theme_support(b, ts, net)), "\t",
            rep(get_average_theme_support(b, ts, net)), "\t",
            num(get_thematic_compatibility(b, ts, net)), "\t",
            rep(get_thematic_compatibility(b, ts, net)), "\t", b.strength)
end
