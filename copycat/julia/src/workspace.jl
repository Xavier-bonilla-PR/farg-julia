# Mirrors copycat/workspaceStructure.py, workspaceObject.py, workspaceString.py,
# letter.py, group.py, bond.py, description.py, conceptMapping.py,
# correspondence.py, replacement.py, rule.py, workspace.py and
# workspaceFormulas.py.

# Python's `list.remove` / `in` compare with `==`, which for all of these
# classes is identity, so these helpers spell that out.
function remove_first!(v::AbstractVector, x)
    i = findfirst(y -> y === x, v)
    i === nothing || deleteat!(v, i)
    return v
end
contains_identical(v::AbstractVector, x) = any(y -> y === x, v)

# --- WorkspaceStructure ------------------------------------------------------

function updateTotalStrength!(s::WSStructure)
    s.totalStrength = weightedAverage((
        (s.internalStrength, s.internalStrength),
        (s.externalStrength, 100 - s.internalStrength)))
end

function updateStrength!(s::WSStructure)
    updateInternalStrength!(s)
    updateExternalStrength!(s)
    updateTotalStrength!(s)
end

totalWeakness(s::WSStructure) = 100 - s.totalStrength^0.95

# --- WorkspaceObject ---------------------------------------------------------

spansString(o::WSObject) = o.leftmost && o.rightmost

function addDescription!(o::WSObject, descriptionType::Slipnode, descriptor::Slipnode)
    push!(o.descriptions, Description(o.ctx, o.string, 0.0, 0.0, 0.0, o,
                                      descriptionType, descriptor))
end

function addDescriptions!(o::WSObject, descriptions)
    workspace = (o.ctx::Copycat).workspace
    for description in copy(descriptions)   # in case we add to our own descriptions
        if !containsDescription(o, description)
            addDescription!(o, description.descriptionType, description.descriptor)
        end
    end
    buildDescriptions!(workspace, o)
end

function calculateIntraStringHappiness(o::WSObject)
    spansString(o) && return 100.0
    o.group !== nothing && return (o.group::Group).totalStrength
    bondStrength = 0.0
    for bond in o.bonds
        bondStrength += (bond::Bond).totalStrength
    end
    return bondStrength / 6.0
end

"""The sum of all relevant descriptions."""
function calculateRawImportance(o::WSObject)
    result = 0.0
    for d in o.descriptions
        description = d::Description
        if fully_active(description.descriptionType)
            result += description.descriptor.activation
        else
            result += description.descriptor.activation / 20.0
        end
    end
    o.group !== nothing && (result *= 2.0 / 3.0)
    o.changed && (result *= 2.0)
    return result
end

function updateValue!(o::WSObject)
    o.rawImportance = calculateRawImportance(o)
    intraStringHappiness = calculateIntraStringHappiness(o)
    o.intraStringUnhappiness = 100.0 - intraStringHappiness

    interStringHappiness = 0.0
    if o.correspondence !== nothing
        interStringHappiness = (o.correspondence::Correspondence).totalStrength
    end
    o.interStringUnhappiness = 100.0 - interStringHappiness

    averageHappiness = (intraStringHappiness + interStringHappiness) / 2
    o.totalUnhappiness = 100.0 - averageHappiness

    o.intraStringSalience = weightedAverage((
        (o.relativeImportance, 0.2), (o.intraStringUnhappiness, 0.8)))
    o.interStringSalience = weightedAverage((
        (o.relativeImportance, 0.8), (o.interStringUnhappiness, 0.2)))
    o.totalSalience = (o.intraStringSalience + o.interStringSalience) / 2.0
end

isWithin(o::WSObject, other::WSObject) =
    o.leftIndex >= other.leftIndex && o.rightIndex <= other.rightIndex
isOutsideOf(o::WSObject, other::WSObject) =
    o.leftIndex > other.rightIndex || o.rightIndex < other.leftIndex

relevantDescriptions(o::WSObject) =
    Description[d for d in o.descriptions if fully_active((d::Description).descriptionType)]

