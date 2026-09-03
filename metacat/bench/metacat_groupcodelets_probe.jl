# Julia counterpart of metacat/bench/metacat_groupcodelets_probe.ss: the group
# codelet pipeline driven through the real coderack, interleaved with bond
# scouts so groups have bonds to scan and bonds to fight.
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

nm(n) = n === nothing ? "-" : n.lowercase_name
num(v) = (x = snorm(v); x isa Integer ? string(x) :
                        string(numerator(x), "/", denominator(x)))
descr_print_name(d::Description) = string(d.description_type.short_name, ":",
                                          d.descriptor.short_name)
net = build_slipnet()

function seed_rack!(ctx::MetacatCtx, strings)
    for _ in 1:4
        post!(ctx.coderack,
              make_codelet(CODELET_TYPES[:bottom_up_bond_scout], VERY_LOW_URGENCY),
              ctx.codelet_count, ctx.rng, ctx.temperature)
        post!(ctx.coderack,
              make_codelet(CODELET_TYPES[:group_scout_whole_string], LOW_URGENCY),
              ctx.codelet_count, ctx.rng, ctx.temperature)
        post!(ctx.coderack,
              make_codelet(CODELET_TYPES[:top_down_group_scout_category], MEDIUM_URGENCY,
                           Any[ctx.net[:plato_succgrp], nothing]),
              ctx.codelet_count, ctx.rng, ctx.temperature)
        post!(ctx.coderack,
              make_codelet(CODELET_TYPES[:top_down_group_scout_category], MEDIUM_URGENCY,
                           Any[ctx.net[:plato_samegrp], strings[3]]),
              ctx.codelet_count, ctx.rng, ctx.temperature)
        post!(ctx.coderack,
              make_codelet(CODELET_TYPES[:top_down_group_scout_direction], LOW_URGENCY,
                           Any[ctx.net[:plato_right], nothing]),
              ctx.codelet_count, ctx.rng, ctx.temperature)
    end
    return ctx
end

function probe(i, m, t, seed, n, temp)
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
               net[:plato_length])
        set_activation!(nd, MAX_ACTIVATION)
    end
    ctx = MetacatCtx(net, PyRandom(0), Coderack(), make_themespace(net),
                     strings[1], strings[2], strings[3], temp, 0)
    TEMPERATURE[] = temp
    update_workspace_values!(strings, nothing, nothing, ctx.themespace)
    ctx.rng = PyRandom(seed)
    # A real run replenishes the rack from add-bottom-up-codelets every update
    # cycle. Without that the rack drains after the seed batch and the builders
    # barely run, so the probe reseeds on the same cadence.
    seed_rack!(ctx, strings)
    c = 0
    while c < n && !coderack_empty(ctx.coderack)
        if c > 0 && c % UPDATE_CYCLE_LENGTH == 0
            seed_rack!(ctx, strings)
        end
        ctx.codelet_count = c
        codelet = choose_codelet!(ctx.coderack, ctx.rng, ctx.temperature)
        print("RUN\t", c, "\t", codelet_type_display(codelet.codelet_type), "\t",
              sround(codelet.relative_urgency), "\t", ctx.coderack.current_num)
        run_codelet!(ctx, codelet)
        # a workspace fingerprint after every codelet, so a divergence localises
        # to the codelet that caused it rather than to the first codelet whose
        # NAME happens to differ
        println("\t", sum(length(s.bonds) for s in strings), "\t",
                sum(length(s.groups) for s in strings), "\t",
                sum(length(s.groups) + length(s.proposed_groups) for s in strings), "\t",
                sum(o.intra_string_salience for s in strings for o in objects(s)))
        update_workspace_values!(strings, ctx.rng, net, ctx.themespace)
        c += 1
    end
    for s in strings
        for b in reverse(s.bonds)
            bb = b::Bond
            println("BOND\t", s.string_type, "\t", ascii_name(bb.left_object), "\t",
                    ascii_name(bb.right_object), "\t", nm(bb.bond_category), "\t",
                    nm(bb.direction), "\t", nm(bb.bond_facet), "\t", bb.strength)
        end
        for g in reverse(s.groups)
            gg = g::Group
            println("GROUP\t", s.string_type, "\t", ascii_name(gg), "\t",
                    nm(gg.group_category), "\t", nm(gg.direction), "\t",
                    nm(gg.group_bond_facet), "\t", gg.group_length, "\t",
                    get_letter_span(gg), "\t", gg.strength)
            for d in all_descriptions(gg)
                println("GDESCR\t", s.string_type, "\t", ascii_name(gg), "\t",
                        descr_print_name(d))
            end
        end
        println("PROPOSED\t", s.string_type, "\t", length(s.groups) + length(s.proposed_groups))
        for o in objects(s)
            println("OBJ\t", s.string_type, "\t", ascii_name(o), "\t",
                    num(o.raw_importance), "\t", o.intra_string_unhappiness, "\t",
                    o.intra_string_salience, "\t",
                    o.enclosing_group === nothing ? "-" : "in")
        end
    end
    for node in net.nodes
        node.activation == 0 || println("ACT\t", nm(node), "\t", node.activation)
    end
end

probe("abc", "abd", "ijk", 3001, 300, 50)
probe("abc", "abd", "mrrjjj", 3002, 600, 40)
probe("abcde", "abcdf", "pqrst", 3003, 600, 60)
probe("abc", "cba", "iijjkk", 3004, 800, 30)
probe("abc", "abd", "iijjkkll", 3005, 900, 20)
probe("aabbcc", "aabbcd", "mmrrjjjj", 3006, 900, 70)
