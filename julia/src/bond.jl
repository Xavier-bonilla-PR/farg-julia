# Mirrors copycat/bond.py.

function Bond(ctx, source::WSObject, destination::WSObject, bondCategory::Slipnode,
              bondFacet::Slipnode, sourceDescriptor::Slipnode,
              destinationDescriptor::Slipnode)
    slipnet = (ctx::Copycat).slipnet
    leftObject = source
    rightObject = destination
    directionCategory = slipnet.right
    if source.leftIndex > destination.rightIndex
        leftObject = destination
        rightObject = source
        directionCategory = slipnet.left
    end
    dc = sourceDescriptor === destinationDescriptor ? nothing : directionCategory
    return Bond(ctx, source.string, 0.0, 0.0, 0.0,
                source, destination, leftObject, rightObject, dc,
                bondFacet, sourceDescriptor, destinationDescriptor, bondCategory)
end

function flippedVersion(b::Bond)
    slipnet = (b.ctx::Copycat).slipnet
    return Bond(b.ctx, b.destination, b.source,
                getRelatedNode(b.category, slipnet.opposite),
                b.facet, b.destinationDescriptor, b.sourceDescriptor)
end

function buildBond!(b::Bond)
    workspace = (b.ctx::Copycat).workspace
    push!(workspace.structures, b)
    push!(b.string.bonds, b)
    b.category.buffer = 100.0
    if b.directionCategory !== nothing
        (b.directionCategory::Slipnode).buffer = 100.0
    end
    b.leftObject.rightBond = b
    b.rightObject.leftBond = b
    push!(b.leftObject.bonds, b)
    push!(b.rightObject.bonds, b)
end

break_the_structure!(b::Bond) = breakBond!(b)

function breakBond!(b::Bond)
    workspace = (b.ctx::Copycat).workspace
    contains_identical(workspace.structures, b) && remove_first!(workspace.structures, b)
    contains_identical(b.string.bonds, b) && remove_first!(b.string.bonds, b)
    b.leftObject.rightBond = nothing
    b.rightObject.leftBond = nothing
    contains_identical(b.leftObject.bonds, b) && remove_first!(b.leftObject.bonds, b)
    contains_identical(b.rightObject.bonds, b) && remove_first!(b.rightObject.bonds, b)
end

"""Correspondences that are incompatible with this bond."""
function getIncompatibleCorrespondences(b::Bond)
    workspace = (b.ctx::Copycat).workspace
    incompatibles = Correspondence[]
    if b.leftObject.leftmost && b.leftObject.correspondence !== nothing
        correspondence = b.leftObject.correspondence::Correspondence
        objekt = b.string === workspace.initial ? correspondence.objectFromTarget :
                                                  correspondence.objectFromInitial
        if objekt.leftmost && objekt.rightBond !== nothing
            rb = objekt.rightBond::Bond
            if rb.directionCategory !== nothing && rb.directionCategory !== b.directionCategory
                push!(incompatibles, correspondence)
            end
        end
    end
    if b.rightObject.rightmost && b.rightObject.correspondence !== nothing
        correspondence = b.rightObject.correspondence::Correspondence
        objekt = b.string === workspace.initial ? correspondence.objectFromTarget :
                                                  correspondence.objectFromInitial
        if objekt.rightmost && objekt.leftBond !== nothing
            lb = objekt.leftBond::Bond
            if lb.directionCategory !== nothing && lb.directionCategory !== b.directionCategory
                push!(incompatibles, correspondence)
            end
        end
    end
    return incompatibles
end

function updateInternalStrength!(b::Bond)
    slipnet = (b.ctx::Copycat).slipnet
    # bonds between objects of the same type are stronger than between types
    sourceGap = b.source.leftIndex != b.source.rightIndex
    destinationGap = b.destination.leftIndex != b.destination.rightIndex
    memberCompatibility = sourceGap == destinationGap ? 1.0 : 0.7
    # letter category bonds are stronger
    facetFactor = b.facet === slipnet.letterCategory ? 1.0 : 0.7
    b.internalStrength = min(100.0, memberCompatibility * facetFactor *
                                    bondDegreeOfAssociation(b.category))
end

function updateExternalStrength!(b::Bond)
    b.externalStrength = 0.0
    supporters = numberOfLocalSupportingBonds(b)
    if supporters > 0
        density = localDensity(b) / 100.0
        density = sqrt(density) * 100.0
        supportFactor = 0.6^(1.0 / supporters^3)
        supportFactor = max(1.0, supportFactor)
        b.externalStrength = supportFactor * density
    end
end

function numberOfLocalSupportingBonds(b::Bond)
    count = 0
    for x in b.string.bonds
        other = x::Bond
        if other.string === b.source.string &&
           letterDistance(b.leftObject, other.leftObject) != 0 &&
           letterDistance(b.rightObject, other.rightObject) != 0 &&
           b.category === other.category &&
           b.directionCategory === other.directionCategory
            count += 1
        end
    end
    return count
end

sameCategories(b::Bond, other::Bond) =
    b.category === other.category && b.directionCategory === other.directionCategory

function myEnds(b::Bond, object1::WSObject, object2::WSObject)
    (b.source === object1 && b.destination === object2) && return true
    return b.source === object2 && b.destination === object1
end

"""A rough measure of the density in the string of this bond's categories."""
function localDensity(b::Bond)
    workspace = (b.ctx::Copycat).workspace
    slotSum = 0.0
    supportSum = 0.0
    for object1 in workspace.objects
        object1.string === b.string || continue
        for object2 in workspace.objects
            if beside(object1, object2)
                slotSum += 1.0
                for x in b.string.bonds
                    bond = x::Bond
                    if bond !== b && sameCategories(b, bond) && myEnds(b, object1, object2)
                        supportSum += 1.0
                    end
                end
            end
        end
    end
    slotSum == 0 && return 0.0
    return 100.0 * supportSum / slotSum
end

function sameNeighbors(b::Bond, other::Bond)
    b.leftObject === other.leftObject && return true
    return b.rightObject === other.rightObject
end

getIncompatibleBonds(b::Bond) =
    Bond[x::Bond for x in b.string.bonds if sameNeighbors(b, x::Bond)]

function possibleGroupBonds(b::Bond, bonds)
    result = Bond[]
    slipnet = (b.ctx::Copycat).slipnet
    for x in bonds
        bond = x::Bond
        if bond.category === b.category && bond.directionCategory === b.directionCategory
            push!(result, bond)
        else
            # a modified bond might be made
            bond.category === b.category && return Bond[]
            bond.directionCategory === b.directionCategory && return Bond[]
            (b.category === slipnet.sameness || bond.category === slipnet.sameness) &&
                return Bond[]
            push!(result, Bond(bond.ctx, bond.destination, bond.source, b.category,
                               b.facet, bond.destinationDescriptor, bond.sourceDescriptor))
        end
    end
    return result
end
