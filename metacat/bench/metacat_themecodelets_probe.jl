# Julia counterpart of metacat/bench/metacat_themecodelets_probe.ss: the
# thematic codelet pipeline driven through the real coderack, against a clamped
# theme pattern, with the ordinary scouts running alongside.
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
include("../julia/src/codelets_bridges.jl")
include("../julia/src/codelets_themes.jl")

nm(n) = n === nothing ? "-" : n.lowercase_name
yn(b) = b ? "y" : "n"
num(v) = (x = snorm(v); x isa Integer ? string(x) :
                        string(numerator(x), "/", denominator(x)))
slist(xs) = string("(", join(xs, " "), ")")
descr_print_name(d::Description) = string(d.description_type.short_name, ":",
                                          d.descriptor.short_name)
const TYPE_NAMES = Dict(:top_bridge => "top-bridge", :bottom_bridge => "bottom-bridge",
                        :vertical_bridge => "vertical-bridge")
net = build_slipnet()

function seed_rack!(ctx::MetacatCtx)
    post(name, urgency, args = Any[]) =
        post!(ctx.coderack, make_codelet(CODELET_TYPES[name], urgency, args),
              ctx.codelet_count, ctx.rng, ctx.temperature, ctx)
    for _ in 1:3
        post(:thematic_bridge_scout, VERY_HIGH_URGENCY)
        post(:thematic_bridge_scout, VERY_HIGH_URGENCY)
        post(:bottom_up_bond_scout, VERY_LOW_URGENCY)
        post(:group_scout_whole_string, LOW_URGENCY)
        post(:bottom_up_bridge_scout, MEDIUM_URGENCY)
        post(:bottom_up_description_scout, VERY_LOW_URGENCY)
    end
    return ctx
end

function probe(i, m, t, seed, n, temp, theme_spec)
    println("PROBLEM\t", i, "\t", m, "\t", t, "\t", seed, "\t", n, "\t", temp)
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
               net[:plato_predecessor], net[:plato_sameness], net[:plato_bond_facet],
               net[:plato_bond_category], net[:plato_group_category],
               net[:plato_direction_category], net[:plato_left], net[:plato_right],
               net[:plato_samegrp], net[:plato_succgrp], net[:plato_predgrp],
               net[:plato_alphabetic_position_category], net[:plato_length])
        set_activation!(nd, MAX_ACTIVATION)
    end
    ts = make_themespace(net)
    ctx = MetacatCtx(net, PyRandom(0), Coderack(), ts,
                     strings[1], strings[2], strings[3], temp, 0)
    update_workspace_values!(ctx)
    dim_at(k) = ts.dimensions[k + 1]
    rel_at(type, k, j) = get_relations(ts, type, dim_at(k))[j + 1]
    # clamp the theme pattern the scouts will work toward
    thematic_pressure_on!(ts)
    for (type, dimension, relation, activation) in theme_spec
        set_theme_activation!(ts, type, dim_at(dimension),
                              rel_at(type, dimension, relation), activation)
    end
    update_dominant_themes!(ts)
    println("THEMES\t",
            slist([slist([theme_ascii_name(th), th.activation])
                   for th in get_all_active_themes(ts)]))
    ctx.rng = PyRandom(seed)
    seed_rack!(ctx)
    c = 0
    while c < n && !coderack_empty(ctx.coderack)
        if c > 0 && c % UPDATE_CYCLE_LENGTH == 0
            seed_rack!(ctx)
        end
        ctx.codelet_count = c
        codelet = choose_codelet!(ctx.coderack, ctx.rng, ctx.temperature)
        print("RUN\t", c, "\t", codelet_type_display(codelet.codelet_type), "\t",
              sround(codelet.relative_urgency), "\t", ctx.coderack.current_num)
        run_codelet!(ctx, codelet)
        println("\t", sum(length(s.bonds) for s in strings), "\t",
                sum(length(s.groups) for s in strings), "\t",
                length(get_all_bridges(ctx)), "\t", length(ts.all_themes), "\t",
                sum(o.average_salience for s in strings for o in objects(s)))
        update_workspace_values!(ctx)
        c += 1
    end
    for bridge_type in (:top, :vertical)
        for b in reverse(get_bridges(ctx, bridge_type))
            println("BRIDGE\t", bridge_type, "\t", ascii_name(b.object1), "\t",
                    ascii_name(b.object2), "\t", yn(b.flipped_group1), "\t",
                    yn(b.flipped_group2), "\t", b.strength, "\t",
                    slist([cm_print_name(cm, net) for cm in b.all_concept_mappings]))
        end
    end
    for s in strings
        for o in objects(s)
            println("OBJ\t", s.string_type, "\t", ascii_name(o), "\t",
                    num(o.raw_importance), "\t", o.average_salience, "\t",
                    slist([descr_print_name(d) for d in all_descriptions(o)]))
        end
        for g in reverse(s.groups)
            gg = g::Group
            println("GROUP\t", s.string_type, "\t", ascii_name(gg), "\t",
                    nm(gg.group_category), "\t", nm(gg.direction), "\t", gg.strength)
        end
    end
    for th in ts.all_themes
        println("THEME\t", TYPE_NAMES[th.theme_type], "\t", theme_ascii_name(th), "\t",
                th.activation, "\t", yn(is_dominant(th)))
    end
    println("WS\t", ctx.top_mapping_strength, "\t", ctx.vertical_mapping_strength, "\t",
            num(get_percentage_of_dominant_themes(ts)))
