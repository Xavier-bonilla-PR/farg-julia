# Julia counterpart of metacat/bench/metacat_patterns_probe.ss.
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
include("../julia/src/rules.jl")
include("../julia/src/answers.jl")
include("../julia/src/trace.jl")

nm(n) = n === nothing ? "-" : n.lowercase_name
sn(n) = n === nothing ? "*" : n.short_name
yn(b) = b ? "y" : "n"
join_or_dash(xs) = isempty(xs) ? "-" : join(xs, ",")
net = build_slipnet()
ts = make_themespace(net)

# Scheme spells the pattern and codelet type names with hyphens and a colon.
pname(s::Symbol) = replace(replace(String(s), "_scout_whole_string" => "-scout:whole-string"),
                           "_" => "-")
ctname(t::CodeletType) =
    replace(replace(String(t.name), "_scout_category" => "-scout:category"),
            "_scout_direction" => "-scout:direction") |>
    x -> replace(replace(x, "_scout_whole_string" => "-scout:whole-string"), "_" => "-")

lcat = net[:plato_letter_category]
spos = net[:plato_string_position_category]
dir = net[:plato_direction_category]
otype = net[:plato_object_category]
len = net[:plato_length]
gtype = net[:plato_group_category]
iden = net[:plato_identity]
opp = net[:plato_opposite]
succ = net[:plato_successor]
pred = net[:plato_predecessor]

function entry_tag(pattern_type, entry)
    pattern_type === :concepts && return string(sn(entry[1]), "=", entry[2])
    pattern_type === :codelets && return string(ctname(entry[1]), "=", entry[2])
    return string(sn(entry[1]), "/", nm(entry[2]),
                  length(entry) == 3 ? string("@", entry[3]) : "")
end

pattern_tag(pattern) =
    string("(", pname(pattern[1]), " ",
           join_or_dash([entry_tag(pattern[1], e) for e in entries(pattern)]), ")")

#----------------------------------------------------------- pattern types ---

println("SECTION\ttypes")

tp1 = Any[:top_bridge, Any[lcat, succ], Any[spos, iden]]
tp2 = Any[:top_bridge, Any[spos, iden], Any[lcat, succ]]
tp3 = Any[:top_bridge, Any[lcat, succ, 80], Any[spos, iden, 40]]
tp4 = Any[:top_bridge, Any[lcat, succ], Any[spos, opp]]
tp5 = Any[:vertical_bridge, Any[lcat, succ], Any[spos, iden]]
tp6 = Any[:top_bridge, Any[lcat, succ]]
tp7 = Any[:top_bridge, Any[lcat, nothing], Any[otype, iden]]
cp1 = Any[:concepts, Any[lcat, 100], Any[spos, 100]]
cp2 = Any[:concepts, Any[spos, 50], Any[lcat, 20]]
cp3 = Any[:concepts, Any[lcat, 100], Any[dir, 100]]
kp1 = Any[:codelets, Any[ct(:bond_evaluator), HIGH_URGENCY],
                     Any[ct(:bond_builder), HIGH_URGENCY]]
kp2 = Any[:codelets, Any[ct(:bond_builder), LOW_URGENCY],
                     Any[ct(:bond_evaluator), LOW_URGENCY]]
kp3 = Any[:codelets, Any[ct(:bond_evaluator), HIGH_URGENCY],
                     Any[ct(:rule_scout), HIGH_URGENCY]]

all_patterns = [("tp1", tp1), ("tp2", tp2), ("tp3", tp3), ("tp4", tp4),
                ("tp5", tp5), ("tp6", tp6), ("tp7", tp7),
                ("cp1", cp1), ("cp2", cp2), ("cp3", cp3),
                ("kp1", kp1), ("kp2", kp2), ("kp3", kp3)]

for (n, p) in all_patterns
    println("PAT\t", n, "\t", pattern_tag(p), "\ttheme=", yn(is_theme_pattern(p)),
            "\tconcept=", yn(is_concept_pattern(p)), "\tcodelet=",
            yn(is_codelet_pattern(p)), "\tn=", length(entries(p)))
end

#-------------------------------------------------------------- comparison ---

println("SECTION\tequality")
for (n1, p1) in all_patterns
    for (n2, p2) in all_patterns
        println("EQ\t", n1, "\t", n2, "\t", yn(same_pattern_type(p1, p2)), "\t",
                yn(patterns_equal(p1, p2)))
    end
end

println("SECTION\tpresent")
pattern_sets = [("none", Any[]), ("themes", Any[tp1]), ("concepts", Any[cp1]),
                ("mixed", Any[tp1, cp1, kp1])]
for (n, p) in all_patterns
    for (sn_, set) in pattern_sets
        println("PRESENT\t", n, "\t", sn_, "\t", yn(pattern_type_present(p, set)))
    end
end

#--------------------------------------------------------------- negation ---

println("SECTION\tnegate")
for (n, p) in [("tp1", tp1), ("tp3", tp3), ("tp7", tp7)]
    for e in entries(p)
        println("NEG\t", n, "\t", entry_tag(:top_bridge, e), "\t",
                entry_tag(:top_bridge, negate_theme_pattern_entry(e)))
    end
end

#------------------------------------------------- associated concept pattern ---

println("SECTION\tassociated")
for (n, p) in [("tp1", tp1), ("tp3", tp3), ("tp4", tp4), ("tp7", tp7),
               ("tpneg", Any[:top_bridge, Any[spos, opp, -60], Any[lcat, succ, 50]])]
    println("ASSOC\t", n, "\t", pattern_tag(get_associated_concept_pattern(p, net)))