function getPossibleDescriptions(o::WSObject, descriptionType::Slipnode)
    slipnet = (o.ctx::Copycat).slipnet
    descriptions = Slipnode[]
    for l in descriptionType.instanceLinks
        node = (l::Sliplink).destination
        if node === slipnet.first && described(o, slipnet.letters[1])
            push!(descriptions, node)
        end
        if node === slipnet.last && described(o, slipnet.letters[end])
            push!(descriptions, node)
        end
        for (i, number) in enumerate(slipnet.numbers)
            if node === number && o isa Group
                if length((o::Group).objectList) == i
                    push!(descriptions, node)
                end
            end
        end
        if node === slipnet.middle && middleObject(o)
            push!(descriptions, node)
        end
    end
    return descriptions
end

function containsDescription(o::WSObject, sought)
    for d in o.descriptions
        description = d::Description
        if sought.descriptionType === description.descriptionType &&
           sought.descriptor === description.descriptor
            return true
        end
    end
    return false
end

described(o::WSObject, slipnode::Slipnode) =
    any(d -> (d::Description).descriptor === slipnode, o.descriptions)

"""Only works if the string is 3 chars long."""
function middleObject(o::WSObject)
    objectOnMyRightIsRightmost = false
    objectOnMyLeftIsLeftmost = false
    for objekt in o.string.objects
        if objekt.leftmost && objekt.rightIndex == o.leftIndex - 1
            objectOnMyLeftIsLeftmost = true
        end
        if objekt.rightmost && objekt.leftIndex == o.rightIndex + 1
            objectOnMyRightIsRightmost = true
        end
    end
    return objectOnMyRightIsRightmost && objectOnMyLeftIsLeftmost
end

function relevantDistinguishingDescriptors(o::WSObject)
    slipnet = (o.ctx::Copycat).slipnet
    return Slipnode[(d::Description).descriptor for d in relevantDescriptions(o)
                    if isDistinguishingDescriptor(slipnet, (d::Description).descriptor)]
end

"""The description attached to this object of the given description type."""
function getDescriptor(o::WSObject, descriptionType::Slipnode)
    for d in o.descriptions
        description = d::Description
        if description.descriptionType === descriptionType
            return description.descriptor
        end
    end
    return nothing
end

"""The description type attached to this object for the given description."""
function getDescriptionType(o::WSObject, sought::Slipnode)
    for d in o.descriptions
        description = d::Description
        if description.descriptor === sought
            return description.descriptionType
        end
    end
    return nothing
end

getCommonGroups(o::WSObject, other::WSObject) =
    WSObject[g for g in o.string.objects if isWithin(o, g) && isWithin(other, g)]

function letterDistance(o::WSObject, other::WSObject)
    other.leftIndex > o.rightIndex && return other.leftIndex - o.rightIndex
    o.leftIndex > other.rightIndex && return o.leftIndex - other.rightIndex
    return 0
end

letterSpan(o::WSObject) = o.rightIndex - o.leftIndex + 1

function beside(o::WSObject, other::WSObject)
    o.string === other.string || return false
    o.leftIndex == other.rightIndex + 1 && return true
    return other.leftIndex == o.rightIndex + 1
end

# --- Letter ------------------------------------------------------------------

function Letter(string::WorkspaceString, position::Int, len::Int)
    ctx = string.ctx
    l = Letter(ctx, string, 0.0, 0.0, 0.0,
               Description[], Bond[], nothing, false, nothing,
               0.0, 0.0, nothing, nothing, "", nothing,
               position, position, position == 1, position == len,
               0.0, 0.0, 0.0, 0.0, 0.0, 0.0)
    push!((ctx::Copycat).workspace.objects, l)
    push!(string.objects, l)
    return l
end

function describe!(l::Letter, position::Int, len::Int)
    slipnet = (l.ctx::Copycat).slipnet
    if len == 1
        addDescription!(l, slipnet.stringPositionCategory, slipnet.single)
    end
    if l.leftmost
        addDescription!(l, slipnet.stringPositionCategory, slipnet.leftmost)
    end
    if l.rightmost
        addDescription!(l, slipnet.stringPositionCategory, slipnet.rightmost)
    end
    if position * 2 == len + 1
        addDescription!(l, slipnet.stringPositionCategory, slipnet.middle)
    end
end

"""Whether no other object of the same type has the same descriptor."""
function distinguishingDescriptor(l::Letter, descriptor::Slipnode)
    slipnet = (l.ctx::Copycat).slipnet
    isDistinguishingDescriptor(slipnet, descriptor) || return false
    for objekt in l.string.objects
        if objekt isa Letter && objekt !== l
            for d in objekt.descriptions
                (d::Description).descriptor === descriptor && return false
            end
        end
    end
    return true