end

# A variant that builds bonds and whole-string groups FIRST. Two of the thematic
# scout's branches need group objects to exist: a Length theme has no possible
# descriptor for a letter, so propose_description_based_on_theme only posts
# anything when the chosen object is a group; and look_for_auxiliary_slippages
# needs the proposed bridge to carry slippages, which identity mappings between
# letters never do.
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

function grouped_probe(i, m, t, seed, n, temp, theme_spec)
    println("GPROBLEM\t", i, "\t", m, "\t", t, "\t", seed, "\t", n, "\t", temp)
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
               net[:plato_predecessor], net[:plato_sameness], net[:plato_bond_facet],
               net[:plato_bond_category], net[:plato_group_category],
               net[:plato_direction_category], net[:plato_left], net[:plato_right],
               net[:plato_samegrp], net[:plato_succgrp], net[:plato_predgrp],
               net[:plato_alphabetic_position_category], net[:plato_length])
        set_activation!(nd, MAX_ACTIVATION)
    end
    ts = make_themespace(net)
    ctx = MetacatCtx(net, PyRandom(0), Coderack(), ts,
                     strings[1], strings[2], strings[3], temp, 0)
    update_workspace_values!(ctx)
    ctx.rng = PyRandom(seed)
    for s in strings
        build_chain_and_group!(s)
    end
    update_workspace_values!(ctx)
    dim_at(k) = ts.dimensions[k + 1]
    rel_at(type, k, j) = get_relations(ts, type, dim_at(k))[j + 1]
    thematic_pressure_on!(ts)
    for (type, dimension, relation, activation) in theme_spec
        set_theme_activation!(ts, type, dim_at(dimension),
                              rel_at(type, dimension, relation), activation)
    end
    update_dominant_themes!(ts)
    c = 0
    while c < n
        if c % 6 == 0
            for _ in 1:2
                post!(ctx.coderack,
                      make_codelet(CODELET_TYPES[:thematic_bridge_scout],
                                   VERY_HIGH_URGENCY),
                      ctx.codelet_count, ctx.rng, ctx.temperature, ctx)
            end
        end
        ctx.codelet_count = c
        if !coderack_empty(ctx.coderack)
            codelet = choose_codelet!(ctx.coderack, ctx.rng, ctx.temperature)
            print("GRUN\t", c, "\t", codelet_type_display(codelet.codelet_type), "\t",
                  sround(codelet.relative_urgency), "\t", ctx.coderack.current_num)
            run_codelet!(ctx, codelet)
            println("\t", sum(length(s.groups) for s in strings), "\t",
                    length(get_all_bridges(ctx)), "\t", length(ts.all_themes), "\t",
                    sum(o.average_salience for s in strings for o in objects(s)))
        end
        update_workspace_values!(ctx)
        c += 1
    end
    for bridge_type in (:top, :vertical)
        for b in reverse(get_bridges(ctx, bridge_type))
            println("GBRIDGE\t", bridge_type, "\t", ascii_name(b.object1), "\t",
                    ascii_name(b.object2), "\t", yn(b.flipped_group1), "\t",
                    yn(b.flipped_group2), "\t", b.strength, "\t",
                    slist([cm_print_name(cm, net) for cm in b.all_concept_mappings]))
        end
    end
    for s in strings, o in objects(s)
        println("GOBJ\t", s.string_type, "\t", ascii_name(o), "\t",
                o.average_salience, "\t",
                slist([descr_print_name(d) for d in all_descriptions(o)]))
    end
