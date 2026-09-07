# Ported from Metacat's themes.ss.
#
# The themespace is what makes Metacat more than Copycat. A THEME is a claim
# about how one dimension of the mapping works - "letter-category maps by
# successor", "string-position maps by opposite" - and it carries an activation
# in -100..+100. Positive themes assert the relation; negative themes assert
# that it does NOT hold. Bridges boost the themes their concept mappings
# realise, and in return every workspace structure's strength is pulled toward
# 100 (or 0) in proportion to how well it fits the themes currently active.
# That feedback loop is the "self-watching" pressure of the model.
#
# Themes live in CLUSTERS, one per (theme-type, dimension) pair: three theme
# types (top-bridge, bottom-bridge, vertical-bridge) over the nine category
# nodes of the slipnet, so 27 clusters. Within a cluster the themes inhibit and
# excite each other through a small recurrent net, which is what lets one
# relation per dimension win and become DOMINANT.
#
# Deferred, and marked where they arise: the thematic codelets
# (thematic-bridge-scout and friends, which need the bridge and description
# codelets first), state save/restore for the GUI's history browser, and
# graphics.

const MAX_THEME_ACTIVATION = 100
const DOMINANT_THEME_MARGIN = 90
const THEME_SPREAD_AMOUNT = 20
const THEME_BOOST_AMOUNT = 7
const THEME_DECAY_AMOUNT = 25

# Intra-cluster theme weights (< 0 = inhibitory, > 0 = excitatory).
const NEGATIVE_TO_NEGATIVE_WEIGHT = 0
const NEGATIVE_TO_POSITIVE_WEIGHT = 25
const POSITIVE_TO_NEGATIVE_WEIGHT = -75
const POSITIVE_TO_POSITIVE_WEIGHT = -2
const SELF_TO_SELF_WEIGHT = 10

clip_positive(x) = max(0, min(x, MAX_THEME_ACTIVATION))
clip_negative(x) = max(-MAX_THEME_ACTIVATION, min(x, 0))

# --- themes and clusters ----------------------------------------------------
#
# Theme and ThemeCluster are mutually recursive, so Theme is parametrised on
# its cluster type the way Slipnode is parametrised on its link type.

mutable struct Theme{C}
    theme_type::Symbol                    # :top_bridge | :bottom_bridge | :vertical_bridge
    dimension::Node
    """`#f` here is the DIFFERENCE theme: "this dimension maps by no relation
    at all", which is a claim in its own right, not the absence of a theme."""
    relation::Union{Nothing,Node}
    activation::Int
    net_input_buffer::Union{Int,Rational{Int}}
    cluster::Union{Nothing,C}
    outgoing_theme_links::Vector{Theme{C}}
    frozen::Bool
end

mutable struct ThemeCluster
    theme_type::Symbol
    dimension::Node
    relations::Vector{Union{Nothing,Node}}
    """`alpha` scales the sigmoid that turns net input into an activation step.
    NB: the Scheme computes it once, inside the `let*` that closes over
    `sensitivity`, so `set-sensitivity` never reaches it. Storing the number
    rather than the sensitivity reproduces that."""
    alpha::Float64
    themes::Vector{Theme{ThemeCluster}}
    dominant_theme::Union{Nothing,Theme{ThemeCluster}}
    frozen::Bool
end

const BridgeTheme = Theme{ThemeCluster}

theme_type_matches(t::BridgeTheme, type::Symbol) = t.theme_type === type
theme_type_matches(t::BridgeTheme, types) = any(x -> x === t.theme_type, types)

absolute_activation(t::BridgeTheme) = abs(t.activation)
positive_activation(t::BridgeTheme) = max(0, t.activation)
is_negative_theme(t::BridgeTheme) = t.activation < 0
difference_theme(t::BridgeTheme) = t.relation === nothing
"""`(frozen?)` - a theme in a frozen cluster is frozen even if not individually
frozen."""
is_frozen(t::BridgeTheme) = t.frozen || (t.cluster::ThemeCluster).frozen
is_dominant(t::BridgeTheme) = (t.cluster::ThemeCluster).dominant_theme === t

theme_ascii_name(t::BridgeTheme) =
    string(t.dimension.short_name, ":",
           t.relation === nothing ? "different" : (t.relation::Node).lowercase_name)

