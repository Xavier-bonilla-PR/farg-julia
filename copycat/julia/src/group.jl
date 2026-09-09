# Mirrors copycat/group.py.

function Group(string::WorkspaceString, groupCategory::Slipnode,
               directionCategory::Union{Nothing,Slipnode}, facet::Slipnode,
               objectList::Vector{WSObject}, bondList::Vector{Bond})
    ctx = string.ctx
    slipnet = (ctx::Copycat).slipnet
    bondCategory = getRelatedNode(groupCategory, slipnet.bondCategory)::Slipnode

    leftObject = objectList[1]
    rightObject = objectList[end]
    leftIndex = leftObject.leftIndex
    rightIndex = rightObject.rightIndex

    g = Group(ctx, string, 0.0, 0.0, 0.0,
              Description[], Bond[], nothing, false, nothing,
              0.0, 0.0, nothing, nothing, "", nothing,
              rightIndex, leftIndex, leftIndex == 1, rightIndex == length(string),
              0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
              groupCategory, directionCategory, facet, objectList, bondList,
              bondCategory, Description[])

    if !isempty(g.bondList)
        firstFacet = (g.bondList[1]::Bond).facet
        push!(g.bondDescriptions,
              Description(ctx, string, 0.0, 0.0, 0.0, g, slipnet.bondFacet, firstFacet))
    end
    push!(g.bondDescriptions,
          Description(ctx, string, 0.0, 0.0, 0.0, g, slipnet.bondCategory, g.bondCategory))

    addDescription!(g, slipnet.objectCategory, slipnet.group)
    addDescription!(g, slipnet.groupCategory, g.groupCategory)
    if g.directionCategory === nothing
        # sameness group - find letterCategory
        letter = getDescriptor(g.objectList[1], g.facet)::Slipnode
        addDescription!(g, g.facet, letter)
    else
        addDescription!(g, slipnet.directionCategory, g.directionCategory::Slipnode)
    end
    if spansString(g)
        addDescription!(g, slipnet.stringPositionCategory, slipnet.whole)
    elseif g.leftmost
        addDescription!(g, slipnet.stringPositionCategory, slipnet.leftmost)
    elseif g.rightmost
        addDescription!(g, slipnet.stringPositionCategory, slipnet.rightmost)
    elseif middleObject(g)
        addDescription!(g, slipnet.stringPositionCategory, slipnet.middle)
    end
    add_length_description_category!(g)
    return g
end

function add_length_description_category!(g::Group)
    ctx = g.ctx::Copycat
    probability = lengthDescriptionProbability(g)
    if coinFlip(ctx.random, probability)
        len = length(g.objectList)
        if len < 6
            addDescription!(g, ctx.slipnet.length, ctx.slipnet.numbers[len])
        end
    end
end

function getIncompatibleGroups(g::Group)
    result = Group[]
    for o in g.objectList
        objekt = o
        while objekt.group !== nothing
            push!(result, objekt.group::Group)
            objekt = objekt.group::Group
        end
    end
    return result
end

function singleLetterGroupProbability(g::Group)
    ctx = g.ctx::Copycat
    numberOfSupporters = numberOfLocalSupportingGroups(g)
    numberOfSupporters == 0 && return 0.0
    exp = numberOfSupporters == 1 ? 4.0 : (numberOfSupporters == 2 ? 2.0 : 1.0)
    support = localSupport(g) / 100.0
    activation = ctx.slipnet.length.activation / 100.0
    return getAdjustedProbability(ctx.temperature, (support * activation)^exp)
end

function flippedVersion(g::Group)
    # The Python original dereferences `slipnet.flipped`, which does not exist,
    # so this path raises AttributeError there. Mirror that.
    error("Group.flippedVersion: slipnet has no `flipped` node (matches an " *
          "AttributeError in the Python original)")
end

function buildGroup!(g::Group)
    workspace = (g.ctx::Copycat).workspace
    push!(workspace.objects, g)
    push!(workspace.structures, g)
    push!(g.string.objects, g)
    for objekt in g.objectList
        objekt.group = g
    end
    buildDescriptions!(workspace, g)
    activateDescriptions!(g)
end

function activateDescriptions!(g::Group)
    for d in g.descriptions
        (d::Description).descriptor.buffer = 100.0
    end
end

function lengthDescriptionProbability(g::Group)
    ctx = g.ctx::Copycat
    len = length(g.objectList)
    len > 5 && return 0.0
    cubedlength = len^3
    fred = cubedlength * (100.0 - ctx.slipnet.length.activation) / 100.0
    probability = 0.5^fred
    v = getAdjustedProbability(ctx.temperature, probability)
    return v < 0.06 ? 0.0 : v
end

break_the_structure!(g::Group) = breakGroup!(g)

function breakGroup!(g::Group)
    workspace = (g.ctx::Copycat).workspace
    if g.correspondence !== nothing
        breakCorrespondence!(g.correspondence::Correspondence)
    end
    if g.group !== nothing
        breakGroup!(g.group::Group)
    end
    if g.leftBond !== nothing
        breakBond!(g.leftBond::Bond)
    end
    if g.rightBond !== nothing
        breakBond!(g.rightBond::Bond)
    end
    while !isempty(g.descriptions)
        breakDescription!(g.descriptions[end]::Description)
    end
    for o in g.objectList
        o.group = nothing
    end
    contains_identical(workspace.structures, g) && remove_first!(workspace.structures, g)
    contains_identical(workspace.objects, g) && remove_first!(workspace.objects, g)
    contains_identical(g.string.objects, g) && remove_first!(g.string.objects, g)
end

function updateInternalStrength!(g::Group)
    slipnet = (g.ctx::Copycat).slipnet
    relatedBondAssociation =
        degreeOfAssociation(getRelatedNode(g.groupCategory, slipnet.bondCategory)::Slipnode)
    bondWeight = relatedBondAssociation^0.98
    len = length(g.objectList)
    lengthFactor = len == 1 ? 5.0 : (len == 2 ? 20.0 : (len == 3 ? 60.0 : 90.0))
    lengthWeight = 100.0 - bondWeight
    g.internalStrength = weightedAverage(((relatedBondAssociation, bondWeight),
                                          (lengthFactor, lengthWeight)))
end

updateExternalStrength!(g::Group) =
    (g.externalStrength = spansString(g) ? 100.0 : localSupport(g))

function localSupport(g::Group)
    numberOfSupporters = numberOfLocalSupportingGroups(g)
    numberOfSupporters == 0 && return 0.0
    supportFactor = min(1.0, 0.6^(1 / numberOfSupporters^3))
    densityFactor = 100.0 * sqrt(localDensity(g) / 100.0)
    return densityFactor * supportFactor
end

function numberOfLocalSupportingGroups(g::Group)
    count = 0
    for objekt in g.string.objects
        if objekt isa Group && isOutsideOf(g, objekt)
            other = objekt::Group
            if other.groupCategory === g.groupCategory &&
               other.directionCategory === g.directionCategory
                count += 1
            end
        end
    end
    return count
end

localDensity(g::Group) =
    100.0 * numberOfLocalSupportingGroups(g) / (length(g.string) / 2.0)

function sameGroup(g::Group, other::Group)
    g.leftIndex == other.leftIndex || return false
    g.rightIndex == other.rightIndex || return false
    g.groupCategory === other.groupCategory || return false
    g.directionCategory === other.directionCategory || return false
    return g.facet === other.facet
end
