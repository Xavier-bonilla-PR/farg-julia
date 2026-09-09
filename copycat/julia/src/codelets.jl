# Mirrors copycat/codeletMethods.py.
#
# The Python original uses `assert` for a codelet "fizzling" and catches
# AssertionError in Coderack.run. Julia exceptions are comparatively expensive
# and fizzling is the common case, so each of those asserts becomes an early
# `return`, which has exactly the same effect: the codelet stops, having
# already performed whatever side effects (RNG draws, strength updates) the
# Python code performed up to that point.

function getScoutSource(ctx, slipnode::Slipnode, relevanceMethod::F, typeName) where {F}
    cc = ctx::Copycat
    workspace = cc.workspace
    initialRelevance = relevanceMethod(workspace.initial, slipnode)
    targetRelevance = relevanceMethod(workspace.target, slipnode)
    initialUnhappiness = workspace.initial.intraStringUnhappiness
    targetUnhappiness = workspace.target.intraStringUnhappiness
    string = workspace.initial
    initials = initialRelevance + initialUnhappiness
    targets = targetRelevance + targetUnhappiness
    if weighted_greater_than(cc.random, targets, initials)
        string = workspace.target
    end
    return chooseUnmodifiedObject(ctx, :intraStringSalience, string.objects)
end

"""Returns nothing when either descriptor is missing (a fizzle in Python)."""
function getDescriptors(bondFacet::Slipnode, source::WSObject, destination::WSObject)
    sourceDescriptor = getDescriptor(source, bondFacet)
    destinationDescriptor = getDescriptor(destination, bondFacet)
    (sourceDescriptor === nothing || destinationDescriptor === nothing) && return nothing
    return (sourceDescriptor::Slipnode, destinationDescriptor::Slipnode)
end

"""Whether the first structure comes out stronger than the second."""
function structureVsStructure(structure1, weight1, structure2, weight2)
    cc = structure1.ctx::Copycat
    updateStrength!(structure1)
    updateStrength!(structure2)
    weightedStrength1 = getAdjustedValue(cc.temperature, structure1.totalStrength * weight1)
    weightedStrength2 = getAdjustedValue(cc.temperature, structure2.totalStrength * weight2)
    return weighted_greater_than(cc.random, weightedStrength1, weightedStrength2)
end

function fight(structure, structureWeight, incompatibles, incompatibleWeight)
    isempty(incompatibles) && return true
    for incompatible in incompatibles
        structureVsStructure(structure, structureWeight, incompatible, incompatibleWeight) ||
            return false
    end
    return true
end

function fightIncompatibles(incompatibles, structure, name, structureWeight, incompatibleWeight)
    isempty(incompatibles) && return true
    return fight(structure, structureWeight, incompatibles, incompatibleWeight)
end

function slippability(ctx, conceptMappings)
    cc = ctx::Copycat
    for mapping in conceptMappings
        slippiness = slippability(mapping) / 100.0
        if coinFlip(cc.random, getAdjustedProbability(cc.temperature, slippiness))
            return true
        end
    end
    return false
end

# --- codelets ----------------------------------------------------------------

# First decides probabilistically whether to fizzle, based on temperature.
# Chooses a structure at random and decides probabilistically whether to break
# it as a function of its total weakness. Breaking a bond in a group requires
# breaking the group too.
function breaker(ctx, codelet)
    cc = ctx::Copycat
    random = cc.random
    temperature = cc.temperature
    workspace = cc.workspace
    probabilityOfFizzle = (100.0 - value(temperature)) / 100.0
    coinFlip(random, probabilityOfFizzle) && return
    structures = WSStructure[s for s in workspace.structures
                             if s isa Group || s isa Bond || s isa Correspondence]
    isempty(structures) && return
    structure = choice(random, structures)
    breakObjects = WSStructure[structure]
    if structure isa Bond
        b = structure::Bond
        if b.source.group !== nothing && b.source.group === b.destination.group
            push!(breakObjects, b.source.group::Group)
        end
    end
    # Break all the objects or none of them; this matches the Java.
    for s in breakObjects
        if coinFlip(random, getAdjustedProbability(temperature, s.totalStrength / 100.0))
            return
        end
    end
    for s in breakObjects
        break_the_structure!(s)
    end
end

function similarPropertyLinks(ctx, slip_node::Slipnode)
    cc = ctx::Copycat
    result = AbstractSliplink[]
    for l in slip_node.propertyLinks
        link = l::Sliplink
        association = degreeOfAssociation(link) / 100.0
        if coinFlip(cc.random, getAdjustedProbability(cc.temperature, association))
            push!(result, link)
        end
    end
    return result
end

function bottom_up_description_scout(ctx, codelet)
    cc = ctx::Copycat
    chosenObject = chooseUnmodifiedObject(ctx, :totalSalience, cc.workspace.objects)
    chosenObject === nothing && return
    # choose relevant description by activation
    descriptions = relevantDescriptions(chosenObject::WSObject)
    weights = Float64[(d::Description).descriptor.activation for d in descriptions]
    description = weighted_choice(cc.random, descriptions, weights)
    description === nothing && return
    sliplinks = similarPropertyLinks(ctx, (description::Description).descriptor)
    isempty(sliplinks) && return
    weights = Float64[degreeOfAssociation(l::Sliplink) * (l::Sliplink).destination.activation
                      for l in sliplinks]
    chosen = weighted_choice(cc.random, sliplinks, weights)::Sliplink
    chosenProperty = chosen.destination
    proposeDescription!(cc.coderack, chosenObject::WSObject,
                        category(chosenProperty)::Slipnode, chosenProperty)