end

function distinguishingDescriptor(g::Group, descriptor::Slipnode)
    slipnet = (g.ctx::Copycat).slipnet
    isDistinguishingDescriptor(slipnet, descriptor) || return false
    for objekt in g.string.objects
        if objekt isa Group && objekt !== g
            for d in objekt.descriptions
                (d::Description).descriptor === descriptor && return false
            end
        end
    end
    return true
end

# --- WorkspaceString ---------------------------------------------------------

function build_string!(ctx, s::AbstractString)
    ws = WorkspaceString(ctx, s)
    slipnet = (ctx::Copycat).slipnet
    workspace = (ctx::Copycat).workspace
    for (position, c) in enumerate(uppercase(ws.string))
        value = Int(c) - Int('A')
        letter = Letter(ws, position, ws.length)
        addDescription!(letter, slipnet.objectCategory, slipnet.letter)
        addDescription!(letter, slipnet.letterCategory, slipnet.letters[value + 1])
        describe!(letter, position, ws.length)
        buildDescriptions!(workspace, letter)
        push!(ws.letters, letter)
    end
    return ws
end

Base.length(ws::WorkspaceString) = length(ws.string)

"""Update the normalised importance of all objects in the string."""
function updateRelativeImportance!(ws::WorkspaceString)
    total = 0.0
    for o in ws.objects
        total += o.rawImportance
    end
    if total == 0
        for o in ws.objects
            o.relativeImportance = 0.0
        end
    else
        for o in ws.objects
            o.relativeImportance = o.rawImportance / total
        end
    end
end

function updateIntraStringUnhappiness!(ws::WorkspaceString)
    if isempty(ws.objects)
        ws.intraStringUnhappiness = 0.0
        return
    end
    total = 0.0
    for o in ws.objects
        total += o.intraStringUnhappiness
    end
    ws.intraStringUnhappiness = total / length(ws.objects)
end

function equivalentGroup(ws::WorkspaceString, sought::Group)
    for objekt in ws.objects
        if objekt isa Group && sameGroup(objekt::Group, sought)
            return objekt::Group
        end
    end
    return nothing
end

# --- Description -------------------------------------------------------------

updateInternalStrength!(d::Description) = (d.internalStrength = d.descriptor.conceptualDepth)
updateExternalStrength!(d::Description) =
    (d.externalStrength = (localSupport(d) + d.descriptionType.activation) / 2)

function localSupport(d::Description)
    workspace = (d.ctx::Copycat).workspace
    described_like_self = 0
    for other in workspace.objects
        d.object === other && continue
        (isWithin(d.object, other) || isWithin(other, d.object)) && continue
        for od in other.descriptions
            if (od::Description).descriptionType === d.descriptionType
                described_like_self += 1
            end
        end
    end
    described_like_self == 0 && return 0.0
    described_like_self == 1 && return 20.0
    described_like_self == 2 && return 60.0
    described_like_self == 3 && return 90.0
    return 100.0
end

function build!(d::Description)
    d.descriptionType.buffer = 100.0
    d.descriptor.buffer = 100.0
    if !described(d.object, d.descriptor)
        push!(d.object.descriptions, d)
    end
end

function breakDescription!(d::Description)
    workspace = (d.ctx::Copycat).workspace
    if contains_identical(workspace.structures, d)
        remove_first!(workspace.structures, d)
    end
    remove_first!(d.object.descriptions, d)
end

# --- ConceptMapping ----------------------------------------------------------

function ConceptMapping(initialDescriptionType::Slipnode, targetDescriptionType::Slipnode,
                        initialDescriptor::Slipnode, targetDescriptor::Slipnode,
                        initialObject, targetObject)
    ConceptMapping(initialDescriptionType.slipnet::Slipnet,
                   initialDescriptionType, targetDescriptionType,
                   initialDescriptor, targetDescriptor,
                   initialObject, targetObject,
                   getBondCategory(initialDescriptor, targetDescriptor))
end

"""Assumes the 2 descriptors are connected in the slipnet by <= 1 link."""
function cm_degreeOfAssociation(m::ConceptMapping)
    m.initialDescriptor === m.targetDescriptor && return 100.0
    for l in m.initialDescriptor.lateralSlipLinks
        link = l::Sliplink
        if link.destination === m.targetDescriptor
            return degreeOfAssociation(link)
        end
    end
    return 0.0
