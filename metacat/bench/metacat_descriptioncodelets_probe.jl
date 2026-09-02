# Julia counterpart of metacat/bench/metacat_descriptioncodelets_probe.ss: the
# description codelet pipeline driven through the real coderack.
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

nm(n) = n === nothing ? "-" : n.lowercase_name

"""raw importance is an exact rational whenever the object sits inside a group"""
num(v) = (x = snorm(v); x isa Integer ? string(x) :
                        string(numerator(x), "/", denominator(x)))

net = build_slipnet()

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
               net[:plato_string_position_category],
               net[:plato_alphabetic_position_category],
               net[:plato_length], net[:plato_alphabetic_first],
               net[:plato_alphabetic_last])
        set_activation!(nd, MAX_ACTIVATION)
    end
    ctx = MetacatCtx(net, PyRandom(0), Coderack(), make_themespace(net),
                     strings[1], strings[2], strings[3], temp, 0)
    TEMPERATURE[] = temp
    update_workspace_values!(strings, nothing, nothing, ctx.themespace)
    ctx.rng = PyRandom(seed)
    for _ in 1:10
        post!(ctx.coderack,
              make_codelet(CODELET_TYPES[:bottom_up_description_scout], VERY_LOW_URGENCY),
              ctx.codelet_count, ctx.rng, ctx.temperature)
        post!(ctx.coderack,
              make_codelet(CODELET_TYPES[:top_down_description_scout], LOW_URGENCY,
                           Any[net[:plato_alphabetic_position_category], nothing]),
              ctx.codelet_count, ctx.rng, ctx.temperature)
        post!(ctx.coderack,
              make_codelet(CODELET_TYPES[:top_down_description_scout], MEDIUM_URGENCY,
                           Any[net[:plato_string_position_category], strings[3]]),
              ctx.codelet_count, ctx.rng, ctx.temperature)
    end
    c = 0
    while c < n && !coderack_empty(ctx.coderack)
        ctx.codelet_count = c
        codelet = choose_codelet!(ctx.coderack, ctx.rng, ctx.temperature)
        println("RUN\t", c, "\t", codelet_type_display(codelet.codelet_type), "\t",
                sround(codelet.relative_urgency), "\t", ctx.coderack.current_num)
        run_codelet!(ctx, codelet)
        update_workspace_values!(strings, ctx.rng, net, ctx.themespace)
        c += 1
    end
    for s in strings, o in objects(s)
        for d in all_descriptions(o)
            println("DESCR\t", s.string_type, "\t", ascii_name(o), "\t",
                    descr_print_name(d), "\t", d.proposal_level, "\t", d.strength)
        end
        println("OBJ\t", s.string_type, "\t", ascii_name(o), "\t",
                num(o.raw_importance), "\t", o.relative_importance, "\t",
                o.average_salience)
    end
    for node in net.nodes
        node.activation == 0 || println("ACT\t", nm(node), "\t", node.activation)
    end
end

descr_print_name(d::Description) = string(d.description_type.short_name, ":",
                                          d.descriptor.short_name)

probe("abc", "abd", "ijk", 2001, 60, 50)
probe("abc", "abd", "mrrjjj", 2002, 90, 30)
probe("abcde", "abcdf", "pqrst", 2003, 120, 80)
