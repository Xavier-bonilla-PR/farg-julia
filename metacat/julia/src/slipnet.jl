# Ported from Metacat's slipnet.ss.
#
# The slipnet is Metacat's network of platonic concepts: nodes carry an
# activation and a conceptual depth, and links between them carry a length
# whose reciprocal is the "degree of association". Activation decays toward
# zero, spreads from fully active nodes along their links, and occasionally
# jumps to full for a partially active node.
#
# Two details of the Scheme are load-bearing and easy to lose in translation:
#
#   * Links are CONSed onto a node's list, so each of a node's five link lists
#     ends up in REVERSE declaration order. `get-related-node` picks the first
#     match out of those lists, so the order is behaviour-visible, and the port
#     uses pushfirst! to reproduce it.
#   * Almost every quantity here is an exact rational, not a float. A node's
#     rate of decay is 1 - depth/100 exactly, and spreading multiplies by
#     association/100 exactly before rounding. See schemenum.jl.

const MAX_ACTIVATION = 100
const WORKSPACE_ACTIVATION = 100
const FULL_ACTIVATION_THRESHOLD = 50
const UPDATE_CYCLE_LENGTH = 15

# Slipnode and Sliplink are mutually recursive; parametrising the node on the
# link type keeps both concrete.
mutable struct Slipnode{L}
    name::Symbol
    short_name::String
    conceptual_depth::Int
    activation::Int
    activation_buffer::Int
    frozen::Bool
    changed_frozen::Bool
    rate_of_decay::Union{Int,Rational{Int}}
    intrinsic_link_length::Int
    shrunk_link_length::Int
    top_down_codelet_types::Vector{Symbol}
    incoming_links::Vector{L}
    category_links::Vector{L}
    instance_links::Vector{L}
    property_links::Vector{L}
    lateral_links::Vector{L}
    lateral_sliplinks::Vector{L}
    links_labeled_by_node::Vector{L}
    lowercase_name::String
    uppercase_name::String
end

mutable struct Sliplink
    from_node::Slipnode{Sliplink}
    to_node::Slipnode{Sliplink}
    link_type::Symbol
    label_node::Union{Nothing,Slipnode{Sliplink}}
    fixed_length::Bool
    link_length::Int
end

const Node = Slipnode{Sliplink}

"""`(string-suffix (symbol->string name) 6)` drops the `plato-` prefix."""
function make_slipnode(name::Symbol, short_name::AbstractString, conceptual_depth::Int)
    # Scheme spells these with hyphens; Julia symbols use underscores.
    full_lower = lowercase(replace(String(name)[7:end], "_" => "-"))
    return Node(name, String(short_name), conceptual_depth,
                0, 0, false, false, 0, 0, 0, Symbol[],
                Sliplink[], Sliplink[], Sliplink[], Sliplink[], Sliplink[],
                Sliplink[], Sliplink[],
                full_lower, uppercase(full_lower))
end

function reset!(n::Node)
    n.activation = 0
    n.activation_buffer = 0
    n.frozen = false
    n.changed_frozen = false
    # (1- (expt (% conceptual-depth) (/ %update-cycle-length% 15)))
    n.rate_of_decay = sub_from_1(sexpt(pct(n.conceptual_depth),
                                       sdiv(UPDATE_CYCLE_LENGTH, 15)))
    return n
end

fully_active(n::Node) = n.activation == MAX_ACTIVATION
above_threshold(n::Node) = n.activation >= FULL_ACTIVATION_THRESHOLD
partially_active(n::Node) = above_threshold(n) && !fully_active(n)

degree_of_assoc(n::Node) =
    sub_from_100(fully_active(n) ? n.shrunk_link_length : n.intrinsic_link_length)

is_category(n::Node) = !isempty(n.instance_links)
is_instance(n::Node) = !isempty(n.category_links)

get_category(n::Node) = isempty(n.category_links) ? nothing : n.category_links[1].to_node