end

function top_down_description_scout(ctx, codelet)
    cc = ctx::Copycat
    descriptionType = codelet.arguments[1]::Slipnode
    chosenObject = chooseUnmodifiedObject(ctx, :totalSalience, cc.workspace.objects)
    chosenObject === nothing && return
    descriptions = getPossibleDescriptions(chosenObject::WSObject, descriptionType)
    isempty(descriptions) && return
    weights = Float64[n.activation for n in descriptions]
    chosenProperty = weighted_choice(cc.random, descriptions, weights)::Slipnode
    proposeDescription!(cc.coderack, chosenObject::WSObject,
                        category(chosenProperty)::Slipnode, chosenProperty)
end

function description_strength_tester(ctx, codelet)
    cc = ctx::Copycat
    description = codelet.arguments[1]::Description
    description.descriptor.buffer = 100.0
    updateStrength!(description)
    strength = description.totalStrength
    coinFlip(cc.random, getAdjustedProbability(cc.temperature, strength / 100.0)) || return
    newCodelet!(cc.coderack, "description-builder", strength, Any[description])
end

function description_builder(ctx, codelet)
    cc = ctx::Copycat
    description = codelet.arguments[1]::Description
    contains_identical(cc.workspace.objects, description.object) || return
    if described(description.object, description.descriptor)
        description.descriptionType.buffer = 100.0
        description.descriptor.buffer = 100.0
    else
        build!(description)
    end
end

function supportForDescriptionType(ctx, descriptionType::Slipnode, string::WorkspaceString)
    workspace = (ctx::Copycat).workspace
    described_count = 0
    total = 0
    for o in workspace.objects
        o.string === string || continue
        total += 1
        for d in o.descriptions
            (d::Description).descriptionType === descriptionType && (described_count += 1)
        end
    end
    return (descriptionType.activation + described_count / total) / 2
end

function chooseBondFacet(ctx, source::WSObject, destination::WSObject)
    cc = ctx::Copycat
    slipnet = cc.slipnet
    # the descriptor types that bonds can form between
    isfacet(t) = t === slipnet.letterCategory || t === slipnet.length
    sourceFacets = Slipnode[(d::Description).descriptionType for d in source.descriptions
                            if isfacet((d::Description).descriptionType)]
    bondFacets = Slipnode[(d::Description).descriptionType for d in destination.descriptions
                          if any(f -> f === (d::Description).descriptionType, sourceFacets)]
    supports = Float64[supportForDescriptionType(ctx, f, source.string) for f in bondFacets]
    return weighted_choice(cc.random, bondFacets, supports)
end

function bottom_up_bond_scout(ctx, codelet)
    cc = ctx::Copycat
    slipnet = cc.slipnet
    source = chooseUnmodifiedObject(ctx, :intraStringSalience, cc.workspace.objects)
    source === nothing && return
    destination = chooseNeighbor(ctx, source::WSObject)
    destination === nothing && return
    bondFacet = chooseBondFacet(ctx, source::WSObject, destination::WSObject)
    bondFacet === nothing && return
    descriptors = getDescriptors(bondFacet::Slipnode, source::WSObject, destination::WSObject)
    descriptors === nothing && return
    sourceDescriptor, destinationDescriptor = descriptors
    category = getBondCategory(sourceDescriptor, destinationDescriptor)
    category === nothing && return
    if category === slipnet.identity
        category = slipnet.sameness
    end
    proposeBond!(cc.coderack, source::WSObject, destination::WSObject, category::Slipnode,
                 bondFacet::Slipnode, sourceDescriptor, destinationDescriptor)
end

function rule_scout(ctx, codelet)
    cc = ctx::Copycat
    random = cc.random
    slipnet = cc.slipnet
    temperature = cc.temperature
    workspace = cc.workspace
    numberOfUnreplacedObjects(workspace) == 0 || return
    changedObjects = WSObject[o for o in workspace.initial.objects if o.changed]
    # if there are no changed objects, propose a rule with no changes
    if isempty(changedObjects)
        proposeRule!(cc.coderack, nothing, nothing, nothing, nothing)
        return
    end

    changed = changedObjects[end]
    # a list of distinguishing descriptions for the object: string position
    # (left-/right-most, middle or whole) or letter category if it is the only
    # one of its type in the string
    objectList = Slipnode[]
    position = getDescriptor(changed, slipnet.stringPositionCategory)
    position === nothing || push!(objectList, position::Slipnode)
    letter = getDescriptor(changed, slipnet.letterCategory)::Slipnode
    # NB: the Python original writes `if not o != changed`, i.e. `o == changed`,
    # so this only ever inspects the changed object itself. Preserved as-is.
    otherObjectsOfSameLetter = WSObject[o for o in workspace.initial.objects
                                        if o === changed &&
                                           getDescriptionType(o, letter) !== nothing]
    if isempty(otherObjectsOfSameLetter)
        push!(objectList, letter)
    end
    # if this object corresponds to another object in the workspace, objectList
    # = the union of this and the distinguishing descriptors
    if changed.correspondence !== nothing
        targetObject = (changed.correspondence::Correspondence).objectFromTarget
        newList = Slipnode[]
        slips = slippages(workspace)
        for node in objectList
            n = applySlippages(node, slips)
            if described(targetObject, n) && distinguishingDescriptor(targetObject, n)
                push!(newList, n)
            end
        end
        objectList = newList
    end
    isempty(objectList) && return
    # use conceptual depth to choose a description
    weights = Float64[getAdjustedValue(temperature, n.conceptualDepth) for n in objectList]
    descriptor = weighted_choice(random, objectList, weights)::Slipnode
    # choose the relation (change the leftmost object to "successor" or "d")
    objectList = Slipnode[]
    replacement = changed.replacement::Replacement
    if replacement.relation !== nothing
        push!(objectList, replacement.relation::Slipnode)
    end
    push!(objectList, getDescriptor(replacement.objectFromModified, slipnet.letterCategory)::Slipnode)
    weights = Float64[getAdjustedValue(temperature, n.conceptualDepth) for n in objectList]
    relation = weighted_choice(random, objectList, weights)::Slipnode
    proposeRule!(cc.coderack, slipnet.letterCategory, descriptor, slipnet.letter, relation)