end

cm_conceptualDepth(m::ConceptMapping) =
    (m.initialDescriptor.conceptualDepth + m.targetDescriptor.conceptualDepth) / 2.0

function slippability(m::ConceptMapping)
    association = cm_degreeOfAssociation(m)
    association == 100.0 && return 100.0
    depth = cm_conceptualDepth(m) / 100.0
    return association * (1 - depth * depth)
end

function strength(m::ConceptMapping)
    association = cm_degreeOfAssociation(m)
    association == 100.0 && return 100.0
    depth = cm_conceptualDepth(m) / 100.0
    return association * (1 + depth * depth)
end

function distinguishing(m::ConceptMapping)
    slipnet = m.slipnet
    if m.initialDescriptor === slipnet.whole && m.targetDescriptor === slipnet.whole
        return false
    end
    distinguishingDescriptor(m.initialObject::WSObject, m.initialDescriptor) || return false
    return distinguishingDescriptor(m.targetObject::WSObject, m.targetDescriptor)
end

sameInitialType(m::ConceptMapping, o::ConceptMapping) =
    m.initialDescriptionType === o.initialDescriptionType
sameTargetType(m::ConceptMapping, o::ConceptMapping) =
    m.targetDescriptionType === o.targetDescriptionType
sameTypes(m::ConceptMapping, o::ConceptMapping) = sameInitialType(m, o) && sameTargetType(m, o)
sameInitialDescriptor(m::ConceptMapping, o::ConceptMapping) =
    m.initialDescriptor === o.initialDescriptor
sameTargetDescriptor(m::ConceptMapping, o::ConceptMapping) =
    m.targetDescriptor === o.targetDescriptor
sameDescriptors(m::ConceptMapping, o::ConceptMapping) =
    sameInitialDescriptor(m, o) ? sameTargetDescriptor(m, o) : false
sameKind(m::ConceptMapping, o::ConceptMapping) = sameTypes(m, o) && sameDescriptors(m, o)
nearlySameKind(m::ConceptMapping, o::ConceptMapping) =
    sameTypes(m, o) && sameInitialDescriptor(m, o)
isContainedBy(m::ConceptMapping, mappings) = any(o -> sameKind(m, o), mappings)
isNearlyContainedBy(m::ConceptMapping, mappings) = any(o -> nearlySameKind(m, o), mappings)

function cm_related(m::ConceptMapping, o::ConceptMapping)
    related(m.initialDescriptor, o.initialDescriptor) && return true
    return related(m.targetDescriptor, o.targetDescriptor)
end

# (a -> b) and (c -> d) are incompatible if a is related to c or b to d, and
# the a -> b relationship differs from the c -> d relationship.
function incompatible(m::ConceptMapping, o::ConceptMapping)
    cm_related(m, o) || return false
    (m.label === nothing || o.label === nothing) && return false
    return m.label !== o.label
end

# (a -> b) and (c -> d) support each other if a is related to c, b to d, and
# the relationships are the same.
function supports(m::ConceptMapping, o::ConceptMapping)
    sameDescriptors(m, o) && return true
    cm_related(m, o) || return false
    (m.label === nothing || o.label === nothing) && return false
    return m.label === o.label
end

relevant(m::ConceptMapping) =
    fully_active(m.initialDescriptionType) ? fully_active(m.targetDescriptionType) : false

slippage(m::ConceptMapping) =
    !(m.label === m.slipnet.sameness || m.label === m.slipnet.identity)

function symmetricVersion(m::ConceptMapping)
    slippage(m) || return m
    bond = getBondCategory(m.targetDescriptor, m.initialDescriptor)
    bond === m.label && return m
    # The Python original references `self.initialDescriptor1` here, which does
    # not exist; reaching this branch raises AttributeError there. Mirror that
    # rather than silently inventing different behaviour.
    error("symmetricVersion: unreachable branch reached (matches an " *
          "AttributeError in the Python original)")
end

# --- Replacement -------------------------------------------------------------

Replacement(ctx, objectFromInitial, objectFromModified, relation) =
    Replacement(ctx, 0.0, 0.0, 0.0, objectFromInitial, objectFromModified, relation)
