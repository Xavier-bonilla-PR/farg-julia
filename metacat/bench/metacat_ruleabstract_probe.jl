# Julia counterpart of metacat/bench/metacat_ruleabstract_probe.ss: rules read
# off the horizontal bridges a real coderack run happened to build.
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
include("../julia/src/rules.jl")

nm(n) = n === nothing ? "-" : n.lowercase_name
sn(n) = n === nothing ? "*" : n.short_name
yn(b) = b ? "y" : "n"
slist(xs) = string("(", join(xs, " "), ")")
net = build_slipnet()

object_tag(o) = o isa WorkspaceString ? string("string:", o.string_type) : ascii_name(o)

function seed_rack!(ctx::MetacatCtx)
    post(name, urgency, args = Any[]) =
        post!(ctx.coderack, make_codelet(CODELET_TYPES[name], urgency, args),
              ctx.codelet_count, ctx.rng, ctx.temperature, ctx)
    for _ in 1:3
        post(:bottom_up_bond_scout, VERY_LOW_URGENCY)
        post(:group_scout_whole_string, LOW_URGENCY)
        post(:top_down_group_scout_category, LOW_URGENCY,
             Any[ctx.net[:plato_succgrp], nothing])
        post(:top_down_group_scout_category, LOW_URGENCY,
             Any[ctx.net[:plato_samegrp], nothing])
        post(:bottom_up_bridge_scout, MEDIUM_URGENCY)
        post(:bottom_up_bridge_scout, MEDIUM_URGENCY)
        post(:important_object_bridge_scout, MEDIUM_URGENCY)
        post(:bottom_up_description_scout, VERY_LOW_URGENCY)
    end
    return ctx
end

# ------------------------------------ printing ------------------------------------

function print_change_description(cd)
    if cd isa IntrinsicChangeDescription
        println("  CD\tintrinsic\t", object_tag(cd.reference_object), "\t", cd.scope,
                "\t", sn(cd.dimension), "\t", sn(cd.descriptor1), "\t",
                sn(cd.descriptor2), "\t", slist([sn(d) for d in cd.descriptors]))
    else
        println("  CD\textrinsic\t",
                slist([object_tag(o) for o in cd.reference_objects]), "\t",
                sn(cd.dimension), "\tsubswap=", yn(cd.subobjects_swap))
    end
end

function print_template(t::RuleClauseTemplate)
    if is_intrinsic_template(t)
        println("  TMPL\tintrinsic\t", object_tag(t.ref_object))
        for ct in t.change_templates
            println("    CT\t", ct.scope, "\t", sn(ct.dimension), "\t",
                    slist([sn(d) for d in ct.descriptors]))
        end
    else
        println("  TMPL\textrinsic\t", slist([object_tag(o) for o in t.ref_objects]),
                "\t", slist([sn(d) for d in t.dimensions]))
    end
end

function print_clause(rc::RuleClause)
    if is_verbatim_clause(rc)
        println("  RC\tVERBATIM\t", slist([nm(n) for n in rc.letter_categories]))
    elseif is_intrinsic_clause(rc)
        println("  RC\tCHANGE\t", format_object_description(rc.object_descriptions[1]))
        for c in rc.changes
            println("    CH\t(", c.scope, " ", sn(c.dimension), " ", sn(c.descriptor),
                    ")")
        end
    else
        println("  RC\tSWAP\t",
                slist([format_object_description(od) for od in rc.object_descriptions]),
                "\t", slist([sn(d) for d in rc.dimensions]))
    end
end

const SNAG = Symbol[]
record_snag(r) = (push!(SNAG, r[1]); :done)

# -------------------------------------- probe --------------------------------------

