# Julia counterpart of bench/metacat_themes_probe.ss: same trace, same order.
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

net = build_slipnet()
ts = make_themespace(net)

tt_tag(tt) = tt === :top_bridge ? "top" : tt === :bottom_bridge ? "bot" : "ver"
rel_tag(r) = r === nothing ? "diff" : r.lowercase_name
yn(b) = b ? "y" : "n"
fmtnum(v) = v isa AbstractFloat ? string(v) :
            (v isa Rational ? string(numerator(v), "/", denominator(v)) : string(v))
emit(label, v) = println(label, "\t", is_exact(v) ? "E" : "F", "\t", fmtnum(v))

"""Print a nested list the way Chez's `~a` does."""
sexp(x::AbstractString) = x
sexp(x::Union{AbstractVector,Tuple}) = string("(", join(map(sexp, x), " "), ")")
sexp(x) = fmtnum(x)

#-------------------------------------------------------------------- A. shape
for tt in (:top_bridge, :bottom_bridge, :vertical_bridge)
    for c in get_clusters(ts, tt)
        println("CLUSTER\t", tt_tag(tt), "\t", c.dimension.short_name, "\t",
                length(c.relations), "\t", sexp(map(rel_tag, c.relations)))
    end
end
println("POSSIBLE-TYPES\t", sexp(map(tt_tag, get_possible_theme_types())))

#----------------------------------------------------------- dumping utilities
function dump_themes(tag)
    for (k, th) in enumerate(get_all_themes(ts))
        println("TH\t", tag, "\t", k - 1, "\t", tt_tag(th.theme_type), "\t",
                theme_ascii_name(th), "\t", get_activation(th), "\t",
                yn(is_dominant(th)), "\t", yn(is_theme_frozen(th)), "\t",
                yn(individually_frozen(th)), "\t", length(th.cluster.themes))
    end
end

function dump_dominant(tag)
    for tt in (:top_bridge, :bottom_bridge, :vertical_bridge), c in get_clusters(ts, tt)
        c.dominant_theme === nothing && continue
        println("DOM\t", tag, "\t", tt_tag(tt), "\t", theme_ascii_name(c.dominant_theme),
                "\t", get_activation(c.dominant_theme))
    end
end

#----------------------------------------------------- B. creation and spread
delete_everything!(ts)
unfreeze_everything!(ts)
thematic_pressure_on!(ts)
println("ACTIVE\t", sexp(map(tt_tag, ts.active_theme_types)))
println("PRESSURE\t", yn(thematic_pressure(ts, :top_bridge)), "\t",
        yn(thematic_pressure(ts, :bottom_bridge)), "\t",
        yn(thematic_pressure(ts, :vertical_bridge)))

for (tt, dim, rel, act) in (
        (:top_bridge, net[:plato_letter_category], net[:plato_successor], 100),
        (:top_bridge, net[:plato_letter_category], net[:plato_identity], 40),
        (:top_bridge, net[:plato_letter_category], nothing, -60),
        (:top_bridge, net[:plato_string_position_category], net[:plato_identity], 75),
        (:top_bridge, net[:plato_string_position_category], net[:plato_opposite], -30),
        (:vertical_bridge, net[:plato_letter_category], net[:plato_successor], 90),
        (:vertical_bridge, net[:plato_object_category], nothing, 55),
        (:vertical_bridge, net[:plato_length], net[:plato_predecessor], -100),
        (:bottom_bridge, net[:plato_direction_category], net[:plato_opposite], 65))
    set_theme_activation!(ts, tt, dim, rel, act)
end
dump_themes("init")
dump_dominant("init")

for step in 0:11
    spread_theme_activation!(ts)
    for th in get_all_themes(ts)
        emit("SPREAD/$step/$(tt_tag(th.theme_type))/$(theme_ascii_name(th))",
             get_activation(th))
    end
end
dump_dominant("settled")
emit("PCT-DOMINANT", get_percentage_of_dominant_themes(ts))

#----------------------------------------------------------------- C. boosting
for factor in (0, 13, 50, 87, 100, 250)
    for th in get_all_themes(ts)
        boost_theme_activation!(th, factor)
    end
    for th in get_all_themes(ts)
        emit("BOOST/$factor/$(tt_tag(th.theme_type))/$(theme_ascii_name(th))",
             get_activation(th))
    end
end

#----------------------------------------------------------------- D. freezing
freeze_theme!(ts, :top_bridge, net[:plato_letter_category], net[:plato_successor])
freeze_theme_cluster!(ts, :vertical_bridge, net[:plato_letter_category])
println("FROZEN\t",
        yn(is_theme_frozen(ts, :top_bridge, net[:plato_letter_category],
                           net[:plato_successor])), "\t",
        yn(is_cluster_frozen(ts, :vertical_bridge, net[:plato_letter_category])), "\t",
        yn(is_theme_type_frozen(ts, :top_bridge)), "\t",
        yn(everything_frozen(ts)))
spread_theme_activation!(ts)
dump_themes("frozen")
println("ADD-IF\t", yn(add_theme_if_possible!(ts, :vertical_bridge,
                                              net[:plato_letter_category],
                                              net[:plato_opposite]) !== nothing))
