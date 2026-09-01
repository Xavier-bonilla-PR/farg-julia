# Ported from Metacat's themes.ss.
#
# The themespace is Metacat's self-watching layer over the workspace. A THEME
# is a claim of the form "in the top bridge, letter categories are related by
# successorship" — a (theme-type, dimension, relation) triple carrying an
# activation in -100..+100. Positive themes assert that relation; negative ones
# assert its absence. Themes live in CLUSTERS, one per (theme-type, dimension)
# pair, and the themes inside a cluster compete: a cluster settles on at most
# one DOMINANT theme, so the model converges on a single reading of each
# dimension.
#
# Why this layer is on the critical path rather than optional: every workspace
# structure's strength is a weighted blend of its intrinsic strength and its
# thematic compatibility (see `update_strength!` in workspace.jl). That
# compatibility is 0 only while no themes exist, which is exactly the condition
# the earlier probes held. Once bridges start boosting themes, structure
# strengths diverge from the theme-free port, so nothing downstream can be
# compared end-to-end until this file is in place.
#
# Deferred, and marked where it arises: the `thematic-bridge-scout` codelet,
# which needs the bridge and description codelets (not yet ported), and the
# save/restore-state machinery, which only the GUI and the memory layer use.

const MAX_THEME_ACTIVATION = 100
const DOMINANT_THEME_MARGIN = 90
const THEME_SPREAD_AMOUNT = 20
const THEME_BOOST_AMOUNT = 7
const THEME_DECAY_AMOUNT = 25

# Intra-cluster theme weights (< 0 inhibitory, > 0 excitatory).
const NEGATIVE_TO_NEGATIVE_WEIGHT = 0
const NEGATIVE_TO_POSITIVE_WEIGHT = 25
const POSITIVE_TO_NEGATIVE_WEIGHT = -75
const POSITIVE_TO_POSITIVE_WEIGHT = -2
const SELF_TO_SELF_WEIGHT = 10

clip_positive(x) = max(0, min(x, MAX_THEME_ACTIVATION))
clip_negative(x) = max(-MAX_THEME_ACTIVATION, min(x, 0))

"""`%self-watching-enabled%` and `*display-mode?*`, which together gate whether
themes may be created at all."""
const SELF_WATCHING_ENABLED = Ref{Bool}(true)
const DISPLAY_MODE = Ref{Bool}(false)
"""`%justify-mode%` — off, the bottom bridge takes no thematic pressure."""
const JUSTIFY_MODE = Ref{Bool}(false)

# --- themes -----------------------------------------------------------------

# Theme and ThemeCluster refer to each other, so the cluster field is typed
# through an abstract supertype rather than left as Any; that keeps field
# access off the dynamic path.
abstract type AbstractThemeCluster end

mutable struct Theme
    theme_type::Symbol                   # :top_bridge | :bottom_bridge | :vertical_bridge
    dimension::Node
    relation::Union{Nothing,Node}        # nothing == the "difference" theme
    activation::Int
    # exact throughout: propagation and self-excitation multiply by `(% w)`,
    # an exact rational, and the decay term is an integer
    net_input_buffer::Union{Int,Rational{Int}}
    cluster::Union{Nothing,AbstractThemeCluster}  # set when added to a cluster
    outgoing_theme_links::Vector{Theme}
    frozen::Bool
end

make_theme(theme_type::Symbol, dimension::Node, relation::Union{Nothing,Node}) =
    Theme(theme_type, dimension, relation, 0, 0, nothing, Theme[], false)

get_activation(t::Theme) = t.activation
get_absolute_activation(t::Theme) = abs(t.activation)
get_positive_activation(t::Theme) = max(0, t.activation)
is_negative_theme(t::Theme) = t.activation < 0

theme_type_matches(t::Theme, type::Symbol) = t.theme_type === type
theme_type_matches(t::Theme, types) = any(x -> x === t.theme_type, types)

is_difference_theme(t::Theme) = t.relation === nothing
theme_dimension_is(t::Theme, dim::Node) = t.dimension === dim
theme_relation_is(t::Theme, rel) = t.relation === rel

"""`(equal? other-theme)` — themes are identified by their triple."""
themes_equal(a::Theme, b::Theme) =
    a.theme_type === b.theme_type && a.dimension === b.dimension && a.relation === b.relation

"""`(ascii-name)`. A relation-less theme is the "different" theme."""
theme_ascii_name(t::Theme) =
    string(t.dimension.short_name, ":",
           t.relation === nothing ? "different" : t.relation.lowercase_name)