end

function rule_strength_tester(ctx, codelet)
    cc = ctx::Copycat
    rule = codelet.arguments[1]::Rule
    updateStrength!(rule)
    if coinFlip(cc.random, getAdjustedProbability(cc.temperature, rule.totalStrength / 100.0))
        newCodelet!(cc.coderack, "rule-builder", rule.totalStrength, Any[rule])
    end
end

function replacement_finder(ctx, codelet)
    cc = ctx::Copycat
    random = cc.random
    slipnet = cc.slipnet
    workspace = cc.workspace
    # choose random letter in initial string
    letters = WSObject[o for o in workspace.initial.objects if o isa Letter]
    isempty(letters) && return
    letterOfInitialString = choice(random, letters)
    letterOfInitialString.replacement === nothing || return
    position = letterOfInitialString.leftIndex
    letterOfModifiedString = nothing
    for o in workspace.modified.objects
        if o isa Letter && o.leftIndex == position
            letterOfModifiedString = o
            break
        end
    end
    letterOfModifiedString === nothing && return
    initialAscii = Int(workspace.initialString[position])
    modifiedAscii = Int(workspace.modifiedString[position])
    diff = initialAscii - modifiedAscii
    relation = if diff == 0
        slipnet.sameness
    elseif diff == -1
        slipnet.successor
    elseif diff == 1
        slipnet.predecessor
    else
        nothing
    end
    letterOfInitialString.replacement =
        Replacement(ctx, letterOfInitialString, letterOfModifiedString::WSObject, relation)
    if relation !== slipnet.sameness
        letterOfInitialString.changed = true
        workspace.changedObject = letterOfInitialString
    end
end

function top_down_bond_scout__category(ctx, codelet)
    cc = ctx::Copycat
    slipnet = cc.slipnet
    category = codelet.arguments[1]::Slipnode
    source = getScoutSource(ctx, category, localBondCategoryRelevance, "bond")
    source === nothing && return
    destination = chooseNeighbor(ctx, source::WSObject)
    destination === nothing && return
    bondFacet = chooseBondFacet(ctx, source::WSObject, destination::WSObject)
    bondFacet === nothing && return
    descriptors = getDescriptors(bondFacet::Slipnode, source::WSObject, destination::WSObject)
    descriptors === nothing && return
    sourceDescriptor, destinationDescriptor = descriptors
    forwardBond = getBondCategory(sourceDescriptor, destinationDescriptor)
    if forwardBond === slipnet.identity
        forwardBond = slipnet.sameness
        backwardBond = slipnet.sameness
    else
        backwardBond = getBondCategory(destinationDescriptor, sourceDescriptor)
    end
    (category === forwardBond || category === backwardBond) || return
    if category === forwardBond
        proposeBond!(cc.coderack, source::WSObject, destination::WSObject, category,
                     bondFacet::Slipnode, sourceDescriptor, destinationDescriptor)
    else
        proposeBond!(cc.coderack, destination::WSObject, source::WSObject, category,
                     bondFacet::Slipnode, destinationDescriptor, sourceDescriptor)
    end
end

function top_down_bond_scout__direction(ctx, codelet)
    cc = ctx::Copycat
    slipnet = cc.slipnet
    direction = codelet.arguments[1]::Slipnode
    source = getScoutSource(ctx, direction, localDirectionCategoryRelevance, "bond")
    source === nothing && return
    destination = chooseDirectedNeighbor(ctx, source::WSObject, direction)
    destination === nothing && return
    bondFacet = chooseBondFacet(ctx, source::WSObject, destination::WSObject)
    bondFacet === nothing && return
    descriptors = getDescriptors(bondFacet::Slipnode, source::WSObject, destination::WSObject)
    descriptors === nothing && return
    sourceDescriptor, destinationDescriptor = descriptors
    category = getBondCategory(sourceDescriptor, destinationDescriptor)
    category === nothing && return
    if category === slipnet.identity
        category = slipnet.sameness
    end
    proposeBond!(cc.coderack, source::WSObject, destination::WSObject, category::Slipnode,
                 bondFacet::Slipnode, sourceDescriptor, destinationDescriptor)