println("ADD-UNC\t", yn(add_theme_unconditionally!(ts, :vertical_bridge,
                                                   net[:plato_letter_category],
                                                   net[:plato_opposite]) !== nothing))
unfreeze_everything!(ts)

#----------------------------------------------------------------- E. patterns
pat3(e) = [e[1].short_name, rel_tag(e[2]), e[3]]
pat2(e) = [e[1].short_name, rel_tag(e[2])]
for tt in (:top_bridge, :vertical_bridge)
    println("COMPLETE\t", tt_tag(tt), "\t",
            sexp(map(pat3, get_complete_theme_pattern(ts, tt))))
    println("NONZERO\t", tt_tag(tt), "\t",
            sexp(map(pat3, get_nonzero_theme_pattern(ts, tt))))
    println("DOMPAT\t", tt_tag(tt), "\t",
            sexp(map(pat2, get_dominant_theme_pattern(ts, tt))))
end

#----------------------------------------- F. themes against a real workspace
function build_chain_and_group!(s::WorkspaceString, rng::PyRandom)
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

function probe_workspace(i, m, t, seed, themes)
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
              net[:plato_direction_category], net[:plato_length],
              net[:plato_alphabetic_position_category], net[:plato_bond_category],
              net[:plato_bond_facet])
        set_activation!(n, MAX_ACTIVATION)
    end
    update_workspace_values!(strings)
    rng = PyRandom(seed)
    for s in strings
        build_chain_and_group!(s, rng)
    end
    update_workspace_values!(strings, rng, net)
    all_objects = vcat((objects(s) for s in strings)...)
    for obj in all_objects
        println("DPOSS\t", ascii_name(obj), "\t",
                sexp([[dim.short_name, yn(description_possible(dim, obj, net))]
                      for dim in ts.dimensions]))
    end
    delete_everything!(ts)
    unfreeze_everything!(ts)
    thematic_pressure_on!(ts)
    for (tt, dim, rel, act) in themes
        set_theme_activation!(ts, tt, dim, rel, act)
    end
    for (orientation, s1, s2) in ((:vertical, strings[1], strings[3]),
                                  (:horizontal, strings[1], strings[2]))
        for o1 in objects(s1), o2 in objects(s2)
            cms = all_possible_bridge_cms(orientation, o1, o1.descriptions,
                                          o2, o2.descriptions, net)
            isempty(cms) && continue
            b = make_bridge(orientation, o1, o2, cms, net)
            tag = string(orientation, ":", ascii_name(o1), ">", ascii_name(o2))
            for (k, v) in enumerate(get_theme_support_values(b, ts, net))
                emit("TSV/$tag/$(k - 1)", v)
            end
            emit("AVG/$tag", get_average_theme_support(b, ts, net))
            emit("COMPAT/$tag", get_thematic_compatibility(b, ts, net))
            update_structure_strength!(b, net, Bridge[], ts)
            emit("STRENGTH/$tag", b.strength)
            println("ATR\t", tag, "\t",
                    sexp(map(pat2, get_associated_thematic_relations(b, net))))
            boost_themespace_activations!(b, ts, net)
        end
    end
    dump_themes("boosted")
    dump_dominant("boosted")
    for obj in all_objects, d in obj.descriptions
        update_strength!(d, ts, net)
        println("DESC\t", ascii_name(obj), "\t", string(d.description_type.short_name, ":", d.descriptor.short_name), "\t",
                fmtnum(get_thematic_compatibility(d, ts, net)), "\t", d.strength, "\t",
                sexp(map(fmtnum, get_theme_support_values(d, ts))))
    end
end

probe_workspace("abc", "abd", "ijk", 81,
    ((:top_bridge, net[:plato_letter_category], net[:plato_successor], 100),
     (:top_bridge, net[:plato_string_position_category], net[:plato_identity], 80),
     (:vertical_bridge, net[:plato_letter_category], net[:plato_identity], 100),
     (:vertical_bridge, net[:plato_string_position_category], net[:plato_identity], 90),
     (:vertical_bridge, net[:plato_object_category], nothing, -70)))

probe_workspace("abc", "cba", "pqrs", 82,
    ((:top_bridge, net[:plato_string_position_category], net[:plato_opposite], 100),
     (:top_bridge, net[:plato_letter_category], net[:plato_identity], 60),
     (:vertical_bridge, net[:plato_length], net[:plato_successor], 85),
     (:vertical_bridge, net[:plato_group_category], net[:plato_identity], 100),
     (:vertical_bridge, net[:plato_direction_category], net[:plato_opposite], -45)))

probe_workspace("iijjkk", "iijjll", "mmnnoo", 83,
    ((:top_bridge, net[:plato_letter_category], net[:plato_successor], 95),
     (:top_bridge, net[:plato_bond_facet], nothing, 70),
     (:vertical_bridge, net[:plato_object_category], net[:plato_identity], 100),
     (:vertical_bridge, net[:plato_alphabetic_position_category], net[:plato_opposite], -80)))
