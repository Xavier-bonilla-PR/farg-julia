# Mirrors copycat/slipnode.py, sliplink.py and slipnet.py.

jump_threshold() = 55.0

function Slipnode(slipnet::AbstractSlipnet, name::AbstractString, depth::Float64,
                  len::Float64 = 0.0)
    Slipnode(slipnet, String(name), depth, len, len * 0.4,
             0.0, 0.0, 0.0, false,
             AbstractSliplink[], AbstractSliplink[], AbstractSliplink[],
             AbstractSliplink[], AbstractSliplink[], AbstractSliplink[],
             AbstractSliplink[], String[])
end

function reset!(n::Slipnode)
    n.buffer = 0.0
    n.activation = 0.0
end

clampHigh!(n::Slipnode) = (n.clamped = true; n.activation = 100.0)
unclamp!(n::Slipnode) = (n.clamped = false)
unclamped(n::Slipnode) = !n.clamped

function category(n::Slipnode)
    isempty(n.categoryLinks) && return nothing
    return (n.categoryLinks[1]::Sliplink).destination
end

"""Whether this node has full activation."""
fully_active(n::Slipnode) = n.activation > 100.0 - 0.00001

function bondDegreeOfAssociation(n::Slipnode)
    linkLength = fully_active(n) ? n.shrunkLinkLength : n.intrinsicLinkLength
    return min(100.0, sqrt(100 - linkLength) * 11.0)
end

function degreeOfAssociation(n::Slipnode)
    linkLength = fully_active(n) ? n.shrunkLinkLength : n.intrinsicLinkLength
    return 100.0 - linkLength
end

"""Whether the other is among the outgoing links."""
linked(n::Slipnode, other::Slipnode) =
    any(l -> points_at(l::Sliplink, other), n.outgoingLinks)

"""Whether the other is among the lateral slip links."""
slipLinked(n::Slipnode, other::Slipnode) =
    any(l -> points_at(l::Sliplink, other), n.lateralSlipLinks)

"""Same or linked."""
related(n::Slipnode, other::Slipnode) = n === other || linked(n, other)

function applySlippages(n::Slipnode, slippages)
    for slippage in slippages
        if n === slippage.initialDescriptor
            return slippage.targetDescriptor
        end
    end
    return n
end

"""The node linked to this one via `relation`, or nothing."""
function getRelatedNode(n::Slipnode, relation::Slipnode)
    slipnet = n.slipnet::Slipnet
    relation === slipnet.identity && return n
    for l in n.outgoingLinks
        link = l::Sliplink
        if link.label === relation
            return link.destination
        end
    end
    return nothing
end

"""The label of the link between these nodes, if any."""
function getBondCategory(n::Slipnode, destination::Slipnode)
    slipnet = n.slipnet::Slipnet
    n === destination && return slipnet.identity
    for l in n.outgoingLinks
        link = l::Sliplink
        if link.destination === destination
            return link.label
        end
    end
    return nothing
end

function update!(n::Slipnode)
    n.oldActivation = n.activation
    n.buffer -= n.activation * (100.0 - n.conceptualDepth) / 100.0
end

function spread_activation!(n::Slipnode)
    if fully_active(n)
        for l in n.outgoingLinks
            spread_activation!(l::Sliplink)
        end
    end
end

function addBuffer!(n::Slipnode)
    if unclamped(n)
        n.activation += n.buffer
    end
    n.activation = min(max(0.0, n.activation), 100.0)
end

function jump!(n::Slipnode, random::Randomness)
    (n.clamped || n.activation <= jump_threshold()) && return
    v = (n.activation / 100.0)^3
    if coinFlip(random, v)
        n.activation = 100.0
    end
end

get_name(n::Slipnode) = length(n.name) == 1 ? uppercase(n.name) : n.name

# --- Sliplink ----------------------------------------------------------------

function degreeOfAssociation(l::Sliplink)
    (l.fixedLength > 0 || l.label === nothing) && return 100.0 - l.fixedLength
    return degreeOfAssociation(l.label::Slipnode)
end

function intrinsicDegreeOfAssociation(l::Sliplink)
    l.fixedLength > 1 && return 100.0 - l.fixedLength
    l.label !== nothing && return 100.0 - (l.label::Slipnode).intrinsicLinkLength
    return 0.0
end

spread_activation!(l::Sliplink) =
    (l.destination.buffer += intrinsicDegreeOfAssociation(l))

points_at(l::Sliplink, other::Slipnode) = l.destination === other

# --- Slipnet -----------------------------------------------------------------

function reset!(s::Slipnet)
    s.numberOfUpdates = 0
    for node in s.slipnodes
        reset!(node)
    end
    for node in s.initiallyClampedSlipnodes
        clampHigh!(node)
    end
    return s
end