end

function bond_strength_tester(ctx, codelet)
    cc = ctx::Copycat
    bond = codelet.arguments[1]::Bond
    updateStrength!(bond)
    strength = bond.totalStrength
    coinFlip(cc.random, getAdjustedProbability(cc.temperature, strength / 100.0)) || return
    bond.facet.buffer = 100.0
    bond.sourceDescriptor.buffer = 100.0
    bond.destinationDescriptor.buffer = 100.0
    newCodelet!(cc.coderack, "bond-builder", strength, Any[bond])
end

function bond_builder(ctx, codelet)
    cc = ctx::Copycat
    workspace = cc.workspace
    bond = codelet.arguments[1]::Bond
    updateStrength!(bond)
    (contains_identical(workspace.objects, bond.source) ||
     contains_identical(workspace.objects, bond.destination)) || return
    for x in bond.string.bonds
        stringBond = x::Bond
        if sameNeighbors(bond, stringBond) && sameCategories(bond, stringBond)
            if bond.directionCategory !== nothing
                (bond.directionCategory::Slipnode).buffer = 100.0
            end
            bond.category.buffer = 100.0
            return   # already exists: activate descriptors & fizzle
        end
    end
    incompatibleBonds = getIncompatibleBonds(bond)
    fightIncompatibles(incompatibleBonds, bond, "bonds", 1.0, 1.0) || return
    incompatibleGroups = getCommonGroups(bond.source, bond.destination)
    fightIncompatibles(incompatibleGroups, bond, "groups", 1.0, 1.0) || return
    # fight all incompatible correspondences
    incompatibleCorrespondences = Correspondence[]
    if bond.leftObject.leftmost || bond.rightObject.rightmost
        if bond.directionCategory !== nothing
            incompatibleCorrespondences = getIncompatibleCorrespondences(bond)
            if !isempty(incompatibleCorrespondences)
                fight(bond, 2.0, incompatibleCorrespondences, 3.0) || return
            end
        end
    end
    for incompatible in incompatibleBonds
        break_the_structure!(incompatible)
    end
    for incompatible in incompatibleGroups
        break_the_structure!(incompatible)
    end
    for incompatible in incompatibleCorrespondences
        break_the_structure!(incompatible)
    end
    buildBond!(bond)
end

function top_down_group_scout__category(ctx, codelet)
    cc = ctx::Copycat
    random = cc.random
    slipnet = cc.slipnet
    groupCategory = codelet.arguments[1]::Slipnode
    category = getRelatedNode(groupCategory, slipnet.bondCategory)
    category === nothing && return
    src = getScoutSource(ctx, category::Slipnode, localBondCategoryRelevance, "group")
    src === nothing && return
    source = src::WSObject
    spansString(source) && return
    direction = if source.leftmost
        slipnet.right
    elseif source.rightmost
        slipnet.left
    else
        weighted_choice(random, Slipnode[slipnet.left, slipnet.right],
                        Float64[slipnet.left.activation, slipnet.right.activation])::Slipnode
    end
    firstBond = direction === slipnet.left ? source.leftBond : source.rightBond
    if firstBond === nothing || (firstBond::Bond).category !== category
        # check the other side of the object
        firstBond = direction === slipnet.right ? source.leftBond : source.rightBond
        if firstBond === nothing || (firstBond::Bond).category !== category
            if category === slipnet.sameness && source isa Letter
                group = Group(source.string, slipnet.samenessGroup, nothing,
                              slipnet.letterCategory, WSObject[source], Bond[])
                if coinFlip(random, singleLetterGroupProbability(group))
                    proposeSingleLetterGroup!(cc.coderack, source)
                end
            end
        end
        # NB: this `return` is at the outer level in the Python original, so a
        # failed first check always ends the codelet even when the other side
        # of the object does carry a bond of the right category.
        return
    end
    directionCat = (firstBond::Bond).directionCategory
    bondFacet = nothing
    # find leftmost object in group with these bonds
    search = true
    while search
        search = false
        source.leftBond === nothing && continue
        lb = source.leftBond::Bond
        lb.category === category || continue
        if lb.directionCategory !== directionCat && lb.directionCategory !== nothing
            continue
        end
        if bondFacet === nothing || bondFacet === lb.facet
            bondFacet = lb.facet
            directionCat = lb.directionCategory
            source = lb.leftObject
            search = true
        end
    end
    # find rightmost object in group with these bonds
    search = true
    destination = source
    while search
        search = false
        destination.rightBond === nothing && continue
        rb = destination.rightBond::Bond
        rb.category === category || continue
        if rb.directionCategory !== directionCat && rb.directionCategory !== nothing
            continue
        end
        if bondFacet === nothing || bondFacet === rb.facet
            bondFacet = rb.facet
            # NB: the Python original reads `source.rightBond` here, not
            # `destination.rightBond`. Preserved as-is.
            source.rightBond === nothing && return
            directionCat = (source.rightBond::Bond).directionCategory
            destination = rb.rightObject
            search = true
        end
    end
    destination === source && return
    objects = WSObject[source]
    bonds = Bond[]
    while source !== destination
        rb = source.rightBond::Bond
        push!(bonds, rb)
        push!(objects, rb.rightObject)
        source = rb.rightObject
    end
    proposeGroup!(cc.coderack, objects, bonds, groupCategory, directionCat,
                  bondFacet::Slipnode)