set_theme_activation!(t::Theme, n::Integer) = (t.activation = n; nothing)

"""`(frozen?)` — a theme is frozen if it or its whole cluster is."""
is_theme_frozen(t::Theme) = t.frozen || t.cluster.frozen
individually_frozen(t::Theme) = t.frozen
freeze_theme!(t::Theme) = (t.frozen = true; nothing)
unfreeze_theme!(t::Theme) = (t.frozen = false; nothing)

is_dominant(t::Theme) = t.cluster.dominant_theme === t

function add_outgoing_link!(t::Theme, other::Theme)
    pushfirst!(t.outgoing_theme_links, other)
    return nothing
end

function delete_outgoing_link!(t::Theme, other::Theme)
    idx = findfirst(x -> x === other, t.outgoing_theme_links)
    idx !== nothing && deleteat!(t.outgoing_theme_links, idx)
    return nothing
end

# --- clusters ---------------------------------------------------------------

mutable struct ThemeCluster <: AbstractThemeCluster
    theme_type::Symbol
    dimension::Node
    relations::Vector{Union{Nothing,Node}}
    themes::Vector{Theme}
    dominant_theme::Union{Nothing,Theme}
    sensitivity::Float64
    frozen::Bool
end

"""`(remq-duplicates l)` — NB Metacat's `remove-duplicates-pred` keeps the LAST
of each duplicate group, not the first."""
function remq_duplicates(l::Vector{T}) where {T}
    out = T[]
    for (i, x) in enumerate(l)
        any(y -> y === x, @view l[(i + 1):end]) && continue
        push!(out, x)
    end
    return out
end

"""`(get-possible-relations theme-type dimension)` — every label that can hold
between two instances of the dimension, `nothing` (difference) included. The
theme-type argument is accepted and ignored, as in the Scheme."""
function get_possible_relations(dimension::Node, net::Slipnet)
    nodes = instance_nodes(dimension)
    labels = Union{Nothing,Node}[]
    for n1 in nodes, n2 in nodes
        push!(labels, label_between(n1, n2, net[:plato_identity]))
    end
    return remq_duplicates(labels)
end

function make_theme_cluster(theme_type::Symbol, dimension::Node, net::Slipnet)
    return ThemeCluster(theme_type, dimension, get_possible_relations(dimension, net),
                        Theme[], nothing, 1.0, false)
end

"""The activation flowing across a link from a theme with activation a1 to one
with activation a2. Positive is excitatory, negative inhibitory."""
function propagation_function(a1, a2)
    w = if a1 < 0 && a2 < 0
        NEGATIVE_TO_NEGATIVE_WEIGHT
    elseif a1 < 0
        NEGATIVE_TO_POSITIVE_WEIGHT
    elseif a2 < 0
        POSITIVE_TO_NEGATIVE_WEIGHT
    else
        POSITIVE_TO_POSITIVE_WEIGHT
    end
    return abs(a1) * pct(w)
end

self_excitation_function(a) = a > 0 ? a * pct(SELF_TO_SELF_WEIGHT) : 0