function update!(s::Slipnet, random::Randomness)
    s.numberOfUpdates += 1
    if s.numberOfUpdates == 50
        for node in s.initiallyClampedSlipnodes
            unclamp!(node)
        end
    end
    for node in s.slipnodes
        update!(node)
    end
    for node in s.slipnodes
        spread_activation!(node)
    end
    for node in s.slipnodes
        addBuffer!(node)
        jump!(node, random)
        node.buffer = 0.0
    end
    return s
end

"""Whether no other object of the same type has the same descriptor."""
function isDistinguishingDescriptor(s::Slipnet, descriptor::Slipnode)
    descriptor === s.letter && return false
    descriptor === s.group && return false
    any(n -> n === descriptor, s.numbers) && return false
    return true
end

function addNode!(s::Slipnet, name, depth, len = 0.0)
    node = Slipnode(s, name, Float64(depth), Float64(len))
    push!(s.slipnodes, node)
    return node
end

function addLink!(s::Slipnet, source, destination, label = nothing, len = 0.0)
    link = Sliplink(source, destination, label, Float64(len))
    push!(source.outgoingLinks, link)
    push!(destination.incomingLinks, link)
    push!(s.sliplinks, link)
    return link
end

addSlipLink!(s, src, dst; label = nothing, len = 0.0) =
    push!(src.lateralSlipLinks, addLink!(s, src, dst, label, len))
addNonSlipLink!(s, src, dst; label = nothing, len = 0.0) =
    push!(src.lateralNonSlipLinks, addLink!(s, src, dst, label, len))

function addBidirectionalLink!(s, src, dst, len)
    addNonSlipLink!(s, src, dst; len = len)
    addNonSlipLink!(s, dst, src; len = len)
end

addCategoryLink!(s, src, dst, len) =
    push!(src.categoryLinks, addLink!(s, src, dst, nothing, len))

function addInstanceLink!(s, src, dst, len = 100.0)
    categoryLength = src.conceptualDepth - dst.conceptualDepth
    addCategoryLink!(s, dst, src, categoryLength)
    push!(src.instanceLinks, addLink!(s, src, dst, nothing, len))
end

addPropertyLink!(s, src, dst, len) =
    push!(src.propertyLinks, addLink!(s, src, dst, nothing, len))

function addOppositeLink!(s, src, dst)
    addSlipLink!(s, src, dst; label = s.opposite)
    addSlipLink!(s, dst, src; label = s.opposite)
end

function link_items_to_their_neighbors!(s::Slipnet, items)
    previous = items[1]
    for item in items[2:end]
        addNonSlipLink!(s, previous, item; label = s.successor)
        addNonSlipLink!(s, item, previous; label = s.predecessor)
        previous = item
    end
end