end

function top_down_group_scout__direction(ctx, codelet)
    cc = ctx::Copycat
    random = cc.random
    slipnet = cc.slipnet
    direction = codelet.arguments[1]::Union{Nothing,Slipnode}
    src = getScoutSource(ctx, direction::Slipnode, localDirectionCategoryRelevance, "direction")
    src === nothing && return
    source = src::WSObject
    spansString(source) && return
    mydirection = if source.leftmost
        slipnet.right
    elseif source.rightmost
        slipnet.left
    else
        weighted_choice(random, Slipnode[slipnet.left, slipnet.right],
                        Float64[slipnet.left.activation, slipnet.right.activation])::Slipnode
    end
    firstBond = mydirection === slipnet.left ? source.leftBond : source.rightBond
    if firstBond !== nothing && (firstBond::Bond).directionCategory === nothing
        direction = nothing
    end
    if firstBond === nothing || (firstBond::Bond).directionCategory !== direction
        firstBond = mydirection === slipnet.right ? source.leftBond : source.rightBond
        if firstBond !== nothing && (firstBond::Bond).directionCategory === nothing
            direction = nothing
        end
        (firstBond !== nothing && (firstBond::Bond).directionCategory === direction) || return
    end
    category = (firstBond::Bond).category
    groupCategory = getRelatedNode(category, slipnet.groupCategory)
    groupCategory === nothing && return
    bondFacet = nothing
    # find leftmost object in group with these bonds
    search = true
    while search
        search = false
        source.leftBond === nothing && continue
        lb = source.leftBond::Bond
        lb.category === category || continue
        if lb.directionCategory !== direction && lb.directionCategory !== nothing
            continue
        end
        if bondFacet === nothing || bondFacet === lb.facet
            bondFacet = lb.facet
            direction = lb.directionCategory
            source = lb.leftObject
            search = true
        end
    end
    destination = source
    search = true
    while search
        search = false
        destination.rightBond === nothing && continue
        rb = destination.rightBond::Bond
        rb.category === category || continue
        if rb.directionCategory !== direction && rb.directionCategory !== nothing
            continue
        end
        if bondFacet === nothing || bondFacet === rb.facet
            bondFacet = rb.facet
            # NB: `source.rightBond`, as in the Python original.
            source.rightBond === nothing && return
            direction = (source.rightBond::Bond).directionCategory
            destination = rb.rightObject
            search = true
        end
    end
    destination === source && return
    objects = WSObject[source]
    bonds = Bond[]
    while source !== destination
        rb = source.rightBond::Bond
        push!(bonds, rb)
        push!(objects, rb.rightObject)
        source = rb.rightObject
    end
    proposeGroup!(cc.coderack, objects, bonds, groupCategory::Slipnode, direction,
                  bondFacet::Slipnode)
end

function group_scout__whole_string(ctx, codelet)
    cc = ctx::Copycat
    random = cc.random
    slipnet = cc.slipnet
    workspace = cc.workspace
    string = choice(random, WorkspaceString[workspace.initial, workspace.target])
    # find leftmost object & the highest group to which it belongs
    leftmost = nothing
    for o in string.objects
        if o.leftmost
            leftmost = o
            break
        end
    end
    leftmost === nothing && return
    lm = leftmost::WSObject
    while lm.group !== nothing && (lm.group::Group).bondCategory === slipnet.sameness
        lm = lm.group::Group
    end
    if spansString(lm)
        # the object already spans the string - propose this object
        if lm isa Group
            g = lm::Group
            proposeGroup!(cc.coderack, g.objectList, g.bondList, g.groupCategory,
                          g.directionCategory, g.facet)
        else
            proposeSingleLetterGroup!(cc.coderack, lm)
        end
        return
    end
    bonds = Bond[]
    objects = WSObject[lm]
    while lm.rightBond !== nothing
        rb = lm.rightBond::Bond
        push!(bonds, rb)
        lm = rb.rightObject
        push!(objects, lm)
    end
    lm.rightmost || return
    isempty(bonds) && return
    chosenBond = choice(random, bonds)::Bond
    bonds = possibleGroupBonds(chosenBond, bonds)
    isempty(bonds) && return
    category = chosenBond.category
    groupCategory = getRelatedNode(category, slipnet.groupCategory)
    groupCategory === nothing && return
    proposeGroup!(cc.coderack, objects, bonds, groupCategory::Slipnode,
                  chosenBond.directionCategory, chosenBond.facet)
end

function group_strength_tester(ctx, codelet)
    cc = ctx::Copycat
    slipnet = cc.slipnet
    group = codelet.arguments[1]::Group
    updateStrength!(group)
    strength = group.totalStrength
    if coinFlip(cc.random, getAdjustedProbability(cc.temperature, strength / 100.0))
        # it is strong enough - post builder & activate nodes
        (getRelatedNode(group.groupCategory, slipnet.bondCategory)::Slipnode).buffer = 100.0
        if group.directionCategory !== nothing
            (group.directionCategory::Slipnode).buffer = 100.0
        end
        newCodelet!(cc.coderack, "group-builder", strength, Any[group])
    end
end