"""Squashes the raw net input a theme received into a bounded activation step.
NB `sensitivity` is the inexact 1.0, so alpha and everything downstream of the
tanh is a Float64 — but Metacat's `round` is `inexact->exact`, so the step
itself lands back on an exact integer."""
function net_effect(c::ThemeCluster, net_input)
    alpha = c.sensitivity * (1 // 50) * sdiv(1, length(c.relations))
    return sround(smul(THEME_SPREAD_AMOUNT, stanh(smul(alpha, net_input))))
end

"""Exciting a negative theme pushes it toward -100, inhibiting it pulls it
toward 0; for a positive theme the directions are the other way round."""
function activation_function(c::ThemeCluster, net_input, activation)
    return activation < 0 ? clip_negative(activation - net_effect(c, net_input)) :
                            clip_positive(activation + net_effect(c, net_input))
end

get_cluster_theme(c::ThemeCluster, relation) =
    (i = findfirst(t -> t.relation === relation, c.themes); i === nothing ? nothing : c.themes[i])

has_dominant_theme(c::ThemeCluster) = c.dominant_theme !== nothing

get_max_positive_theme_activation(c::ThemeCluster) =
    smaximum([get_positive_activation(t) for t in c.themes])

pick_positive_theme(rng::PyRandom, c::ThemeCluster) =
    stochastic_pick(rng, c.themes, [get_positive_activation(t) for t in c.themes])

"""`(freeze)` — freezing a cluster freezes every theme in it, and blocks new
themes from being added."""
freeze_cluster!(c::ThemeCluster) = (c.frozen = true; nothing)

function unfreeze_cluster!(c::ThemeCluster)
    c.frozen = false
    for t in c.themes
        unfreeze_theme!(t)
    end
    return nothing
end

"""A cluster has a dominant theme when its most active theme is positive and
clears the runner-up by more than `%dominant-theme-margin%`."""
function update_dominant_theme!(c::ThemeCluster)
    if isempty(c.themes)
        c.dominant_theme = nothing
        return nothing
    end
    ranked = sort(c.themes, by = get_absolute_activation, rev = true, alg = MergeSort)
    runner_up = length(ranked) == 1 ? 0 : get_absolute_activation(ranked[2])
    c.dominant_theme =
        (get_activation(ranked[1]) > 0 &&
         get_absolute_activation(ranked[1]) - runner_up > DOMINANT_THEME_MARGIN) ?
        ranked[1] : nothing
    return nothing
end

"""One settling step for the whole cluster: buffers cleared, then filled, then
applied — so every theme steps off the same previous state."""
function spread_cluster_activation!(c::ThemeCluster)
    for t in c.themes
        t.net_input_buffer = 0
    end
    for t in c.themes
        for other in t.outgoing_theme_links
            other.net_input_buffer +=
                propagation_function(t.activation, other.activation)
        end
        t.net_input_buffer += self_excitation_function(t.activation)
        t.net_input_buffer -= THEME_DECAY_AMOUNT
    end
    for t in c.themes
        if !is_theme_frozen(t)
            t.activation = activation_function(c, t.net_input_buffer, t.activation)
        end
        t.net_input_buffer = 0
    end
    return nothing
end

"""`(boost-activation factor)`."""
function boost_theme_activation!(t::Theme, factor)
    is_theme_frozen(t) && return nothing
    t.activation = clip_positive(sround(t.activation + pct(factor) * THEME_BOOST_AMOUNT))
    return nothing
end

"""`(add-theme relation)` — a new theme is linked bidirectionally to every
theme already in the cluster. NB the Scheme CONSes, so the newest theme is
first in both the cluster list and each link list."""
function add_cluster_theme!(c::ThemeCluster, relation)
    any(r -> r === relation, c.relations) || return nothing
    theme = make_theme(c.theme_type, c.dimension, relation)
    for other in c.themes
        add_outgoing_link!(other, theme)
        add_outgoing_link!(theme, other)
    end
    theme.cluster = c
    pushfirst!(c.themes, theme)
    return theme
end

function delete_cluster_theme!(c::ThemeCluster, theme::Theme)
    idx = findfirst(t -> t === theme, c.themes)
    idx !== nothing && deleteat!(c.themes, idx)
    for other in c.themes
        delete_outgoing_link!(other, theme)
    end
    update_dominant_theme!(c)
    return nothing
end

function delete_cluster_themes!(c::ThemeCluster)
    c.themes = Theme[]
    c.dominant_theme = nothing
    return nothing
end

# --- the themespace ---------------------------------------------------------

mutable struct Themespace
    dimensions::Vector{Node}
    top_clusters::Vector{ThemeCluster}
    bottom_clusters::Vector{ThemeCluster}
    vertical_clusters::Vector{ThemeCluster}
    all_clusters::Vector{ThemeCluster}
    all_themes::Vector{Theme}
    active_theme_types::Vector{Symbol}
end

function make_themespace(net::Slipnet)
    dimensions = Node[n for n in net.nodes if is_category(n)]
    top = [make_theme_cluster(:top_bridge, d, net) for d in dimensions]
    bottom = [make_theme_cluster(:bottom_bridge, d, net) for d in dimensions]
    vertical = [make_theme_cluster(:vertical_bridge, d, net) for d in dimensions]
    return Themespace(dimensions, top, bottom, vertical,
                      vcat(top, bottom, vertical), Theme[], Symbol[])
end

"""Without justify mode the bottom bridge carries no thematic pressure."""
get_possible_theme_types() =
    JUSTIFY_MODE[] ? [:top_bridge, :bottom_bridge, :vertical_bridge] :
                     [:top_bridge, :vertical_bridge]

const ALL_BRIDGE_THEME_TYPES = (:top_bridge, :bottom_bridge, :vertical_bridge)

get_clusters(ts::Themespace, theme_type::Symbol) =
    theme_type === :top_bridge ? ts.top_clusters :
    theme_type === :bottom_bridge ? ts.bottom_clusters : ts.vertical_clusters

function get_cluster(ts::Themespace, theme_type::Symbol, dimension::Node)
    cs = get_clusters(ts, theme_type)
    i = findfirst(c -> c.dimension === dimension, cs)
    return i === nothing ? nothing : cs[i]
end

get_theme(ts::Themespace, theme_type::Symbol, dimension::Node, relation) =
    (c = get_cluster(ts, theme_type, dimension);
     c === nothing ? nothing : get_cluster_theme(c, relation))

get_relations(ts::Themespace, theme_type::Symbol, dimension::Node) =
    get_cluster(ts, theme_type, dimension).relations

thematic_pressure(ts::Themespace) = !isempty(ts.active_theme_types)
thematic_pressure(ts::Themespace, type::Symbol) =
    any(x -> x === type, ts.active_theme_types)
thematic_pressure(ts::Themespace, types) =
    all(t -> thematic_pressure(ts, t), types)

function set_thematic_pressure!(ts::Themespace, type::Symbol, on::Bool)
    on === thematic_pressure(ts, type) && return nothing
    if on
        pushfirst!(ts.active_theme_types, type)
    else
        idx = findfirst(x -> x === type, ts.active_theme_types)
        idx !== nothing && deleteat!(ts.active_theme_types, idx)
    end
    return nothing
end

"""`(thematic-pressure-on)` with no arguments turns on every possible type."""
function thematic_pressure_on!(ts::Themespace, types = Symbol[])
    if isempty(types)
        ts.active_theme_types = get_possible_theme_types()
    else
        for t in types
            set_thematic_pressure!(ts, t, true)
        end
    end
    return nothing
end

function thematic_pressure_off!(ts::Themespace, types = Symbol[])
    if isempty(types)
        ts.active_theme_types = Symbol[]
    else
        for t in types
            set_thematic_pressure!(ts, t, false)
        end
    end
    return nothing
end

get_all_themes(ts::Themespace) = ts.all_themes
get_themes(ts::Themespace, theme_type_or_types) =
    Theme[t for t in ts.all_themes if theme_type_matches(t, theme_type_or_types)]

get_all_active_themes(ts::Themespace) = get_themes(ts, ts.active_theme_types)

"""`(get-active-themes theme-type/s)`. A list argument is intersected with the
active types (order follows the argument); a bare symbol is all-or-nothing."""
function get_active_themes(ts::Themespace, theme_type_or_types)
    if theme_type_or_types isa Symbol
        return thematic_pressure(ts, theme_type_or_types) ?
               get_themes(ts, theme_type_or_types) : Theme[]
    end
    keep = Symbol[t for t in theme_type_or_types if thematic_pressure(ts, t)]
    return get_themes(ts, keep)
end

get_active_bridge_theme_types(ts::Themespace) =
    Symbol[t for t in ALL_BRIDGE_THEME_TYPES if thematic_pressure(ts, t)]

get_max_positive_theme_activation(ts::Themespace, theme_type_or_types) =
    smaximum([get_positive_activation(t) for t in get_themes(ts, theme_type_or_types)])

theme_present(ts::Themespace, theme::Theme) =
    any(t -> themes_equal(t, theme), ts.all_themes)

"""`(supported-by-active-theme? cm bridge)`."""
function supported_by_active_theme(ts::Themespace, theme_type::Symbol,
                                   cm_type::Node, label)
    theme = get_theme(ts, theme_type, cm_type, label)
    return theme !== nothing && thematic_pressure(ts, theme_type) && is_dominant(theme)
end

"""`(add-theme theme-type dimension relation check-if-frozen?)` — returns the
existing theme if there is one, otherwise creates it unless the cluster is
frozen and we were asked to check."""
function add_theme!(ts::Themespace, theme_type::Symbol, dimension::Node, relation,
                    check_if_frozen::Bool)
    (!SELF_WATCHING_ENABLED[] && !DISPLAY_MODE[]) && return nothing
    existing = get_theme(ts, theme_type, dimension, relation)
    existing !== nothing && return existing
    cluster = get_cluster(ts, theme_type, dimension)
    cluster === nothing && return nothing
    (check_if_frozen && cluster.frozen) && return nothing
    new_theme = add_cluster_theme!(cluster, relation)
    new_theme !== nothing && pushfirst!(ts.all_themes, new_theme)
    return new_theme
end

add_theme_if_possible!(ts::Themespace, tt::Symbol, dim::Node, rel) =
    add_theme!(ts, tt, dim, rel, true)
add_theme_unconditionally!(ts::Themespace, tt::Symbol, dim::Node, rel) =
    add_theme!(ts, tt, dim, rel, false)

"""`(set-theme-activation ...)` — adds the theme if missing, then sets it,
without touching frozen status."""
function set_theme_activation!(ts::Themespace, theme_type::Symbol, dimension::Node,
                               relation, activation::Integer)
    theme = add_theme_unconditionally!(ts, theme_type, dimension, relation)
    if theme !== nothing
        set_theme_activation!(theme, activation)
        update_dominant_theme!(theme.cluster)
    end
    return nothing
end

function set_theme_cluster_activations!(ts::Themespace, theme_type::Symbol,
                                        dimension::Node, activation::Integer)
    c = get_cluster(ts, theme_type, dimension)
    for relation in c.relations
        set_theme_activation!(ts, theme_type, dimension, relation, activation)
    end
    return nothing
end

function set_theme_type_activations!(ts::Themespace, theme_type::Symbol,
                                     activation::Integer)
    for c in get_clusters(ts, theme_type)
        set_theme_cluster_activations!(ts, theme_type, c.dimension, activation)
    end
    return nothing
end

function set_all_theme_activations!(ts::Themespace, activation::Integer)
    for tt in ALL_BRIDGE_THEME_TYPES
        set_theme_type_activations!(ts, tt, activation)
    end
    return nothing
end

# --- freezing ---------------------------------------------------------------

is_theme_frozen(ts::Themespace, tt::Symbol, dim::Node, rel) =
    (t = get_theme(ts, tt, dim, rel); t !== nothing && is_theme_frozen(t))
is_cluster_frozen(ts::Themespace, tt::Symbol, dim::Node) = get_cluster(ts, tt, dim).frozen
is_theme_type_frozen(ts::Themespace, tt::Symbol) = all(c -> c.frozen, get_clusters(ts, tt))
everything_frozen(ts::Themespace) =
    all(tt -> is_theme_type_frozen(ts, tt), get_possible_theme_types())

freeze_theme!(ts::Themespace, tt::Symbol, dim::Node, rel) =
    (t = get_theme(ts, tt, dim, rel); t !== nothing && freeze_theme!(t); nothing)
freeze_theme_cluster!(ts::Themespace, tt::Symbol, dim::Node) =
    freeze_cluster!(get_cluster(ts, tt, dim))
freeze_theme_type!(ts::Themespace, tt::Symbol) =
    (foreach(freeze_cluster!, get_clusters(ts, tt)); nothing)
freeze_everything!(ts::Themespace) = (foreach(freeze_cluster!, ts.all_clusters); nothing)

"""`(unfreeze-theme ...)` has no effect on a theme inside a frozen cluster."""
unfreeze_theme!(ts::Themespace, tt::Symbol, dim::Node, rel) =
    (t = get_theme(ts, tt, dim, rel); t !== nothing && unfreeze_theme!(t); nothing)
unfreeze_theme_cluster!(ts::Themespace, tt::Symbol, dim::Node) =
    unfreeze_cluster!(get_cluster(ts, tt, dim))
unfreeze_theme_type!(ts::Themespace, tt::Symbol) =
    (foreach(unfreeze_cluster!, get_clusters(ts, tt)); nothing)
unfreeze_everything!(ts::Themespace) = (foreach(unfreeze_cluster!, ts.all_clusters); nothing)

# --- deletion ---------------------------------------------------------------

function delete_theme!(ts::Themespace, tt::Symbol, dim::Node, rel)
    theme = get_theme(ts, tt, dim, rel)
    theme === nothing && return nothing
    delete_cluster_theme!(theme.cluster, theme)
    idx = findfirst(t -> t === theme, ts.all_themes)
    idx !== nothing && deleteat!(ts.all_themes, idx)
    return nothing
end

function delete_theme_cluster!(ts::Themespace, tt::Symbol, dim::Node)
    for rel in get_cluster(ts, tt, dim).relations
        delete_theme!(ts, tt, dim, rel)
    end
    return nothing
end

function delete_theme_type!(ts::Themespace, tt::Symbol)
    foreach(delete_cluster_themes!, get_clusters(ts, tt))
    ts.all_themes = Theme[t for t in ts.all_themes if !theme_type_matches(t, tt)]
    return nothing
end

function delete_everything!(ts::Themespace)
    foreach(delete_cluster_themes!, ts.all_clusters)
    ts.all_themes = Theme[]
    return nothing
end

function initialize_themespace!(ts::Themespace)
    delete_everything!(ts)
    unfreeze_everything!(ts)
    thematic_pressure_off!(ts)
    return nothing
end

# --- settling ---------------------------------------------------------------

function spread_theme_activation!(ts::Themespace)
    for c in ts.all_clusters
        spread_cluster_activation!(c)
        update_dominant_theme!(c)
    end
    return nothing
end

function update_dominant_themes!(ts::Themespace, theme_types = Symbol[])
    if theme_types isa Symbol
        theme_types = [theme_types]
    end
    clusters = isempty(theme_types) ? ts.all_clusters :
               vcat((get_clusters(ts, tt) for tt in theme_types)...)
    foreach(update_dominant_theme!, clusters)
    return nothing
end

# --- theme patterns ---------------------------------------------------------

get_complete_theme_pattern(ts::Themespace, tt::Symbol) =
    [(t.dimension, t.relation, t.activation)
     for c in get_clusters(ts, tt) for t in c.themes]

get_dominant_theme_pattern(ts::Themespace, tt::Symbol) =
    [(c.dominant_theme.dimension, c.dominant_theme.relation)
     for c in get_clusters(ts, tt) if c.dominant_theme !== nothing]

"""`(get-nonzero-theme-pattern)` — the complete pattern minus zero-activation
entries."""
get_nonzero_theme_pattern(ts::Themespace, tt::Symbol) =
    [e for e in get_complete_theme_pattern(ts, tt) if e[3] != 0]

"""`(get-percentage-of-dominant-themes)` — an exact fraction, as in the Scheme."""
function get_percentage_of_dominant_themes(ts::Themespace)
    clusters = JUSTIFY_MODE[] ? ts.all_clusters :
               vcat(ts.top_clusters, ts.vertical_clusters)
    return sdiv(count(has_dominant_theme, clusters), length(clusters))
end

# --- theme types <-> bridge types -------------------------------------------

theme_type_to_bridge_type(tt::Symbol) =
    tt === :top_bridge ? :top : tt === :bottom_bridge ? :bottom : :vertical
bridge_type_to_theme_type(bt::Symbol) =
    bt === :top ? :top_bridge : bt === :bottom ? :bottom_bridge : :vertical_bridge

# --- theme support ----------------------------------------------------------
#
# The four predicates below decide whether a pair of same-type descriptions
# agrees with a theme. The three "special cases" are mutually exclusive, and
# each exists to stop a structurally forced relation from counting as evidence.

"""Direction descriptions on two string-spanning groups answer to the
StringPos theme, because a spanning group's direction is what a position
relation between the strings amounts to."""
special_direction_case(d1::Description, d2::Description, theme::Theme, net::Slipnet) =
    d1.description_type === net[:plato_direction_category] &&
    both_spanning_groups(d1.object, d2.object) &&
    theme_dimension_is(theme, net[:plato_string_position_category])

"""Two spanning objects trivially agree on object category and string
position, so neither may count for or against a theme."""
special_spanning_bridge_case(d1::Description, d2::Description, theme::Theme, net::Slipnet) =
    (d1.description_type === net[:plato_object_category] &&
     both_spanning_groups(d1.object, d2.object) &&
     theme_dimension_is(theme, net[:plato_object_category])) ||
    (d1.description_type === net[:plato_string_position_category] &&
     both_spanning_objects(d1.object, d2.object) &&
     theme_dimension_is(theme, net[:plato_string_position_category]))

"""middle<->middle counts as supporting a StringPos:opposite theme: the middle
is its own opposite."""
special_middle_middle_case(d1::Description, d2::Description, theme::Theme, net::Slipnet) =
    d1.descriptor === net[:plato_middle] && d2.descriptor === net[:plato_middle] &&
    theme_dimension_is(theme, net[:plato_string_position_category]) &&
    theme_relation_is(theme, net[:plato_opposite])

function relation_consistent_with_theme(d1::Description, d2::Description,
                                        theme::Theme, net::Slipnet)
    label = label_between(d1.descriptor, d2.descriptor, net[:plato_identity])
    return is_difference_theme(theme) ? label !== net[:plato_identity] :
                                        label === theme.relation
end

function conflicts_with_theme(d1::Description, d2::Description, theme::Theme, net::Slipnet)
    (d1.description_type === theme.dimension ||
     special_direction_case(d1, d2, theme, net)) || return false
    special_spanning_bridge_case(d1, d2, theme, net) && return false
    special_middle_middle_case(d1, d2, theme, net) && return false
    return !relation_consistent_with_theme(d1, d2, theme, net)
end

function supported_by_theme(d1::Description, d2::Description, theme::Theme, net::Slipnet)
    (d1.description_type === theme.dimension ||
     special_direction_case(d1, d2, theme, net)) || return false
    special_spanning_bridge_case(d1, d2, theme, net) && return false
    return special_middle_middle_case(d1, d2, theme, net) ||
           relation_consistent_with_theme(d1, d2, theme, net)
end

"""`(check-descriptions object1 object2 pred? theme)` — does any same-type pair
of descriptions across the two objects satisfy the predicate?"""
function check_descriptions(object1::WSObject, object2::WSObject, pred, theme::Theme,
                            net::Slipnet)
    for d1 in object1.descriptions, d2 in object2.descriptions
        d1.description_type === d2.description_type || continue
        pred(d1, d2, theme, net) && return true
    end
    return false
end

both_spanning_groups(o1::WSObject, o2::WSObject) =
    string_spanning_group(o1) && string_spanning_group(o2)
both_spanning_objects(o1::WSObject, o2::WSObject) =
    spans_whole_string(o1) && spans_whole_string(o2)
lone_spanning_object(o1::WSObject, o2::WSObject) =
    spans_whole_string(o1) != spans_whole_string(o2)

"""`(theme-support-tester themes)` — assumes positively-activated themes: a
pair of objects supports a theme set if no theme conflicts and at least one is
positively supported."""
function themes_support(object1::WSObject, object2::WSObject, themes, net::Slipnet)
    any(t -> check_descriptions(object1, object2, conflicts_with_theme, t, net), themes) &&
        return false
    return any(t -> check_descriptions(object1, object2, supported_by_theme, t, net), themes)
end

"""`(descriptions-affect-themespace? d1 d2)` — whether a description pair is
allowed to boost themes at all."""
function descriptions_affect_themespace(d1::Description, d2::Description, net::Slipnet)
    d1.description_type === d2.description_type || return false
    return !ignore_descriptions(d1, d2, net)
end

function ignore_descriptions(d1::Description, d2::Description, net::Slipnet)
    (!relevant(d1) || !relevant(d2)) && return true
    (d1.description_type === net[:plato_object_category] &&
     both_spanning_groups(d1.object, d2.object)) && return true
    (d1.description_type === net[:plato_string_position_category] &&
     both_spanning_objects(d1.object, d2.object)) && return true
    return d1.descriptor === net[:plato_middle] && d2.descriptor === net[:plato_middle]
end

"""Sharpens a bridge's raw theme-support average. A squashing function from
-1..+1 onto -1..+1."""
const THEME_SIGMOID_BETA = 4
bridge_theme_compatibility_sigmoid(x) =
    sdiv(2, 1 + sexp_e(smul(-2 * THEME_SIGMOID_BETA, x))) - 1

# --- descriptor possibility --------------------------------------------------
#
# `(description-possible? object)` on a slipnode, which asks whether any
# instance of that node could describe the object. It lives here because the
# theme code is its first consumer; the description codelets will want it too.

"""`(possible-descriptor? object)` — the per-node predicate table from the
bottom of slipnet.ss. Nodes with no predicate can never describe an object."""
function possible_descriptor(node::Node, object::WSObject, net::Slipnet)
    for (i, sym) in enumerate((:plato_one, :plato_two, :plato_three, :plato_four,
                               :plato_five))
        node === net[sym] && return object isa Group && object.group_length == i
    end
    node === net[:plato_leftmost] &&
        return !string_spanning_group(object) && leftmost_in_string(object)
    node === net[:plato_rightmost] &&
        return !string_spanning_group(object) && rightmost_in_string(object)
    node === net[:plato_middle] && return middle_in_string(object)
    node === net[:plato_single] && return object isa Letter && spans_whole_string(object)
    node === net[:plato_whole] && return string_spanning_group(object)
    node === net[:plato_alphabetic_first] &&
        return get_descriptor_for(object, net[:plato_letter_category]) === net[:plato_a]
    node === net[:plato_alphabetic_last] &&
        return get_descriptor_for(object, net[:plato_letter_category]) === net[:plato_z]
    node === net[:plato_letter] && return object isa Letter
    node === net[:plato_group] && return object isa Group
    return false
end

get_possible_descriptors(node::Node, object::WSObject, net::Slipnet) =
    Node[n for n in instance_nodes(node) if possible_descriptor(n, object, net)]

description_possible(node::Node, object::WSObject, net::Slipnet) =
    any(n -> possible_descriptor(n, object, net), instance_nodes(node))

# --- thematic compatibility of workspace structures --------------------------
#
# These replace the theme-free stubs the earlier layers carried. A `nothing`
# themespace still means "no themes", so every pre-themes call site keeps its
# old behaviour exactly.

"""`(get-theme-support-values)` for a description: the absolute activation of
each active theme on this description's own dimension."""
get_theme_support_values(d::Description, ts::Themespace) =
    [t.dimension === d.description_type ? pct(get_absolute_activation(t)) : 0
     for t in get_active_themes(ts, description_theme_types(d))]

"""Which bridges a description can bear on, by the string it sits in."""
function description_theme_types(d::Description)
    which = d.string.string_type
    which === :initial && return [:top_bridge, :vertical_bridge]
    which === :modified && return [:top_bridge]
    which === :target &&
        return JUSTIFY_MODE[] ? [:vertical_bridge, :bottom_bridge] : [:vertical_bridge]
    return [:bottom_bridge]
end

get_thematic_compatibility(d::Description, ts::Themespace, ::Slipnet) =
    smaximum(get_theme_support_values(d, ts))

"""`(incompatible-with-theme? theme)` for a bridge. Beyond an outright
description conflict, a theme is incompatible when its dimension can describe
one object but not the other — the bridge cannot honour a relation that only
one side can express."""
function bridge_incompatible_with_theme(b::Bridge, theme::Theme, net::Slipnet)
    check_descriptions(b.object1, b.object2, conflicts_with_theme, theme, net) &&
        return true
    possible1 = description_possible(theme.dimension, b.object1, net)
    possible2 = description_possible(theme.dimension, b.object2, net)
    possible1 != possible2 && return true
    return theme.dimension === net[:plato_string_position_category] &&
           !possible1 && !possible2
end

bridge_supported_by_theme(b::Bridge, theme::Theme, net::Slipnet) =
    check_descriptions(b.object1, b.object2, supported_by_theme, theme, net)

function get_theme_support_values(b::Bridge, ts::Themespace, net::Slipnet)
    theme_type = bridge_type_to_theme_type(b.bridge_type)
    return [bridge_incompatible_with_theme(b, t, net) ? -pct(get_activation(t)) :
            bridge_supported_by_theme(b, t, net) ? pct(get_activation(t)) : 0
            for t in get_active_themes(ts, theme_type)]
end

"""`(get-average-theme-support)` — negative support counts for twice the number
of themes, so a single conflict outweighs a good deal of agreement."""
function get_average_theme_support(b::Bridge, ts::Themespace, net::Slipnet)
    values = get_theme_support_values(b, ts, net)
    neg_weight = 2 * length(values)
    weights = [(n < 0 ? neg_weight : 1) * abs(n) for n in values]
    return weighted_average(values, weights)
end

get_thematic_compatibility(b::Bridge, ts::Themespace, net::Slipnet) =
    bridge_theme_compatibility_sigmoid(get_average_theme_support(b, ts, net))

"""`(boost-themes)` — every description pair that agrees on a dimension pushes
the corresponding theme up, by the bridge's strength (doubled for a bridge
between two string-spanning objects)."""
function boost_themes!(b::Bridge, ts::Themespace, net::Slipnet)
    theme_type = bridge_type_to_theme_type(b.bridge_type)
    for d1 in b.object1.descriptions, d2 in b.object2.descriptions
        descriptions_affect_themespace(d1, d2, net) || continue
        theme = add_theme_if_possible!(ts, theme_type, d1.description_type,
                                       label_between(d1.descriptor, d2.descriptor,
                                                     net[:plato_identity]))
        theme === nothing && continue
        boost_theme_activation!(theme, b.spanning_bridge ? 2 * b.strength : b.strength)
    end
    return nothing
end

"""`(boost-themespace-activations)`."""
function boost_themespace_activations!(b::Bridge, ts::Themespace, net::Slipnet)
    boost_themes!(b, ts, net)
    update_dominant_themes!(ts, bridge_type_to_theme_type(b.bridge_type))
    return nothing
end

"""`(get-associated-thematic-relations)`."""
get_associated_thematic_relations(b::Bridge, net::Slipnet) =
    [(d1.description_type,
      label_between(d1.descriptor, d2.descriptor, net[:plato_identity]))
     for d1 in b.object1.descriptions for d2 in b.object2.descriptions
     if descriptions_affect_themespace(d1, d2, net)]