function build_slipnet()
    s = Slipnet()

    for c in "abcdefghijklmnopqrstuvwxyz"
        push!(s.letters, addNode!(s, string(c), 10.0))
    end
    for c in "12345"
        push!(s.numbers, addNode!(s, string(c), 30.0))
    end

    # string positions
    s.leftmost = addNode!(s, "leftmost", 40.0)
    s.rightmost = addNode!(s, "rightmost", 40.0)
    s.middle = addNode!(s, "middle", 40.0)
    s.single = addNode!(s, "single", 40.0)
    s.whole = addNode!(s, "whole", 40.0)

    # alphabetic positions
    s.first = addNode!(s, "first", 60.0)
    s.last = addNode!(s, "last", 60.0)

    # directions
    s.left = addNode!(s, "left", 40.0)
    append!(s.left.codelets, ["top-down-bond-scout--direction", "top-down-group-scout--direction"])
    s.right = addNode!(s, "right", 40.0)
    append!(s.right.codelets, ["top-down-bond-scout--direction", "top-down-group-scout--direction"])

    # bond types
    s.predecessor = addNode!(s, "predecessor", 50.0, 60.0)
    push!(s.predecessor.codelets, "top-down-bond-scout--category")
    s.successor = addNode!(s, "successor", 50.0, 60.0)
    push!(s.successor.codelets, "top-down-bond-scout--category")
    s.sameness = addNode!(s, "sameness", 80.0)
    push!(s.sameness.codelets, "top-down-bond-scout--category")

    # group types
    s.predecessorGroup = addNode!(s, "predecessorGroup", 50.0)
    push!(s.predecessorGroup.codelets, "top-down-group-scout--category")
    s.successorGroup = addNode!(s, "successorGroup", 50.0)
    push!(s.successorGroup.codelets, "top-down-group-scout--category")
    s.samenessGroup = addNode!(s, "samenessGroup", 80.0)
    push!(s.samenessGroup.codelets, "top-down-group-scout--category")

    # other relations
    s.identity = addNode!(s, "identity", 90.0)
    s.opposite = addNode!(s, "opposite", 90.0, 80.0)

    # objects
    s.letter = addNode!(s, "letter", 20.0)
    s.group = addNode!(s, "group", 80.0)

    # categories
    s.letterCategory = addNode!(s, "letterCategory", 30.0)
    s.stringPositionCategory = addNode!(s, "stringPositionCategory", 70.0)
    push!(s.stringPositionCategory.codelets, "top-down-description-scout")
    s.alphabeticPositionCategory = addNode!(s, "alphabeticPositionCategory", 80.0)
    push!(s.alphabeticPositionCategory.codelets, "top-down-description-scout")
    s.directionCategory = addNode!(s, "directionCategory", 70.0)
    s.bondCategory = addNode!(s, "bondCategory", 80.0)
    s.groupCategory = addNode!(s, "groupCategory", 80.0)
    s.length = addNode!(s, "length", 60.0)
    s.objectCategory = addNode!(s, "objectCategory", 90.0)
    s.bondFacet = addNode!(s, "bondFacet", 90.0)

    # some factors are considered "very relevant" a priori
    s.initiallyClampedSlipnodes = [s.letterCategory, s.stringPositionCategory]

    # --- links ---
    link_items_to_their_neighbors!(s, s.letters)
    link_items_to_their_neighbors!(s, s.numbers)
    for letter in s.letters
        addInstanceLink!(s, s.letterCategory, letter, 97.0)
    end
    addCategoryLink!(s, s.samenessGroup, s.letterCategory, 50.0)
    for number in s.numbers
        addInstanceLink!(s, s.length, number)
    end
    for group in (s.predecessorGroup, s.successorGroup, s.samenessGroup)
        addNonSlipLink!(s, group, s.length; len = 95.0)
    end
    for (a, b) in ((s.first, s.last), (s.leftmost, s.rightmost), (s.left, s.right),
                   (s.successor, s.predecessor), (s.successorGroup, s.predecessorGroup))
        addOppositeLink!(s, a, b)
    end
    addPropertyLink!(s, s.letters[1], s.first, 75.0)
    addPropertyLink!(s, s.letters[end], s.last, 75.0)
    for (a, b) in ((s.objectCategory, s.letter), (s.objectCategory, s.group),
                   (s.stringPositionCategory, s.leftmost),
                   (s.stringPositionCategory, s.rightmost),
                   (s.stringPositionCategory, s.middle),
                   (s.stringPositionCategory, s.single),
                   (s.stringPositionCategory, s.whole),
                   (s.alphabeticPositionCategory, s.first),
                   (s.alphabeticPositionCategory, s.last),
                   (s.directionCategory, s.left), (s.directionCategory, s.right),
                   (s.bondCategory, s.predecessor), (s.bondCategory, s.successor),
                   (s.bondCategory, s.sameness),
                   (s.groupCategory, s.predecessorGroup),
                   (s.groupCategory, s.successorGroup),
                   (s.groupCategory, s.samenessGroup),
                   (s.bondFacet, s.letterCategory), (s.bondFacet, s.length))
        addInstanceLink!(s, a, b)
    end
    # link bonds to their groups
    addNonSlipLink!(s, s.sameness, s.samenessGroup; label = s.groupCategory, len = 30.0)
    addNonSlipLink!(s, s.successor, s.successorGroup; label = s.groupCategory, len = 60.0)
    addNonSlipLink!(s, s.predecessor, s.predecessorGroup; label = s.groupCategory, len = 60.0)
    # link bond groups to their bonds
    addNonSlipLink!(s, s.samenessGroup, s.sameness; label = s.bondCategory, len = 90.0)
    addNonSlipLink!(s, s.successorGroup, s.successor; label = s.bondCategory, len = 90.0)
    addNonSlipLink!(s, s.predecessorGroup, s.predecessor; label = s.bondCategory, len = 90.0)
    # letter category to length
    addSlipLink!(s, s.letterCategory, s.length; len = 95.0)
    addSlipLink!(s, s.length, s.letterCategory; len = 95.0)
    # letter to group
    addSlipLink!(s, s.letter, s.group; len = 90.0)
    addSlipLink!(s, s.group, s.letter; len = 90.0)
    # direction-position, direction-neighbor, position-neighbor
    addBidirectionalLink!(s, s.left, s.leftmost, 90.0)
    addBidirectionalLink!(s, s.right, s.rightmost, 90.0)
    addBidirectionalLink!(s, s.right, s.leftmost, 100.0)
    addBidirectionalLink!(s, s.left, s.rightmost, 100.0)
    addBidirectionalLink!(s, s.leftmost, s.first, 100.0)
    addBidirectionalLink!(s, s.rightmost, s.first, 100.0)
    addBidirectionalLink!(s, s.leftmost, s.last, 100.0)
    addBidirectionalLink!(s, s.rightmost, s.last, 100.0)
    # other
    addSlipLink!(s, s.single, s.whole; len = 90.0)
    addSlipLink!(s, s.whole, s.single; len = 90.0)

    reset!(s)
    return s
end