function group_builder(ctx, codelet)
    cc = ctx::Copycat
    slipnet = cc.slipnet
    workspace = cc.workspace
    group = codelet.arguments[1]::Group
    equivalent = equivalentGroup(group.string, group)
    if equivalent !== nothing
        # already exists: activate descriptors & fizzle
        activateDescriptions!(group)
        addDescriptions!(equivalent::Group, group.descriptions)
        return
    end
    # check to see if all objects are still there
    for o in group.objectList
        contains_identical(workspace.objects, o) || return
    end
    # check to see if bonds are there of the same direction
    incompatibleBonds = Bond[]
    if length(group.objectList) > 1
        # NB: in the Python original the `continue` statements skip the
        # `previous`/`next_object` update as well, so those cursors only
        # advance when the bond was recorded as incompatible or was absent.
        previous = group.objectList[1]
        for objekt in group.objectList[2:end]
            leftBond = objekt.leftBond
            if leftBond !== nothing
                lb = leftBond::Bond
                lb.leftObject === previous && continue
                lb.directionCategory === group.directionCategory && continue
                push!(incompatibleBonds, lb)
            end
            previous = objekt
        end
        next_object = group.objectList[end]
        for objekt in reverse(group.objectList[1:end-1])
            rightBond = objekt.rightBond
            if rightBond !== nothing
                rb = rightBond::Bond
                rb.rightObject === next_object && continue
                rb.directionCategory === group.directionCategory && continue
                push!(incompatibleBonds, rb)
            end
            next_object = objekt
        end
    end
    # if incompatible bonds exist - fight
    updateStrength!(group)
    fightIncompatibles(incompatibleBonds, group, "bonds", 1.0, 1.0) || return
    # fight all groups containing these objects
    incompatibleGroups = getIncompatibleGroups(group)
    fightIncompatibles(incompatibleGroups, group, "Groups", 1.0, 1.0) || return
    for incompatible in incompatibleBonds
        break_the_structure!(incompatible)
    end
    # create new bonds
    group.bondList = Bond[]
    for i in 2:length(group.objectList)
        object1 = group.objectList[i - 1]
        object2 = group.objectList[i]
        if object1.rightBond === nothing
            if group.directionCategory === slipnet.right
                source, destination = object1, object2
            else
                source, destination = object2, object1
            end
            category = getRelatedNode(group.groupCategory, slipnet.bondCategory)::Slipnode
            facet = group.facet
            newBond = Bond(ctx, source, destination, category, facet,
                           getDescriptor(source, facet)::Slipnode,
                           getDescriptor(destination, facet)::Slipnode)
            buildBond!(newBond)
        end
        push!(group.bondList, object1.rightBond::Bond)
    end
    for incompatible in incompatibleGroups
        break_the_structure!(incompatible)
    end
    buildGroup!(group)
    activateDescriptions!(group)
end

function rule_builder(ctx, codelet)
    cc = ctx::Copycat
    workspace = cc.workspace
    rule = codelet.arguments[1]::Rule
    if ruleEqual(rule, workspace.rule)
        activateRuleDescriptions!(rule)
        return
    end
    updateStrength!(rule)
    rule.totalStrength == 0 && return
    # fight against other rules
    if workspace.rule !== nothing
        structureVsStructure(rule, 1.0, workspace.rule::Rule, 1.0) || return
    end
    buildRule!(workspace, rule)
end

function getCutoffWeights(bondDensity)
    bondDensity > 0.8 && return Float64[5, 150, 5, 2, 1, 1, 1, 1, 1, 1]
    bondDensity > 0.6 && return Float64[2, 5, 150, 5, 2, 1, 1, 1, 1, 1]
    bondDensity > 0.4 && return Float64[1, 2, 5, 150, 5, 2, 1, 1, 1, 1]
    bondDensity > 0.2 && return Float64[1, 1, 2, 5, 150, 5, 2, 1, 1, 1]
    return Float64[1, 1, 1, 2, 5, 150, 5, 2, 1, 1]
end

function rule_translator(ctx, codelet)
    cc = ctx::Copycat
    workspace = cc.workspace
    workspace.rule === nothing && return
    if length(workspace.initial) + length(workspace.target) <= 2
        bondDensity = 1.0
    else
        numberOfBonds = length(workspace.initial.bonds) + length(workspace.target.bonds)
        nearlyTotalLength = length(workspace.initial) + length(workspace.target) - 2
        bondDensity = min(numberOfBonds / nearlyTotalLength, 1.0)
    end
    weights = getCutoffWeights(bondDensity)
    cutoff = 10.0 * weighted_choice(cc.random, collect(1:10), weights)::Int
    if cutoff >= cc.temperature.actual_value
        result = buildTranslatedRule(workspace.rule::Rule)
        if result !== nothing
            workspace.finalAnswer = result::String
        else
            clampUntil!(cc.temperature, cc.coderack.codeletsRun + 100)
        end
    end
end