end

#----------------------------------------------------------- theme clamping ---

println("SECTION\tthemeclamp")

function dump_themes(tag)
    for type in (:top_bridge, :bottom_bridge, :vertical_bridge)
        themes = get_themes(ts, type)
        println("TH\t", tag, "\t", pname(type), "\t",
                join_or_dash([string(theme_ascii_name(th), "@", th.activation)
                              for th in themes]),
                "\tfrozen=", yn(theme_type_frozen(ts, type)),
                "\tpressure=", yn(has_thematic_pressure(ts, type)))
    end
end

initialize!(ts)
dump_themes("initial")
impose_theme_pattern!(ts, tp3)
dump_themes("imposed")
clamp_theme_pattern!(ts, tp4)
dump_themes("clamped")
clamp_theme_pattern!(ts, tp5)
dump_themes("clamped-vertical")
unclamp_theme_pattern!(ts, tp4)
dump_themes("unclamped")
initialize!(ts)
dump_themes("reinitialized")

#--------------------------------------------------------- concept clamping ---

println("SECTION\tconceptclamp")

function dump_concepts(tag, nodes)
    for n in nodes
        println("CN\t", tag, "\t", sn(n), "\tact=", n.activation, "\tfrozen=",
                yn(n.frozen))
    end
end

watched = [lcat, spos, dir]
foreach(reset!, net.nodes)
dump_concepts("initial", watched)
clamp_concept_pattern!(cp1)
dump_concepts("clamped", watched)
for n in watched
    set_activation!(n, 7)
end
dump_concepts("after-set", watched)
unclamp_concept_pattern!(cp1)
dump_concepts("unclamped", watched)
for n in watched
    set_activation!(n, 7)
end
dump_concepts("after-set2", watched)

#--------------------------------------------------------- codelet clamping ---

println("SECTION\tcodeletclamp")

function dump_codelet_types(tag, types)
    for t in types
        println("CT\t", tag, "\t", ctname(t), "\tclamped=", yn(t.urgency_clamped),
                "\turgency=", t.urgency_clamped ? string(t.clamped_relative_urgency) : "-")
    end
end

println("NTYPES\t", length(all_codelet_types()))
println("TYPES\t", join_or_dash([ctname(t) for t in all_codelet_types()]))

watched_types = [ct(:bond_evaluator), ct(:bond_builder), ct(:rule_scout),
                 ct(:breaker)]
dump_codelet_types("initial", watched_types)

strings = [make_workspace_string(net, :initial, "abc"),
           make_workspace_string(net, :modified, "abd"),
           make_workspace_string(net, :target, "ijk")]
ctx = MetacatCtx(net, PyRandom(1), Coderack(), ts, strings[1], strings[2],
                 strings[3], 100, 0)
post_one(name, urgency) =
    post!(ctx.coderack, make_codelet(ct(name), urgency), ctx.codelet_count,
          ctx.rng, ctx.temperature, ctx)
post_one(:bond_evaluator, VERY_LOW_URGENCY)
post_one(:bond_builder, VERY_LOW_URGENCY)
post_one(:rule_scout, VERY_LOW_URGENCY)

# A coderack bin has no number accessor in the Scheme, so bin membership is
# observed through the per-bin counts instead.
function dump_rack(tag)
    for c in reverse(ctx.coderack.codelet_list)
        println("CD\t", tag, "\t", ctname(c.codelet_type), "\turg=",
                c.relative_urgency)
    end
    println("BINS\t", tag, "\t",
            join_or_dash([string(b.current_index) for b in ctx.coderack.bins]))
end

dump_rack("posted")
clamp_codelet_pattern!(kp1, ctx.coderack, ctx.codelet_count)
dump_codelet_types("clamped", watched_types)
dump_rack("clamped")
post_one(:bond_evaluator, VERY_LOW_URGENCY)
dump_rack("posted-while-clamped")
unclamp_codelet_pattern!(kp1, ctx.coderack, ctx.codelet_count)
dump_codelet_types("unclamped", watched_types)
dump_rack("unclamped")

println("SECTION\tcomplement")
comp1 = get_complement_codelet_pattern(LOW_URGENCY, Any[kp1])
comp2 = get_complement_codelet_pattern(MEDIUM_URGENCY, Any[kp1, kp3])
println("COMP\tkp1\t", length(entries(comp1)), "\t", pattern_tag(comp1))
println("COMP\tkp1+kp3\t", length(entries(comp2)), "\t", pattern_tag(comp2))
bg = against_background(LOW_URGENCY, kp1)
println("BG\t", length(entries(bg)), "\t", pattern_tag(bg))

println("SECTION\tstandard")
for (n, p) in [("topdown", top_down_codelet_pattern()),
               ("bottomup", bottom_up_codelet_pattern()),
               ("thematic", thematic_codelet_pattern()),
               ("rule", rule_codelet_pattern()),
               ("bond", bond_codelet_pattern()),
               ("group", group_codelet_pattern()),
               ("bridge", bridge_codelet_pattern()),
               ("description", description_codelet_pattern()),
               ("answer", answer_codelet_pattern())]
    println("STD\t", n, "\t", length(entries(p)), "\t", pattern_tag(p))
end
println("STDEQ\tbond-vs-bond\t",
        yn(patterns_equal(bond_codelet_pattern(), bond_codelet_pattern())))
println("STDEQ\tbond-vs-group\t",
        yn(patterns_equal(bond_codelet_pattern(), group_codelet_pattern())))