end

# LetterCtgy:identity + StringPos:identity on both bridge types
probe("abc", "abd", "ijk", 5001, 400, 50,
      [(:top_bridge, 0, 3, 100), (:vertical_bridge, 0, 3, 100),
       (:top_bridge, 1, 2, 100), (:vertical_bridge, 1, 2, 100)])
# StringPos:opposite pressure, the case that wants flipped/crossing bridges
probe("abc", "abd", "cba", 5002, 600, 30,
      [(:vertical_bridge, 1, 1, 100), (:vertical_bridge, 3, 0, 100),
       (:top_bridge, 0, 3, 100), (:top_bridge, 1, 2, 100)])
# ObjectCtgy:different, which forces letter<->group correspondences and so
# exercises propose_description_based_on_theme
probe("abc", "abd", "mrrjjj", 5003, 600, 40,
      [(:vertical_bridge, 7, 0, 100), (:vertical_bridge, 0, 3, 90),
       (:top_bridge, 0, 3, 100), (:top_bridge, 6, 3, 80)])
# Length pressure on a string where lengths genuinely differ
probe("abc", "abd", "iijjkk", 5004, 600, 20,
      [(:vertical_bridge, 6, 3, 100), (:vertical_bridge, 1, 2, 90),
       (:top_bridge, 0, 3, 100)])

# StringPos:opposite between abc and cba gives lmost=>rmost slippages, which is
# what look_for_auxiliary_slippages needs something to work from
grouped_probe("abc", "abd", "cba", 5101, 300, 30,
              [(:vertical_bridge, 1, 1, 100), (:vertical_bridge, 6, 3, 100),
               (:top_bridge, 0, 3, 100), (:top_bridge, 1, 2, 100)])
# Length pressure with groups already present, so a Length description is
# possible for the chosen object and propose_description_based_on_theme posts
grouped_probe("abc", "abd", "iijjkk", 5102, 300, 20,
              [(:vertical_bridge, 6, 2, 100), (:vertical_bridge, 7, 0, 100),
               (:top_bridge, 0, 3, 100)])
# abc <-> xyz is the case look_for_auxiliary_slippages exists for: a StringPos
# lmost=>rmost slippage drags an AlphaPos first=>last slippage along with it,
# because leftmost is linked to alphabetic-first and a is alphabetic-first while
# z is alphabetic-last. No other pair of letters reaches that branch.
grouped_probe("abc", "abd", "xyz", 5104, 300, 30,
              [(:vertical_bridge, 1, 1, 100), (:vertical_bridge, 3, 0, 100),
               (:top_bridge, 0, 3, 100)])
grouped_probe("abc", "abd", "zyx", 5105, 300, 20,
              [(:vertical_bridge, 1, 1, 100), (:vertical_bridge, 2, 0, 100),
               (:top_bridge, 0, 3, 100)])

grouped_probe("abcd", "abce", "dcba", 5103, 300, 40,
              [(:vertical_bridge, 1, 1, 100), (:vertical_bridge, 3, 0, 100),
               (:vertical_bridge, 6, 3, 90), (:top_bridge, 0, 3, 100)])