function abstract_once(trial, describable, ctx::MetacatCtx)
    println(" TRIAL\t", trial)
    all_cds = abstract_change_descriptions(describable, ctx.rng, net)
    final_cds = remove_redundant_change_descriptions(all_cds, net)
    println("  NCD\tall=", length(all_cds), "\tfinal=", length(final_cds))
    foreach(print_change_description, all_cds)
    println("  ---kept---")
    foreach(print_change_description, final_cds)
    classes = spartition(change_descriptions_groupable, final_cds)
    templates = sort_templates(RuleClauseTemplate[
        change_descriptions_to_rule_clause_template(cls, net) for cls in classes])
    println("  NTMPL\t", length(templates))
    foreach(print_template, templates)
    if !possible_to_instantiate(templates, net)
        println("  INSTANTIABLE\tn")
        return
    end
    println("  INSTANTIABLE\ty")
    clauses = RuleClause[chez_map(t -> instantiate_rule_clause_template(t, ctx.rng, net),
                                  templates)...]
    r = make_rule(:top, clauses, ctx.initial_string, net)
    foreach(print_clause, clauses)
    set_quality_values!(r, net)
    println("  RULEQ\tunif=", r.uniformity, "\tabst=", r.abstractness,
            "\tsucc=", r.succinctness, "\tintr=", r.intrinsic_quality,
            "\tqual=", r.quality, "\tchar=", rule_characterization(r, net))
    for line in r.english_transcription
        println("  EN\t|", line, "|")
    end
    empty!(SNAG)
    result = apply_rule(r, ctx.initial_string, net, record_snag)
    println("  APPLIED\t",
            result === nothing ? "failed" : string("ok:", length(result)), "\t",
            slist(SNAG))
    println("  IMAGE\t",
            join([n.lowercase_name for n in generate_image_letters(ctx.initial_string)]))
    println("  WORKS\t",
            yn(result !== nothing &&
               generate_image_letters(ctx.initial_string) ==
               ctx.modified_string.letter_categories))
    reset_image!(get_image(ctx.initial_string))
end

function probe(i, m, t, seed, n, temp, trials)
    println("PROBLEM\t", i, "\t", m, "\t", t, "\t", seed, "\t", n, "\t", temp, "\t",
            trials)
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
    ctx = MetacatCtx(net, PyRandom(0), Coderack(), make_themespace(net),
                     strings[1], strings[2], strings[3], temp, 0)
    update_workspace_values!(ctx)
    ctx.rng = PyRandom(seed)
    seed_rack!(ctx)
    c = 0
    while c < n && !coderack_empty(ctx.coderack)
        if c > 0 && c % UPDATE_CYCLE_LENGTH == 0
            seed_rack!(ctx)
        end
        ctx.codelet_count = c
        run_codelet!(ctx, choose_codelet!(ctx.coderack, ctx.rng, ctx.temperature))
        update_workspace_values!(ctx)
        c += 1
    end
    top_bridges = reverse(get_bridges(ctx, :top))
    describable = Bridge[b for b in top_bridges if rule_describable_bridge(b, net)]
    println("BRIDGES\ttop=", length(top_bridges), "\tdescribable=", length(describable))
    for b in top_bridges
        println(" B\t", object_tag(b.object1), "\t", object_tag(b.object2),
                "\tdescribable=", yn(rule_describable_bridge(b, net)),
                "\tslippages=", length(get_non_symmetric_non_bond_slippages(b)),
                "\tstrposopp=", yn(strposctgy_opposite_slippage(b, net)))
    end
    clusters = spartition(same_left_enclosing_objects, describable)
    println("CLUSTERS\t", length(clusters))
    for cl in clusters
        println(" CL\t", slist([object_tag(b.object1) for b in cl]),
                "\tleft=", object_tag(get_left_enclosing_object(cl)),
                "\tspansL=", yn(spans_left_side(cl)),
                "\tcommonR=", yn(common_right_enclosing_object(cl)),
                "\tspansR=", yn(common_right_enclosing_object(cl) &&
                                spans_right_side(cl)),
                "\tschemas=", slist([string(sn(s.dimension), ":", sn(s.descriptor1),
                                            ":", sn(s.relation), ":", sn(s.descriptor2))
                                     for s in get_common_change_schemas(cl, net)]))
        for sw in get_all_swaps(cl)
            println(" SWAP\t", slist([object_tag(o) for o in sw.objects]), "\t",
                    sn(sw.dimension), "\t", slist([sn(d) for d in sw.descriptors]))
        end
    end
    for k in 1:trials
        abstract_once(k, describable, ctx)
    end
end

probe("abc", "abd", "ijk", 91, 400, 40, 6)
probe("abc", "abd", "ijk", 92, 700, 20, 6)
probe("aabc", "aabd", "ijkk", 93, 700, 30, 6)
probe("abc", "cba", "pqrs", 94, 900, 30, 10)
probe("mrrjjj", "mrrkkk", "xyz", 95, 900, 30, 6)
probe("eqe", "qqq", "abc", 96, 700, 50, 6)
# strings chosen for the extrinsic path: a modified string that trades
# descriptors with the initial one is what an abstracted SWAP is read off
probe("aabb", "bbaa", "ijkk", 97, 1200, 30, 10)
probe("abcd", "abdc", "xyz", 98, 1200, 25, 10)
probe("abcde", "abcdf", "ijklm", 99, 1200, 35, 8)
probe("aabbcc", "ccbbaa", "mrrjjj", 100, 1400, 30, 10)