"""`(get-outgoing-links)` — the five lists appended, in this order."""
outgoing_links(n::Node) = Iterators.flatten((n.category_links, n.instance_links,
                                             n.property_links, n.lateral_links,
                                             n.lateral_sliplinks))

instance_nodes(n::Node) = [l.to_node for l in n.instance_links]

function set_intrinsic_link_length!(n::Node, v::Int)
    n.intrinsic_link_length = v
    n.shrunk_link_length = sround(2 // 5 * v)   # (40% v)
    return n
end

freeze!(n::Node) = (n.frozen = true; n.changed_frozen = true; n)
unfreeze!(n::Node) = (n.frozen = false; n.changed_frozen = true; n)

function clamp_activation!(n::Node, v::Int)
    n.activation = v
    n.activation_buffer = 0
    n.frozen = true
    n.changed_frozen = true
    return n
end

function set_activation!(n::Node, v::Int)
    if !n.frozen
        n.activation = v
        n.activation_buffer = 0
    end
    return n
end

const update_activation! = set_activation!

function increment_activation_buffer!(n::Node, delta)
    n.frozen || (n.activation_buffer += delta)
    return n
end

function decrement_activation_buffer!(n::Node, delta)
    n.frozen || (n.activation_buffer -= delta)
    return n
end

function flush_activation_buffer!(n::Node)
    n.activation = min(MAX_ACTIVATION, n.activation + n.activation_buffer)
    n.activation_buffer = 0
    return n
end

activate_from_workspace!(n::Node) =
    increment_activation_buffer!(n, WORKSPACE_ACTIVATION)

decay_activation!(n::Node) =
    decrement_activation_buffer!(n, sround(n.rate_of_decay * n.activation))

function spread_activation!(n::Node)
    for link in outgoing_links(n)
        association = intrinsic_degree_of_assoc(link)
        spread_amount = sround(sdiv(UPDATE_CYCLE_LENGTH, 15) * pct(association) * n.activation)
        increment_activation_buffer!(link.to_node, spread_amount)
    end
    return n
end

"""`(get-related-node relation)`."""
function get_related_node(n::Node, relation::Union{Nothing,Node}, identity_node::Node)
    relation === identity_node && return n
    related = Node[l.to_node for l in outgoing_links(n) if l.label_node === relation]
    isempty(related) && return nothing
    length(related) == 1 && return related[1]
    mine = get_category(n)
    idx = findfirst(x -> get_category(x) === mine, related)
    return idx === nothing ? nothing : related[idx]
end

# --- links ------------------------------------------------------------------

intrinsic_degree_of_assoc(l::Sliplink) =
    l.fixed_length ? sub_from_100(l.link_length) :
                     sub_from_100((l.label_node::Node).intrinsic_link_length)

function link_degree_of_assoc(l::Sliplink)
    l.fixed_length && return sub_from_100(l.link_length)
    label = l.label_node::Node
    return sub_from_100(fully_active(label) ? label.shrunk_link_length :
                                              label.intrinsic_link_length)
end

link_print_name(l::Sliplink) = string(l.from_node.lowercase_name, "-->", l.to_node.lowercase_name)

"""`(establish-link ...)` — note the CONS: each list ends up reversed."""
function establish_link!(from::Node, to::Node, link_type::Symbol)
    link = Sliplink(from, to, link_type, nothing, false, 0)
    list = link_type === :category  ? from.category_links :
           link_type === :instance  ? from.instance_links :
           link_type === :property  ? from.property_links :
           link_type === :lateral   ? from.lateral_links :
                                      from.lateral_sliplinks
    pushfirst!(list, link)
    pushfirst!(to.incoming_links, link)
    return link
end

function set_link_length!(l::Sliplink, len::Int)
    l.link_length = len
    l.fixed_length = true
    return l
end

function set_label_node!(l::Sliplink, node::Node)
    l.label_node = node
    pushfirst!(node.links_labeled_by_node, l)
    return l
end

related(n1::Node, n2::Node) = n1 === n2 || linked(n1, n2)
linked(n1::Node, n2::Node) = any(l -> l.to_node === n2, outgoing_links(n1))
slip_linked(n1::Node, n2::Node) = any(l -> l.to_node === n2, n1.lateral_sliplinks)

"""`(get-label from to)` — the label on the link between two nodes, if any."""
function label_between(from::Node, to::Node, identity_node::Node)
    from === to && return identity_node
    idx = findfirst(l -> l.from_node === from, to.incoming_links)
    return idx === nothing ? nothing : to.incoming_links[idx].label_node
end

# --- the network itself -----------------------------------------------------

struct Slipnet
    nodes::Vector{Node}
    by_name::Dict{Symbol,Node}
    letters::Vector{Node}
    numbers::Vector{Node}
    top_down_nodes::Vector{Node}
    initially_clamped_nodes::Vector{Node}
end

Base.getindex(net::Slipnet, name::Symbol) = net.by_name[name]

const NODE_TABLE = [
    (:plato_a, "a", 10), (:plato_b, "b", 10), (:plato_c, "c", 10), (:plato_d, "d", 10),
    (:plato_e, "e", 10), (:plato_f, "f", 10), (:plato_g, "g", 10), (:plato_h, "h", 10),
    (:plato_i, "i", 10), (:plato_j, "j", 10), (:plato_k, "k", 10), (:plato_l, "l", 10),
    (:plato_m, "m", 10), (:plato_n, "n", 10), (:plato_o, "o", 10), (:plato_p, "p", 10),
    (:plato_q, "q", 10), (:plato_r, "r", 10), (:plato_s, "s", 10), (:plato_t, "t", 10),
    (:plato_u, "u", 10), (:plato_v, "v", 10), (:plato_w, "w", 10), (:plato_x, "x", 10),
    (:plato_y, "y", 10), (:plato_z, "z", 10),
    (:plato_one, "one", 30), (:plato_two, "two", 30), (:plato_three, "three", 30),
    (:plato_four, "four", 30), (:plato_five, "five", 30),
    (:plato_leftmost, "lmost", 40), (:plato_rightmost, "rmost", 40),
    (:plato_middle, "middle", 40), (:plato_single, "single", 40),
    (:plato_whole, "whole", 40),
    (:plato_alphabetic_first, "first", 60), (:plato_alphabetic_last, "last", 60),
    (:plato_left, "left", 40), (:plato_right, "right", 40),
    (:plato_predecessor, "pred", 50), (:plato_successor, "succ", 50),
    (:plato_sameness, "same", 80),
    (:plato_predgrp, "predgrp", 50), (:plato_succgrp, "succgrp", 50),
    (:plato_samegrp, "samegrp", 80),
    (:plato_identity, "Identity", 90), (:plato_opposite, "Opposite", 90),
    (:plato_letter, "letter", 20), (:plato_group, "group", 80),
    (:plato_letter_category, "LetterCtgy", 30),
    (:plato_string_position_category, "StringPos", 70),
    (:plato_alphabetic_position_category, "AlphaPos", 80),
    (:plato_direction_category, "Direction", 70),
    (:plato_bond_category, "BondCtgy", 80),
    (:plato_group_category, "GroupCtgy", 80),
    (:plato_length, "Length", 60),
    (:plato_object_category, "ObjectCtgy", 90),
    (:plato_bond_facet, "BondFacet", 90),
]

"""Build the slipnet. The order of node creation and, crucially, of link
declaration reproduces slipnet.ss exactly."""
function build_slipnet()
    nodes = Node[]
    by_name = Dict{Symbol,Node}()
    for (name, short, depth) in NODE_TABLE
        n = make_slipnode(name, short, depth)
        push!(nodes, n)
        by_name[name] = n
    end
    N(sym) = by_name[sym]
    # `plato-alphabetic-first` etc. are spelled with hyphens in the Scheme;
    # this resolves the short link-macro names the same way the macros did.
    L(short) = by_name[Symbol("plato_", replace(short, "-" => "_"))]

    letters = [N(Symbol("plato_", c)) for c in "abcdefghijklmnopqrstuvwxyz"]
    numbers = [N(s) for s in (:plato_one, :plato_two, :plato_three, :plato_four, :plato_five)]

    # top-down codelet types
    for n in (L("left"), L("right"))
        n.top_down_codelet_types = [Symbol("top-down-bond-scout:direction"),
                                    Symbol("top-down-group-scout:direction")]
    end
    for n in (L("predecessor"), L("successor"), L("sameness"))
        n.top_down_codelet_types = [Symbol("top-down-bond-scout:category")]
    end
    for n in (L("predgrp"), L("succgrp"), L("samegrp"))
        n.top_down_codelet_types = [Symbol("top-down-group-scout:category")]
    end
    for n in (L("string-position-category"), L("alphabetic-position-category"), L("length"))
        n.top_down_codelet_types = [Symbol("top-down-description-scout")]
    end

    # intrinsic link lengths for the nodes that label links
    set_intrinsic_link_length!(L("predecessor"), 60)
    set_intrinsic_link_length!(L("successor"), 60)
    set_intrinsic_link_length!(L("sameness"), 0)
    set_intrinsic_link_length!(L("identity"), 0)
    set_intrinsic_link_length!(L("opposite"), 80)

    cd(n) = n.conceptual_depth

    lateral!(a, b; length = nothing, label = nothing) = begin
        l = establish_link!(a, b, :lateral)
        length === nothing || set_link_length!(l, length)
        label === nothing || set_label_node!(l, label)
        l
    end
    lateral2!(a, b; length = nothing, label = nothing) = begin
        lateral!(a, b; length = length, label = label)
        lateral!(b, a; length = length, label = label)
    end
    sliplink!(a, b; length = nothing, label = nothing) = begin
        l = establish_link!(a, b, :lateral_sliplink)
        length === nothing || set_link_length!(l, length)
        label === nothing || set_label_node!(l, label)
        l
    end
    sliplink2!(a, b; length = nothing, label = nothing) = begin
        sliplink!(a, b; length = length, label = label)
        sliplink!(b, a; length = length, label = label)
    end
    instance!(c, i, len) = set_link_length!(establish_link!(c, i, :instance), len)
    category!(i, c, len) = set_link_length!(establish_link!(i, c, :category), len)
    property!(a, b, len) = set_link_length!(establish_link!(a, b, :property), len)

    # SUCCESSOR and PREDECESSOR links
    for i in 1:25
        lateral!(letters[i], letters[i + 1]; label = L("successor"))
    end
    for i in 26:-1:2
        lateral!(letters[i], letters[i - 1]; label = L("predecessor"))
    end
    for i in 1:4
        lateral!(numbers[i], numbers[i + 1]; label = L("successor"))
    end
    for i in 5:-1:2
        lateral!(numbers[i], numbers[i - 1]; label = L("predecessor"))
    end

    # LETTER-CATEGORY links
    for l in letters; instance!(L("letter-category"), l, 97); end
    for l in letters; category!(l, L("letter-category"), 0); end
    let d = cd(L("letter-category"))
        for l in letters
            set_link_length!(l.category_links[1], d - cd(l))
        end
    end
    lateral!(L("samegrp"), L("letter-category"); length = 50)

    # LENGTH links
    for n in numbers; instance!(L("length"), n, 100); end
    for n in numbers; category!(n, L("length"), 0); end
    let d = cd(L("length"))
        for n in numbers
            set_link_length!(n.category_links[1], d - cd(n))
        end
    end
    lateral!(L("predgrp"), L("length"); length = 95)
    lateral!(L("succgrp"), L("length"); length = 95)
    lateral!(L("samegrp"), L("length"); length = 95)

    # OPPOSITE links
    sliplink2!(L("alphabetic-first"), L("alphabetic-last"); label = L("opposite"))
    sliplink2!(L("leftmost"), L("rightmost"); label = L("opposite"))
    sliplink2!(L("left"), L("right"); label = L("opposite"))
    sliplink2!(L("successor"), L("predecessor"); label = L("opposite"))
    sliplink2!(L("predgrp"), L("succgrp"); label = L("opposite"))

    # PROPERTY links
    property!(L("a"), L("alphabetic-first"), 75)
    property!(L("z"), L("alphabetic-last"), 75)

    # OBJECT-CATEGORY links
    instance!(L("object-category"), L("letter"), 100)
    category!(L("letter"), L("object-category"), cd(L("object-category")) - cd(L("letter")))
    instance!(L("object-category"), L("group"), 100)
    category!(L("group"), L("object-category"), cd(L("object-category")) - cd(L("group")))

    # STRING-POSITION-CATEGORY links
    for nm in ("leftmost", "rightmost", "middle", "single", "whole")
        instance!(L("string-position-category"), L(nm), 100)
        category!(L(nm), L("string-position-category"),
                  cd(L("string-position-category")) - cd(L(nm)))
    end

    # ALPHABETIC-POSITION-CATEGORY links
    for nm in ("alphabetic-first", "alphabetic-last")
        instance!(L("alphabetic-position-category"), L(nm), 100)
        category!(L(nm), L("alphabetic-position-category"),
                  cd(L("alphabetic-position-category")) - cd(L(nm)))
    end

    # DIRECTION-CATEGORY links
    for nm in ("left", "right")
        instance!(L("direction-category"), L(nm), 100)
        category!(L(nm), L("direction-category"), cd(L("direction-category")) - cd(L(nm)))
    end

    # BOND-CATEGORY links
    for nm in ("predecessor", "successor", "sameness")
        instance!(L("bond-category"), L(nm), 100)
        category!(L(nm), L("bond-category"), cd(L("bond-category")) - cd(L(nm)))
    end

    # GROUP-CATEGORY links
    for nm in ("predgrp", "succgrp", "samegrp")
        instance!(L("group-category"), L(nm), 100)
        category!(L(nm), L("group-category"), cd(L("group-category")) - cd(L(nm)))
    end

    # ASSOCIATED GROUP links
    lateral!(L("sameness"), L("samegrp"); length = 30, label = L("group-category"))
    lateral!(L("successor"), L("succgrp"); length = 60, label = L("group-category"))
    lateral!(L("predecessor"), L("predgrp"); length = 60, label = L("group-category"))

    # ASSOCIATED BOND-CATEGORY links
    lateral!(L("samegrp"), L("sameness"); length = 90, label = L("bond-category"))
    lateral!(L("succgrp"), L("successor"); length = 90, label = L("bond-category"))
    lateral!(L("predgrp"), L("predecessor"); length = 90, label = L("bond-category"))

    # BOND-FACET links
    instance!(L("bond-facet"), L("letter-category"), 100)
    category!(L("letter-category"), L("bond-facet"),
              cd(L("bond-facet")) - cd(L("letter-category")))
    instance!(L("bond-facet"), L("length"), 100)
    category!(L("length"), L("bond-facet"), cd(L("bond-facet")) - cd(L("length")))

    # LETTER-CATEGORY-LENGTH, LETTER-GROUP
    sliplink2!(L("letter-category"), L("length"); length = 95)
    sliplink2!(L("letter"), L("group"); length = 90)

    # DIRECTION-POSITION, DIRECTION-NEIGHBOR, POSITION-NEIGHBOR links
    lateral2!(L("leftmost"), L("left"); length = 90, label = L("identity"))
    lateral2!(L("leftmost"), L("right"); length = 100, label = L("opposite"))
    lateral2!(L("rightmost"), L("left"); length = 100, label = L("opposite"))
    lateral2!(L("rightmost"), L("right"); length = 90, label = L("identity"))
    lateral2!(L("alphabetic-first"), L("leftmost"); length = 100)
    lateral2!(L("alphabetic-first"), L("rightmost"); length = 100)
    lateral2!(L("alphabetic-last"), L("leftmost"); length = 100)
    lateral2!(L("alphabetic-last"), L("rightmost"); length = 100)

    # OTHER
    sliplink2!(L("single"), L("whole"); length = 90)

    net = Slipnet(nodes, by_name, letters, numbers,
                  [L("left"), L("right"), L("predecessor"), L("successor"),
                   L("sameness"), L("predgrp"), L("succgrp"), L("samegrp"),
                   L("string-position-category"), L("alphabetic-position-category"),
                   L("length")],
                  [L("letter-category"), L("string-position-category")])
    reset_slipnet!(net)
    return net
end

reset_slipnet!(net::Slipnet) = (foreach(reset!, net.nodes); net)

"""`(possible-descriptor? object)` — whether this node could describe the
object. Only the nodes with a `define-descriptor-predicate` in slipnet.ss can;
every other node answers no, which is the default predicate there."""
function possible_descriptor(n::Node, o, net::Slipnet)
    name = n.name
    if name === :plato_one || name === :plato_two || name === :plato_three ||
       name === :plato_four || name === :plato_five
        len = name === :plato_one ? 1 : name === :plato_two ? 2 :
              name === :plato_three ? 3 : name === :plato_four ? 4 : 5
        return is_group(o) && group_length(o) == len
    elseif name === :plato_leftmost
        return !string_spanning_group(o) && leftmost_in_string(o)
    elseif name === :plato_rightmost
        return !string_spanning_group(o) && rightmost_in_string(o)
    elseif name === :plato_middle
        return middle_in_string(o)
    elseif name === :plato_single
        return !is_group(o) && spans_whole_string(o)
    elseif name === :plato_whole
        return string_spanning_group(o)
    elseif name === :plato_alphabetic_first
        return get_descriptor_for(o, net[:plato_letter_category]) === net[:plato_a]
    elseif name === :plato_alphabetic_last
        return get_descriptor_for(o, net[:plato_letter_category]) === net[:plato_z]
    elseif name === :plato_letter
        return !is_group(o)
    elseif name === :plato_group
        return is_group(o)
    end
    return false
end

"""`(get-possible-descriptors object)` — the instances of this category node
that could describe the object. Instance links are CONSed, so this walks them
in reverse declaration order."""
get_possible_descriptors(n::Node, o, net::Slipnet) =
    Node[d for d in instance_nodes(n) if possible_descriptor(d, o, net)]

description_possible(n::Node, o, net::Slipnet) =
    any(d -> possible_descriptor(d, o, net), instance_nodes(n))

"""`(update-slipnet-activations)`. Active themes get first say: each one tries
to keep its own dimension and relation alive before the network decays."""
function update_slipnet_activations!(net::Slipnet, rng::PyRandom, ts = nothing)
    if ts !== nothing
        for theme in get_all_active_themes(ts)
            spread_activation_to_slipnet!(theme, rng)
        end
    end
    for n in net.nodes
        decay_activation!(n)
    end
    for n in net.nodes
        fully_active(n) && spread_activation!(n)
    end
    for n in net.nodes
        flush_activation_buffer!(n)
    end
    for n in net.nodes
        if partially_active(n)
            # stochastic-if* ALWAYS draws, unlike prob? which short-circuits.
            coin = random_real(rng, 1.0)
            if coin < cube(pct(n.activation))
                update_activation!(n, MAX_ACTIVATION)
            end
        end
    end
    return net
end

"""`(relationship-between nodes)` — the single label relating every adjacent
pair, or nothing if they differ or any is missing."""
function relationship_between(nodes, identity_node::Node)
    any(n -> n === nothing, nodes) && return nothing
    length(nodes) < 2 && return nothing
    relations = [label_between(nodes[i], nodes[i + 1], identity_node)
                 for i in 1:(length(nodes) - 1)]
    any(r -> r === nothing, relations) && return nothing
    all(r -> r === relations[1], relations) || return nothing
    return relations[1]
end