"""Shared tail of the two correspondence scouts."""
function propose_correspondence_from(cc::Copycat, objectFromInitial::WSObject,
                                     objectFromTarget::WSObject)
    slipnet = cc.slipnet
    conceptMappings = getMappings(objectFromInitial, objectFromTarget,
                                  relevantDescriptions(objectFromInitial),
                                  relevantDescriptions(objectFromTarget))
    (!isempty(conceptMappings) && slippability(cc, conceptMappings)) || return
    # find out if any are distinguishing
    distinguishingMappings = ConceptMapping[m for m in conceptMappings if distinguishing(m)]
    isempty(distinguishingMappings) && return
    # if both objects span the strings, check whether the string description
    # needs to be flipped
    opposites = ConceptMapping[m for m in distinguishingMappings
                               if m.initialDescriptionType === slipnet.stringPositionCategory &&
                                  m.initialDescriptionType !== slipnet.bondFacet]
    flipTargetObject = false
    if spansString(objectFromInitial) && spansString(objectFromTarget) &&
       any(m -> m.initialDescriptionType === slipnet.directionCategory, opposites) &&
       all(m -> m.label === slipnet.opposite, opposites) &&
       slipnet.opposite.activation != 100.0
        objectFromTarget = flippedVersion(objectFromTarget::Group)
        conceptMappings = getMappings(objectFromInitial, objectFromTarget,
                                      relevantDescriptions(objectFromInitial),
                                      relevantDescriptions(objectFromTarget))
        flipTargetObject = true
    end
    proposeCorrespondence!(cc.coderack, objectFromInitial, objectFromTarget,
                           conceptMappings, flipTargetObject)
end

function bottom_up_correspondence_scout(ctx, codelet)
    cc = ctx::Copycat
    workspace = cc.workspace
    objectFromInitial = chooseUnmodifiedObject(ctx, :interStringSalience,
                                               workspace.initial.objects)
    objectFromInitial === nothing && return
    objectFromTarget = chooseUnmodifiedObject(ctx, :interStringSalience,
                                              workspace.target.objects)
    objectFromTarget === nothing && return
    spansString(objectFromInitial::WSObject) == spansString(objectFromTarget::WSObject) || return
    propose_correspondence_from(cc, objectFromInitial::WSObject, objectFromTarget::WSObject)
end

function important_object_correspondence_scout(ctx, codelet)
    cc = ctx::Copycat
    workspace = cc.workspace
    objectFromInitial = chooseUnmodifiedObject(ctx, :relativeImportance,
                                               workspace.initial.objects)
    objectFromInitial === nothing && return
    oi = objectFromInitial::WSObject
    descriptors = relevantDistinguishingDescriptors(oi)
    # choose descriptor by conceptual depth
    weights = Float64[getAdjustedValue(cc.temperature, n.conceptualDepth) for n in descriptors]
    slipnode = weighted_choice(cc.random, descriptors, weights)
    slipnode === nothing && return
    initialDescriptor = slipnode::Slipnode
    for mapping in slippages(workspace)
        if mapping.initialDescriptor === slipnode
            initialDescriptor = mapping.targetDescriptor
        end
    end
    targetCandidates = WSObject[]
    for objekt in workspace.target.objects
        for description in relevantDescriptions(objekt)
            if (description::Description).descriptor === initialDescriptor
                push!(targetCandidates, objekt)
            end
        end
    end
    isempty(targetCandidates) && return
    objectFromTarget = chooseUnmodifiedObject(ctx, :interStringSalience, targetCandidates)
    objectFromTarget === nothing && return
    spansString(oi) == spansString(objectFromTarget::WSObject) || return
    propose_correspondence_from(cc, oi, objectFromTarget::WSObject)
end

function correspondence_strength_tester(ctx, codelet)
    cc = ctx::Copycat
    workspace = cc.workspace
    correspondence = codelet.arguments[1]::Correspondence
    objectFromInitial = correspondence.objectFromInitial
    objectFromTarget = correspondence.objectFromTarget
    ok = contains_identical(workspace.objects, objectFromInitial) &&
         (contains_identical(workspace.objects, objectFromTarget) ||
          (correspondence.flipTargetObject &&
           equivalentGroup(workspace.target, flippedVersion(objectFromTarget::Group)) === nothing))
    ok || return
    updateStrength!(correspondence)
    strength = correspondence.totalStrength
    if coinFlip(cc.random, getAdjustedProbability(cc.temperature, strength / 100.0))
        # activate some concepts
        for mapping in correspondence.conceptMappings
            mapping.initialDescriptionType.buffer = 100.0
            mapping.initialDescriptor.buffer = 100.0
            mapping.targetDescriptionType.buffer = 100.0
            mapping.targetDescriptor.buffer = 100.0
        end
        newCodelet!(cc.coderack, "correspondence-builder", strength, Any[correspondence])
    end
end