"""`(get-possible-relations theme-type dimension)` - every label that holds
between two instances of the dimension, `#f` (difference) included. The
cross product is row-major, and `remq-duplicates` keeps the LAST of each
duplicate group, not the first."""
function get_possible_relations(dimension::Node, net::Slipnet)
    nodes = instance_nodes(dimension)
    labels = Union{Nothing,Node}[]
    for n1 in nodes, n2 in nodes
        push!(labels, label_between(n1, n2, net[:plato_identity]))
    end
    return Union{Nothing,Node}[l for (i, l) in enumerate(labels)
                               if !any(x -> x === l, labels[(i + 1):end])]
end

function make_theme_cluster(theme_type::Symbol, dimension::Node, net::Slipnet)
    relations = get_possible_relations(dimension, net)
    sensitivity = 1.0
    alpha = sensitivity * (1 // 50) * sdiv(1, length(relations))
    return ThemeCluster(theme_type, dimension, relations, alpha,
                        BridgeTheme[], nothing, false)
end

"""The amount of inhibitory (-) or excitatory (+) activation flowing across a
link from a theme with activation `a1` to one with activation `a2`."""
function propagation_function(a1::Int, a2::Int)
    weight = a1 < 0 && a2 < 0 ? NEGATIVE_TO_NEGATIVE_WEIGHT :
             a1 < 0           ? NEGATIVE_TO_POSITIVE_WEIGHT :
             a2 < 0           ? POSITIVE_TO_NEGATIVE_WEIGHT :
                                POSITIVE_TO_POSITIVE_WEIGHT
    return snorm(abs(a1) * pct(weight))
end

self_excitation_function(a::Int) = a > 0 ? snorm(a * pct(SELF_TO_SELF_WEIGHT)) : 0

"""Squashes the raw net input into a step in (-N,+N), N being the largest
activation change one cycle allows."""
net_effect(c::ThemeCluster, net_input) = sround(THEME_SPREAD_AMOUNT * tanh(c.alpha * net_input))

"""Inhibiting a theme pulls its activation toward zero whichever side of zero
it sits on; exciting it pushes it toward the corresponding extreme."""
function activation_function(c::ThemeCluster, net_input, activation::Int)
    return activation < 0 ? clip_negative(activation - net_effect(c, net_input)) :
                            clip_positive(activation + net_effect(c, net_input))
end

get_theme(c::ThemeCluster, relation::Union{Nothing,Node}) =
    (i = findfirst(t -> t.relation === relation, c.themes);
     i === nothing ? nothing : c.themes[i])

get_max_positive_theme_activation(c::ThemeCluster) =
    isempty(c.themes) ? 0 : maximum(positive_activation, c.themes)

"""`(pick-positive-theme)` - stochastic-pick weighted by positive activation."""
pick_positive_theme(rng::PyRandom, c::ThemeCluster) =
    isempty(c.themes) ? nothing :
    stochastic_pick(rng, c.themes, [positive_activation(t) for t in c.themes])

"""`(freeze)` - freezing a cluster freezes every theme in it, and blocks new
themes from being added."""
freeze!(c::ThemeCluster) = (c.frozen = true; c)
function unfreeze!(c::ThemeCluster)
    c.frozen = false
    for t in c.themes
        t.frozen = false
    end
    return c
end

"""`(update-dominant-theme)` - a theme is dominant only when it is positive AND
clears the next-strongest theme by more than the margin. The sort is stable, as
Chez's is, so ties keep insertion order."""
function update_dominant_theme!(c::ThemeCluster)
    if isempty(c.themes)
        c.dominant_theme = nothing
        return c
    end
    ranked = sort(c.themes, lt = (a, b) -> absolute_activation(a) > absolute_activation(b),
                  alg = MergeSort)
    runner_up = length(ranked) == 1 ? 0 : absolute_activation(ranked[2])
    c.dominant_theme =
        (ranked[1].activation > 0 &&
         absolute_activation(ranked[1]) - runner_up > DOMINANT_THEME_MARGIN) ?
        ranked[1] : nothing
    return c
end

"""One cycle of the cluster's recurrent net: every theme deposits into every
other theme's buffer, then every theme reads its own buffer. Buffers are
cleared for the whole cluster first, so the step is synchronous."""
function spread_activation!(c::ThemeCluster)
    for t in c.themes
        t.net_input_buffer = 0
    end
    for t in c.themes
        spread_activation!(t)
    end
    for t in c.themes
        update_theme_activation!(t)
    end
    return c
end

function spread_activation!(t::BridgeTheme)
    for other in t.outgoing_theme_links
        other.net_input_buffer =
            snorm(other.net_input_buffer + propagation_function(t.activation, other.activation))
    end
    t.net_input_buffer = snorm(t.net_input_buffer + self_excitation_function(t.activation))
    t.net_input_buffer = snorm(t.net_input_buffer - THEME_DECAY_AMOUNT)
    return t
end

function update_theme_activation!(t::BridgeTheme)
    if !is_frozen(t)
        t.activation = activation_function(t.cluster::ThemeCluster, t.net_input_buffer,
                                           t.activation)
    end
    t.net_input_buffer = 0
    return t
end

"""`(boost-activation factor)` - what a bridge does to the themes its concept
mappings realise. Only ever pushes upward, and only on positive activations."""
function boost_activation!(t::BridgeTheme, factor)
    if !is_frozen(t)
        t.activation = clip_positive(sround(t.activation + pct(factor) * THEME_BOOST_AMOUNT))
    end
    return t
end

"""`(add-theme relation)` - a new theme is fully connected to the ones already
in the cluster. Both link lists and the cluster's own theme list are CONSed."""
function add_theme!(c::ThemeCluster, relation::Union{Nothing,Node})
    any(r -> r === relation, c.relations) || return nothing
    theme = BridgeTheme(c.theme_type, c.dimension, relation, 0, 0, nothing,
                        BridgeTheme[], false)
    for other in c.themes
        pushfirst!(other.outgoing_theme_links, theme)
        pushfirst!(theme.outgoing_theme_links, other)
    end
    theme.cluster = c
    pushfirst!(c.themes, theme)
    return theme
end

function delete_theme!(c::ThemeCluster, theme::BridgeTheme)
    filter!(t -> t !== theme, c.themes)
    for other in c.themes
        filter!(t -> t !== theme, other.outgoing_theme_links)
    end
    update_dominant_theme!(c)
    return c
end

function delete_themes!(c::ThemeCluster)
    empty!(c.themes)
    c.dominant_theme = nothing
    return c
end

# --- the themespace ---------------------------------------------------------

mutable struct Themespace
    dimensions::Vector{Node}
    top_clusters::Vector{ThemeCluster}
    bottom_clusters::Vector{ThemeCluster}
    vertical_clusters::Vector{ThemeCluster}
    all_clusters::Vector{ThemeCluster}
    all_themes::Vector{BridgeTheme}
    """Theme types currently exerting thematic pressure. Themes outside these
    types still hold activation; they just do not weigh on anything."""
    active_theme_types::Vector{Symbol}
end

const ALL_THEME_TYPES = Symbol[:top_bridge, :bottom_bridge, :vertical_bridge]

function make_themespace(net::Slipnet)
    dimensions = Node[n for n in net.nodes if is_category(n)]
    top = [make_theme_cluster(:top_bridge, d, net) for d in dimensions]
    bottom = [make_theme_cluster(:bottom_bridge, d, net) for d in dimensions]
    vertical = [make_theme_cluster(:vertical_bridge, d, net) for d in dimensions]
    return Themespace(dimensions, top, bottom, vertical,
                      vcat(top, bottom, vertical), BridgeTheme[], Symbol[])
end

"""`(get-possible-theme-types)` - without justify mode the answer string does
not exist, so the bottom bridge has nothing to map."""
get_possible_theme_types() =
    JUSTIFY_MODE[] ? Symbol[:top_bridge, :bottom_bridge, :vertical_bridge] :
                     Symbol[:top_bridge, :vertical_bridge]

"""`(intersect l1 l2)` - keeps l1's order, and l1's duplicates."""
sintersect(l1, l2) = [x for x in l1 if any(y -> y === x, l2)]

get_clusters(ts::Themespace, theme_type::Symbol) =
    theme_type === :top_bridge    ? ts.top_clusters :
    theme_type === :bottom_bridge ? ts.bottom_clusters :
                                    ts.vertical_clusters

function get_cluster(ts::Themespace, theme_type::Symbol, dimension::Node)
    cs = get_clusters(ts, theme_type)
    i = findfirst(c -> c.dimension === dimension, cs)
    return i === nothing ? nothing : cs[i]
end

get_relations(ts::Themespace, theme_type::Symbol, dimension::Node) =
    (get_cluster(ts, theme_type, dimension)::ThemeCluster).relations

get_theme(ts::Themespace, theme_type::Symbol, dimension::Node,
          relation::Union{Nothing,Node}) =
    get_theme(get_cluster(ts, theme_type, dimension)::ThemeCluster, relation)

get_themes(ts::Themespace, type_s) =
    BridgeTheme[t for t in ts.all_themes if theme_type_matches(t, type_s)]

get_all_active_themes(ts::Themespace) = get_themes(ts, ts.active_theme_types)

"""`(equal? other-theme)` — themes are equal when they make the same claim,
whether or not they are the same object."""
themes_equal(t1::BridgeTheme, t2::BridgeTheme) =
    t1.theme_type === t2.theme_type && t1.dimension === t2.dimension &&
    t1.relation === t2.relation

"""`(get-equivalent-theme theme)` — the themespace's own theme making the same
claim as the one handed in. The trace and the memory hold onto themes from
states that no longer exist, and look them up this way."""
function get_equivalent_theme(ts::Themespace, theme::BridgeTheme)
    i = findfirst(t -> themes_equal(t, theme), ts.all_themes)
    return i === nothing ? nothing : ts.all_themes[i]
end

theme_present(ts::Themespace, theme::BridgeTheme) =
    get_equivalent_theme(ts, theme) !== nothing

"""`(get-active-themes theme-type/s)` - themes of those types, but only the
types that are currently exerting pressure."""
function get_active_themes(ts::Themespace, type_s::Symbol)
    any(x -> x === type_s, ts.active_theme_types) || return BridgeTheme[]
    return get_themes(ts, type_s)
end
get_active_themes(ts::Themespace, type_s) =
    get_themes(ts, sintersect(type_s, ts.active_theme_types))

get_active_bridge_theme_types(ts::Themespace) =
    sintersect(ALL_THEME_TYPES, ts.active_theme_types)

function get_max_positive_theme_activation(ts::Themespace, type_s)
    themes = get_themes(ts, type_s)
    return isempty(themes) ? 0 : maximum(positive_activation, themes)
end

# --- thematic pressure ------------------------------------------------------

"""`(thematic-pressure?)` with no arguments asks whether ANY type is active;
with arguments, whether ALL of the named ones are."""
has_thematic_pressure(ts::Themespace) = !isempty(ts.active_theme_types)
has_thematic_pressure(ts::Themespace, types...) =
    all(t -> any(x -> x === t, ts.active_theme_types), types)

function set_thematic_pressure!(ts::Themespace, type::Symbol, switch::Bool)
    if switch != has_thematic_pressure(ts, type)
        if switch
            pushfirst!(ts.active_theme_types, type)
        else
            filter!(x -> x !== type, ts.active_theme_types)
        end
    end
    return ts
end

function thematic_pressure_on!(ts::Themespace, types::Symbol...)
    if isempty(types)
        ts.active_theme_types = get_possible_theme_types()
    else
        for t in types
            set_thematic_pressure!(ts, t, true)
        end
    end
    return ts
end

function thematic_pressure_off!(ts::Themespace, types::Symbol...)
    if isempty(types)
        empty!(ts.active_theme_types)
    else
        for t in types
            set_thematic_pressure!(ts, t, false)
        end
    end
    return ts
end

"""`(supported-by-active-theme? concept-mapping bridge)` - used by the trace to
decide which concept mappings a bridge owes to thematic pressure."""
function supported_by_active_theme(ts::Themespace, cm::ConceptMapping, b)
    theme = get_theme(ts, bridge_type_to_theme_type(b.bridge_type), cm_type(cm), cm.label)
    theme === nothing && return false
    return has_thematic_pressure(ts, (theme::BridgeTheme).theme_type) &&
           is_dominant(theme::BridgeTheme)
end

# --- adding, freezing and deleting ------------------------------------------

"""`(add-theme theme-type dimension relation check-if-frozen?)`. A frozen
cluster refuses new themes; `add-theme-unconditionally` bypasses that so the
GUI and the trace can set activations directly."""
function add_theme!(ts::Themespace, theme_type::Symbol, dimension::Node,
                    relation::Union{Nothing,Node}, check_if_frozen::Bool)
    SELF_WATCHING_ENABLED[] || return nothing
    theme = get_theme(ts, theme_type, dimension, relation)
    theme !== nothing && return theme
    cluster = get_cluster(ts, theme_type, dimension)::ThemeCluster
    check_if_frozen && cluster.frozen && return nothing
    new_theme = add_theme!(cluster, relation)
    new_theme !== nothing && pushfirst!(ts.all_themes, new_theme::BridgeTheme)
    return new_theme
end

add_theme_if_possible!(ts::Themespace, theme_type::Symbol, dimension::Node,
                       relation::Union{Nothing,Node}) =
    add_theme!(ts, theme_type, dimension, relation, true)
add_theme_unconditionally!(ts::Themespace, theme_type::Symbol, dimension::Node,
                           relation::Union{Nothing,Node}) =
    add_theme!(ts, theme_type, dimension, relation, false)

"""`(set-theme-activation ...)` - adds the theme if it is missing, then sets its
activation, leaving frozen/unfrozen status alone."""
function set_theme_activation!(ts::Themespace, theme_type::Symbol, dimension::Node,
                               relation::Union{Nothing,Node}, activation::Int)
    theme = add_theme_unconditionally!(ts, theme_type, dimension, relation)
    if theme !== nothing
        (theme::BridgeTheme).activation = activation
        update_dominant_theme!((theme::BridgeTheme).cluster::ThemeCluster)
    end
    return ts
end

function set_theme_cluster_activations!(ts::Themespace, theme_type::Symbol,
                                        dimension::Node, activation::Int)
    for relation in get_relations(ts, theme_type, dimension)
        set_theme_activation!(ts, theme_type, dimension, relation, activation)
    end
    return ts
end

function set_theme_type_activations!(ts::Themespace, theme_type::Symbol, activation::Int)
    for cluster in get_clusters(ts, theme_type)
        set_theme_cluster_activations!(ts, theme_type, cluster.dimension, activation)
    end
    return ts
end

function set_all_theme_activations!(ts::Themespace, activation::Int)
    for theme_type in ALL_THEME_TYPES
        set_theme_type_activations!(ts, theme_type, activation)
    end
    return ts
end

theme_frozen(ts::Themespace, theme_type::Symbol, dimension::Node,
             relation::Union{Nothing,Node}) =
    (t = get_theme(ts, theme_type, dimension, relation);
     t !== nothing && is_frozen(t::BridgeTheme))
cluster_frozen(ts::Themespace, theme_type::Symbol, dimension::Node) =
    (get_cluster(ts, theme_type, dimension)::ThemeCluster).frozen
theme_type_frozen(ts::Themespace, theme_type::Symbol) =
    all(c -> c.frozen, get_clusters(ts, theme_type))
everything_frozen(ts::Themespace) =
    all(t -> theme_type_frozen(ts, t), get_possible_theme_types())

function freeze_theme!(ts::Themespace, theme_type::Symbol, dimension::Node,
                       relation::Union{Nothing,Node})
    theme = get_theme(ts, theme_type, dimension, relation)
    theme !== nothing && ((theme::BridgeTheme).frozen = true)
    return ts
end

freeze_theme_cluster!(ts::Themespace, theme_type::Symbol, dimension::Node) =
    (freeze!(get_cluster(ts, theme_type, dimension)::ThemeCluster); ts)
freeze_theme_type!(ts::Themespace, theme_type::Symbol) =
    (foreach(freeze!, get_clusters(ts, theme_type)); ts)
freeze_everything!(ts::Themespace) = (foreach(freeze!, ts.all_clusters); ts)

"""`(unfreeze-theme ...)` has no effect on a theme whose whole cluster is
frozen - the cluster's flag outranks the theme's own."""
function unfreeze_theme!(ts::Themespace, theme_type::Symbol, dimension::Node,
                         relation::Union{Nothing,Node})
    theme = get_theme(ts, theme_type, dimension, relation)
    theme !== nothing && ((theme::BridgeTheme).frozen = false)
    return ts
end

unfreeze_theme_cluster!(ts::Themespace, theme_type::Symbol, dimension::Node) =
    (unfreeze!(get_cluster(ts, theme_type, dimension)::ThemeCluster); ts)
unfreeze_theme_type!(ts::Themespace, theme_type::Symbol) =
    (foreach(unfreeze!, get_clusters(ts, theme_type)); ts)
unfreeze_everything!(ts::Themespace) = (foreach(unfreeze!, ts.all_clusters); ts)

function delete_theme!(ts::Themespace, theme_type::Symbol, dimension::Node,
                       relation::Union{Nothing,Node})
    theme = get_theme(ts, theme_type, dimension, relation)
    if theme !== nothing
        delete_theme!((theme::BridgeTheme).cluster::ThemeCluster, theme::BridgeTheme)
        filter!(t -> t !== theme, ts.all_themes)
    end
    return ts
end

function delete_theme_cluster!(ts::Themespace, theme_type::Symbol, dimension::Node)
    for relation in get_relations(ts, theme_type, dimension)
        delete_theme!(ts, theme_type, dimension, relation)
    end
    return ts
end

function delete_theme_type!(ts::Themespace, theme_type::Symbol)
    foreach(delete_themes!, get_clusters(ts, theme_type))
    filter!(t -> !theme_type_matches(t, theme_type), ts.all_themes)
    return ts
end

function delete_everything!(ts::Themespace)
    foreach(delete_themes!, ts.all_clusters)
    empty!(ts.all_themes)
    return ts
end

function initialize!(ts::Themespace)
    delete_everything!(ts)
    unfreeze_everything!(ts)
    thematic_pressure_off!(ts)
    return ts
end

"""One cycle of the whole themespace, called once per codelet-update step."""
function spread_activation!(ts::Themespace)
    for cluster in ts.all_clusters
        spread_activation!(cluster)
        update_dominant_theme!(cluster)
    end
    return ts
end

function update_dominant_themes!(ts::Themespace, theme_types::Symbol...)
    clusters = isempty(theme_types) ? ts.all_clusters :
               vcat((get_clusters(ts, t) for t in theme_types)...)
    foreach(update_dominant_theme!, clusters)
    return ts
end

# --- theme patterns ---------------------------------------------------------

"""`(get-complete-theme-pattern theme-type)` - every theme of the type, as
(dimension, relation, activation) triples, cluster by cluster."""
get_complete_theme_pattern(ts::Themespace, theme_type::Symbol) =
    [(t.dimension, t.relation, t.activation)
     for c in get_clusters(ts, theme_type) for t in c.themes]

"""`(get-dominant-theme-pattern theme-type)` - one entry per cluster that has a
dominant theme."""
function get_dominant_theme_pattern(ts::Themespace, theme_type::Symbol)
    result = Tuple{Node,Union{Nothing,Node}}[]
    for c in get_clusters(ts, theme_type)
        d = c.dominant_theme
        d !== nothing && push!(result, ((d::BridgeTheme).dimension, (d::BridgeTheme).relation))
    end
    return result
end

get_nonzero_theme_pattern(ts::Themespace, theme_type::Symbol) =
    [e for e in get_complete_theme_pattern(ts, theme_type) if e[3] != 0]

"""`(get-percentage-of-dominant-themes)` - how much of the mapping the themes
have made up their mind about. Outside justify mode the bottom-bridge clusters
are excluded, since there is no answer string to map."""
function get_percentage_of_dominant_themes(ts::Themespace)
    clusters = JUSTIFY_MODE[] ? ts.all_clusters :
               vcat(ts.top_clusters, ts.vertical_clusters)
    return sdiv(count(c -> c.dominant_theme !== nothing, clusters), length(clusters))
end

# --- theme <-> slipnet ------------------------------------------------------

"""`(spread-activation-to-slipnet)` - an active theme keeps its own dimension
and relation alive in the slipnet. Both are `stochastic-if*`, which ALWAYS
draws, so the two draws happen even when the theme is at zero."""
function spread_activation_to_slipnet!(t::BridgeTheme, rng::PyRandom)
    if random_real(rng, 1.0) < cube(pct(absolute_activation(t)))
        activate_from_workspace!(t.dimension)
    end
    if t.relation !== nothing
        if random_real(rng, 1.0) < cube(pct(t.activation))
            activate_from_workspace!(t.relation::Node)
        end
    end
    return t
end

theme_type_to_bridge_type(theme_type::Symbol) =
    theme_type === :top_bridge    ? :top :
    theme_type === :bottom_bridge ? :bottom : :vertical

bridge_type_to_theme_type(bridge_type::Symbol) =
    bridge_type === :top    ? :top_bridge :
    bridge_type === :bottom ? :bottom_bridge : :vertical_bridge

# --- theme support ----------------------------------------------------------
#
# Whether a pair of objects, viewed through their descriptions, argues for or
# against a theme. `conflicts-with-theme?` and `supported-by-theme?` assume d1
# and d2 share a description type; the three special cases below are mutually
# exclusive.

"""Direction descriptions on two string-spanning groups speak to string
position, not to direction, because a whole-string group has no position of its
own to compare."""
special_direction_case(d1::Description, d2::Description, theme::BridgeTheme, net::Slipnet) =
    d1.description_type === net[:plato_direction_category] &&
    string_spanning_group(d1.object) && string_spanning_group(d2.object) &&
    theme.dimension === net[:plato_string_position_category]

"""Two whole-string objects trivially agree on object category and string
position, so neither counts as evidence."""
function special_spanning_bridge_case(d1::Description, d2::Description,
                                      theme::BridgeTheme, net::Slipnet)
    if d1.description_type === net[:plato_object_category] &&
       string_spanning_group(d1.object) && string_spanning_group(d2.object) &&
       theme.dimension === net[:plato_object_category]
        return true
    end
    return d1.description_type === net[:plato_string_position_category] &&
           spans_whole_string(d1.object) && spans_whole_string(d2.object) &&
           theme.dimension === net[:plato_string_position_category]
end

"""middle->middle counts as supporting a StringPos:opposite theme: the middle
of a string IS its own opposite."""
special_middle_middle_case(d1::Description, d2::Description, theme::BridgeTheme,
                           net::Slipnet) =
    d1.descriptor === net[:plato_middle] && d2.descriptor === net[:plato_middle] &&
    theme.dimension === net[:plato_string_position_category] &&
    theme.relation === net[:plato_opposite]

"""A difference theme is consistent with any relation except identity."""
function relation_consistent_with_theme(d1::Description, d2::Description,
                                        theme::BridgeTheme, net::Slipnet)
    label = label_between(d1.descriptor, d2.descriptor, net[:plato_identity])
    return difference_theme(theme) ? label !== net[:plato_identity] :
                                     label === theme.relation
end

function conflicts_with_theme(d1::Description, d2::Description, theme::BridgeTheme,
                              net::Slipnet)
    (d1.description_type === theme.dimension ||
     special_direction_case(d1, d2, theme, net)) || return false
    special_spanning_bridge_case(d1, d2, theme, net) && return false
    special_middle_middle_case(d1, d2, theme, net) && return false
    return !relation_consistent_with_theme(d1, d2, theme, net)
end

function supported_by_theme(d1::Description, d2::Description, theme::BridgeTheme,
                            net::Slipnet)
    (d1.description_type === theme.dimension ||
     special_direction_case(d1, d2, theme, net)) || return false
    special_spanning_bridge_case(d1, d2, theme, net) && return false
    return special_middle_middle_case(d1, d2, theme, net) ||
           relation_consistent_with_theme(d1, d2, theme, net)
end

"""`(check-descriptions object1 object2 pred? theme)` - does any same-typed pair
of descriptions satisfy the predicate?"""
function check_descriptions(object1::WSObject, object2::WSObject, pred,
                            theme::BridgeTheme, net::Slipnet)
    for d1 in object1.descriptions, d2 in object2.descriptions
        d1.description_type === d2.description_type || continue
        pred(d1, d2, theme, net) && return true
    end
    return false
end

"""`(theme-support-tester themes)` - assumes positively activated themes: a pair
of objects passes when no theme conflicts and at least one is supported."""
function themes_support(object1::WSObject, object2::WSObject, themes, net::Slipnet)
    any(t -> check_descriptions(object1, object2, conflicts_with_theme, t, net), themes) &&
        return false
    return any(t -> check_descriptions(object1, object2, supported_by_theme, t, net), themes)
end

"""`(descriptions-affect-themespace? d1 d2)` - which description pairs get to
vote when a bridge boosts themes. Irrelevant descriptions, the two trivial
whole-string agreements, and middle->middle are all ignored."""
function descriptions_affect_themespace(d1::Description, d2::Description, net::Slipnet)
    d1.description_type === d2.description_type || return false
    return !ignore_descriptions(d1, d2, net)
end

function ignore_descriptions(d1::Description, d2::Description, net::Slipnet)
    (relevant(d1) && relevant(d2)) || return true
    d1.description_type === net[:plato_object_category] &&
        string_spanning_group(d1.object) && string_spanning_group(d2.object) && return true
    d1.description_type === net[:plato_string_position_category] &&
        spans_whole_string(d1.object) && spans_whole_string(d2.object) && return true
    return d1.descriptor === net[:plato_middle] && d2.descriptor === net[:plato_middle]
end

"""Sharpens a bridge's raw theme-compatibility rating: a squashing function
from -1..+1 onto -1..+1."""
const THEME_SIGMOID_BETA = 4
bridge_theme_compatibility_sigmoid(x) = 2 / (1 + exp(-2 * THEME_SIGMOID_BETA * x)) - 1

# --- what the rest of the model asks the themespace -------------------------

"""`(get-theme-types)` for a description - which bridges its object can take
part in, and therefore which themes can weigh on it."""
function get_description_theme_types(d::Description)
    st = d.string.string_type
    st === :initial  && return Symbol[:top_bridge, :vertical_bridge]
    st === :modified && return Symbol[:top_bridge]
    st === :target   && return JUSTIFY_MODE[] ?
                               Symbol[:vertical_bridge, :bottom_bridge] :
                               Symbol[:vertical_bridge]
    return Symbol[:bottom_bridge]
end

get_theme_support_values(d::Description, ts::Themespace) =
    [t.dimension === d.description_type ? pct(absolute_activation(t)) : 0
     for t in get_active_themes(ts, get_description_theme_types(d))]

"""A description is pulled toward whichever active theme most wants its
dimension; it is never pulled against one, so this is always >= 0."""
function get_thematic_compatibility(d::Description, ts::Themespace)
    values = get_theme_support_values(d, ts)
    return isempty(values) ? 0 : maximum(values)
end

incompatible_with_theme(b::Bridge, theme::BridgeTheme, ts::Themespace, net::Slipnet) =
    check_descriptions(b.object1, b.object2, conflicts_with_theme, theme, net) ||
    begin
        # A theme also conflicts when only one of the objects could carry a
        # description in its dimension at all - the mapping cannot be made
        # either way.
        possible1 = description_possible(theme.dimension, b.object1, net)
        possible2 = description_possible(theme.dimension, b.object2, net)
        (possible1 && !possible2) || (!possible1 && possible2) ||
            (theme.dimension === net[:plato_string_position_category] &&
             !possible1 && !possible2)
    end

supported_by_theme(b::Bridge, theme::BridgeTheme, net::Slipnet) =
    check_descriptions(b.object1, b.object2, supported_by_theme, theme, net)

get_theme_support_values(b::Bridge, ts::Themespace, net::Slipnet) =
    [incompatible_with_theme(b, t, ts, net) ? -pct(t.activation) :
     supported_by_theme(b, t, net)          ?  pct(t.activation) : 0
     for t in get_active_themes(ts, bridge_type_to_theme_type(b.bridge_type))]

"""Negative support counts for far more than positive: violating one theme
outweighs satisfying all the others."""
function get_average_theme_support(b::Bridge, ts::Themespace, net::Slipnet)
    values = get_theme_support_values(b, ts, net)
    neg_weight = 2 * length(values)
    weights = [(n < 0 ? neg_weight : 1) * abs(n) for n in values]
    return weighted_average(values, weights)
end

get_thematic_compatibility(b::Bridge, ts::Themespace, net::Slipnet) =
    bridge_theme_compatibility_sigmoid(get_average_theme_support(b, ts, net))

"""`(boost-themes)` - every description pair the bridge maps votes for the theme
it realises, in proportion to the bridge's strength. A whole-string bridge
counts double. This does NOT update dominant themes; the caller does."""
function boost_themes!(b::Bridge, ts::Themespace, net::Slipnet)
    strength = b.strength
    theme_type = bridge_type_to_theme_type(b.bridge_type)
    for d1 in b.object1.descriptions, d2 in b.object2.descriptions
        descriptions_affect_themespace(d1, d2, net) || continue
        theme = add_theme_if_possible!(ts, theme_type, d1.description_type,
                                       label_between(d1.descriptor, d2.descriptor,
                                                     net[:plato_identity]))
        theme === nothing && continue
        boost_activation!(theme::BridgeTheme,
                          b.spanning_bridge ? 2 * strength : strength)
    end
    return b
end

function boost_themespace_activations!(b::Bridge, ts::Themespace, net::Slipnet)
    boost_themes!(b, ts, net)
    update_dominant_themes!(ts, bridge_type_to_theme_type(b.bridge_type))
    return b
end

"""`(get-associated-thematic-relations)` - the (dimension, relation) pairs this
bridge asserts, which is what the trace records about it."""
function get_associated_thematic_relations(b::Bridge, net::Slipnet)
    result = Tuple{Node,Union{Nothing,Node}}[]
    for d1 in b.object1.descriptions, d2 in b.object2.descriptions
        descriptions_affect_themespace(d1, d2, net) || continue
        push!(result, (d1.description_type,
                       label_between(d1.descriptor, d2.descriptor, net[:plato_identity])))
    end
    return result
end

"""`(get-all-complete-theme-patterns)` / `(get-all-dominant-theme-patterns)` —
one PATTERN per possible theme type, each with its type as its head, which is
the form the trace stores and `assq`s on. `get_complete_theme_pattern` above
returns the entries alone."""
get_all_complete_theme_patterns(ts::Themespace) =
    Any[Any[tt, get_complete_theme_pattern(ts, tt)...] for tt in get_possible_theme_types()]

get_all_dominant_theme_patterns(ts::Themespace) =
    Any[Any[tt, get_dominant_theme_pattern(ts, tt)...] for tt in get_possible_theme_types()]
