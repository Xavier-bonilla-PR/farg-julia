# Mirrors copycat/correspondence.py.

Correspondence(ctx, objectFromInitial, objectFromTarget, conceptMappings, flipTargetObject) =
    Correspondence(ctx, 0.0, 0.0, 0.0, objectFromInitial, objectFromTarget,
                   conceptMappings, flipTargetObject, ConceptMapping[])

distinguishingConceptMappings(c::Correspondence) =
    ConceptMapping[m for m in c.conceptMappings if distinguishing(m)]

relevantDistinguishingConceptMappings(c::Correspondence) =
    ConceptMapping[m for m in c.conceptMappings if distinguishing(m) && relevant(m)]

function extract_target_bond(c::Correspondence)
    c.objectFromTarget.leftmost && return c.objectFromTarget.rightBond
    c.objectFromTarget.rightmost && return c.objectFromTarget.leftBond
    return nothing
end

function extract_initial_bond(c::Correspondence)
    c.objectFromInitial.leftmost && return c.objectFromInitial.rightBond
    c.objectFromInitial.rightmost && return c.objectFromInitial.leftBond
    return nothing
end

function getIncompatibleBond(c::Correspondence)
    slipnet = (c.ctx::Copycat).slipnet
    initialBond = extract_initial_bond(c)
    initialBond === nothing && return nothing
    targetBond = extract_target_bond(c)
    targetBond === nothing && return nothing
    ib = initialBond::Bond
    tb = targetBond::Bond
    if ib.directionCategory !== nothing && tb.directionCategory !== nothing
        mapping = ConceptMapping(slipnet.directionCategory, slipnet.directionCategory,
                                 ib.directionCategory::Slipnode,
                                 tb.directionCategory::Slipnode, nothing, nothing)
        for m in c.conceptMappings
            incompatible(m, mapping) && return tb
        end
    end
    return nothing
end

function getIncompatibleCorrespondences(c::Correspondence)
    workspace = (c.ctx::Copycat).workspace
    result = Correspondence[]
    for o in workspace.initial.objects
        if corr_incompatible(c, o.correspondence)
            push!(result, o.correspondence::Correspondence)
        end
    end
    return result
end

corr_incompatible(c::Correspondence, ::Nothing) = false
function corr_incompatible(c::Correspondence, x::Correspondence)
    other = x::Correspondence
    c.objectFromInitial === other.objectFromInitial && return true
    c.objectFromTarget === other.objectFromTarget && return true
    for mapping in c.conceptMappings
        for otherMapping in other.conceptMappings
            incompatible(mapping, otherMapping) && return true
        end
    end
    return false
end

function supporting(c::Correspondence, other::Correspondence)
    c === other && return false
    c.objectFromInitial === other.objectFromInitial && return false
    c.objectFromTarget === other.objectFromTarget && return false
    corr_incompatible(c, other) && return false
    for mapping in distinguishingConceptMappings(c)
        for otherMapping in distinguishingConceptMappings(other)
            supports(mapping, otherMapping) && return true
        end
    end
    return false
end

function support(c::Correspondence)
    workspace = (c.ctx::Copycat).workspace
    if c.objectFromInitial isa Letter && spansString(c.objectFromInitial)
        return 100.0
    end
    if c.objectFromTarget isa Letter && spansString(c.objectFromTarget)
        return 100.0
    end
    total = 0.0
    for x in workspace.structures
        if x isa Correspondence && supporting(c, x::Correspondence)
            total += (x::Correspondence).totalStrength
        end
    end
    return min(total, 100.0)
end

"""A function of how many concept mappings there are, their strength and how
well they cohere."""
function updateInternalStrength!(c::Correspondence)
    distinguishingMappings = relevantDistinguishingConceptMappings(c)
    numberOfConceptMappings = length(distinguishingMappings)
    if numberOfConceptMappings < 1
        c.internalStrength = 0.0
        return
    end
    totalStrength = 0.0
    for m in distinguishingMappings
        totalStrength += strength(m)
    end
    averageStrength = totalStrength / numberOfConceptMappings
    numberOfConceptMappingsFactor = numberOfConceptMappings == 1 ? 0.8 :
                                    (numberOfConceptMappings == 2 ? 1.2 : 1.6)
    internalCoherenceFactor = internallyCoherent(c) ? 2.5 : 1.0
    c.internalStrength = min(averageStrength * internalCoherenceFactor *
                             numberOfConceptMappingsFactor, 100.0)
end

updateExternalStrength!(c::Correspondence) = (c.externalStrength = support(c))

"""Whether any pair of distinguishing mappings support each other."""
function internallyCoherent(c::Correspondence)
    mappings = relevantDistinguishingConceptMappings(c)
    n = length(mappings)
    for i in 1:n, j in 1:n
        if i != j && supports(mappings[i], mappings[j])
            return true
        end
    end
    return false
end

function slippages(c::Correspondence)
    mappings = ConceptMapping[m for m in c.conceptMappings if slippage(m)]
    append!(mappings, ConceptMapping[m for m in c.accessoryConceptMappings if slippage(m)])
    return mappings
end

function reflexive(c::Correspondence)
    initial = c.objectFromInitial
    initial.correspondence === nothing && return false
    return (initial.correspondence::Correspondence).objectFromTarget === c.objectFromTarget
end

function buildCorrespondence!(c::Correspondence)
    workspace = (c.ctx::Copycat).workspace
    push!(workspace.structures, c)
    if c.objectFromInitial.correspondence !== nothing
        breakCorrespondence!(c.objectFromInitial.correspondence::Correspondence)
    end
    if c.objectFromTarget.correspondence !== nothing
        breakCorrespondence!(c.objectFromTarget.correspondence::Correspondence)
    end
    c.objectFromInitial.correspondence = c
    c.objectFromTarget.correspondence = c
    # add mappings to accessory-concept-mapping-list
    for mapping in relevantDistinguishingConceptMappings(c)
        if slippage(mapping)
            push!(c.accessoryConceptMappings, symmetricVersion(mapping))
        end
    end
    if c.objectFromInitial isa Group && c.objectFromTarget isa Group
        bondMappings = getMappings(c.objectFromInitial, c.objectFromTarget,
                                   (c.objectFromInitial::Group).bondDescriptions,
                                   (c.objectFromTarget::Group).bondDescriptions)
        for mapping in bondMappings
            push!(c.accessoryConceptMappings, mapping)
            if slippage(mapping)
                push!(c.accessoryConceptMappings, symmetricVersion(mapping))
            end
        end
    end
    for mapping in c.conceptMappings
        if mapping.label !== nothing
            (mapping.label::Slipnode).activation = 100.0
        end
    end
end

break_the_structure!(c::Correspondence) = breakCorrespondence!(c)

function breakCorrespondence!(c::Correspondence)
    workspace = (c.ctx::Copycat).workspace
    remove_first!(workspace.structures, c)
    c.objectFromInitial.correspondence = nothing
    c.objectFromTarget.correspondence = nothing
end