function correspondence_builder(ctx, codelet)
    cc = ctx::Copycat
    workspace = cc.workspace
    correspondence = codelet.arguments[1]::Correspondence
    objectFromInitial = correspondence.objectFromInitial
    objectFromTarget = correspondence.objectFromTarget
    wantFlip = correspondence.flipTargetObject
    targetNotFlipped = false
    if wantFlip
        flipper = flippedVersion(objectFromTarget::Group)
        targetNotFlipped = equivalentGroup(workspace.target, flipper) === nothing
    end
    initialInObjects = contains_identical(workspace.objects, objectFromInitial)
    targetInObjects = contains_identical(workspace.objects, objectFromTarget)
    (initialInObjects || (!targetInObjects && !(wantFlip && targetNotFlipped))) || return
    if reflexive(correspondence)
        # if the correspondence exists, activate concept mappings and add new
        # ones to the existing correspondence
        existing = correspondence.objectFromInitial.correspondence::Correspondence
        for mapping in correspondence.conceptMappings
            if mapping.label !== nothing
                (mapping.label::Slipnode).buffer = 100.0
            end
            if !isContainedBy(mapping, existing.conceptMappings)
                push!(existing.conceptMappings, mapping)
            end
        end
        return
    end
    incompatibles = getIncompatibleCorrespondences(correspondence)
    # fight against all correspondences
    if !isempty(incompatibles)
        correspondenceSpans = letterSpan(correspondence.objectFromInitial) +
                              letterSpan(correspondence.objectFromTarget)
        for x in incompatibles
            incompatible = x::Correspondence
            incompatibleSpans = letterSpan(incompatible.objectFromInitial) +
                                letterSpan(incompatible.objectFromTarget)
            structureVsStructure(correspondence, correspondenceSpans,
                                 incompatible, incompatibleSpans) || return
        end
    end
    incompatibleBond = nothing
    incompatibleGroup = nothing
    # if there is an incompatible bond then fight against it
    initial = correspondence.objectFromInitial
    target = correspondence.objectFromTarget
    if initial.leftmost || (initial.rightmost && target.leftmost) || target.rightmost
        incompatibleBond = getIncompatibleBond(correspondence)
        if incompatibleBond !== nothing
            # bond found - fight against it
            structureVsStructure(correspondence, 3.0, incompatibleBond::Bond, 2.0) || return
            # won against incompatible bond
            incompatibleGroup = target.group
            if incompatibleGroup !== nothing
                structureVsStructure(correspondence, 1.0, incompatibleGroup::Group, 1.0) || return
            end
        end
    end
    # if there is an incompatible rule, fight against it
    incompatibleRule = nothing
    if workspace.rule !== nothing
        if incompatibleRuleCorrespondence(workspace.rule::Rule, correspondence)
            incompatibleRule = workspace.rule::Rule
            structureVsStructure(correspondence, 1.0, incompatibleRule::Rule, 1.0) || return
        end
    end
    for x in incompatibles
        break_the_structure!(x)
    end
    # break incompatible group and bond if they exist
    incompatibleBond === nothing || break_the_structure!(incompatibleBond::Bond)
    incompatibleGroup === nothing || break_the_structure!(incompatibleGroup::Group)
    incompatibleRule === nothing || breakRule!(workspace)
    buildCorrespondence!(correspondence)
end

const CODELET_NAMES = (
    "breaker", "bottom-up-description-scout", "top-down-description-scout",
    "description-strength-tester", "description-builder", "bottom-up-bond-scout",
    "top-down-bond-scout--category", "top-down-bond-scout--direction",
    "bond-strength-tester", "bond-builder", "top-down-group-scout--category",
    "top-down-group-scout--direction", "group-scout--whole-string",
    "group-strength-tester", "group-builder", "replacement-finder", "rule-scout",
    "rule-strength-tester", "rule-builder", "rule-translator",
    "bottom-up-correspondence-scout", "important-object-correspondence-scout",
    "correspondence-strength-tester", "correspondence-builder")

function dispatch_codelet(ctx::Copycat, codelet::Codelet)
    name = codelet.name
    if     name == "bottom-up-bond-scout";                  bottom_up_bond_scout(ctx, codelet)
    elseif name == "bond-strength-tester";                  bond_strength_tester(ctx, codelet)
    elseif name == "bond-builder";                          bond_builder(ctx, codelet)
    elseif name == "breaker";                               breaker(ctx, codelet)
    elseif name == "bottom-up-correspondence-scout";        bottom_up_correspondence_scout(ctx, codelet)
    elseif name == "important-object-correspondence-scout"; important_object_correspondence_scout(ctx, codelet)
    elseif name == "correspondence-strength-tester";        correspondence_strength_tester(ctx, codelet)
    elseif name == "correspondence-builder";                correspondence_builder(ctx, codelet)
    elseif name == "bottom-up-description-scout";           bottom_up_description_scout(ctx, codelet)
    elseif name == "top-down-description-scout";            top_down_description_scout(ctx, codelet)
    elseif name == "description-strength-tester";           description_strength_tester(ctx, codelet)
    elseif name == "description-builder";                   description_builder(ctx, codelet)
    elseif name == "top-down-bond-scout--category";         top_down_bond_scout__category(ctx, codelet)
    elseif name == "top-down-bond-scout--direction";        top_down_bond_scout__direction(ctx, codelet)
    elseif name == "top-down-group-scout--category";        top_down_group_scout__category(ctx, codelet)
    elseif name == "top-down-group-scout--direction";       top_down_group_scout__direction(ctx, codelet)
    elseif name == "group-scout--whole-string";             group_scout__whole_string(ctx, codelet)
    elseif name == "group-strength-tester";                 group_strength_tester(ctx, codelet)
    elseif name == "group-builder";                         group_builder(ctx, codelet)
    elseif name == "replacement-finder";                    replacement_finder(ctx, codelet)
    elseif name == "rule-scout";                            rule_scout(ctx, codelet)
    elseif name == "rule-strength-tester";                  rule_strength_tester(ctx, codelet)
    elseif name == "rule-builder";                          rule_builder(ctx, codelet)
    elseif name == "rule-translator";                       rule_translator(ctx, codelet)
    else   error("unknown codelet: $name")
    end
    return nothing
end
