# Mirrors copycat/formulas.py.

function weightedAverage(values)
    total = 0.0
    totalWeights = 0.0
    for (value, weight) in values
        total += value * weight
        totalWeights += weight
    end
    totalWeights == 0 && return 0.0
    return total / totalWeights
end

function localRelevance(string::WorkspaceString, isRelevant::F) where {F}
    numberOfObjectsNotSpanning = 0.0
    numberOfMatches = 0.0
    for o in string.objects
        if !spansString(o)
            numberOfObjectsNotSpanning += 1.0
            if isRelevant(o)
                numberOfMatches += 1.0
            end
        end
    end
    numberOfObjectsNotSpanning == 1 && return 100.0 * numberOfMatches
    return 100.0 * numberOfMatches / (numberOfObjectsNotSpanning - 1.0)
end

function localBondCategoryRelevance(string::WorkspaceString, category::Slipnode)
    length(string.objects) == 1 && return 0.0
    return localRelevance(string, o -> begin
        rb = o.rightBond
        rb !== nothing && (rb::Bond).category === category
    end)
end

function localDirectionCategoryRelevance(string::WorkspaceString, direction::Slipnode)
    return localRelevance(string, o -> begin
        rb = o.rightBond
        rb !== nothing && (rb::Bond).directionCategory === direction
    end)
end

function getMappings(objectFromInitial, objectFromTarget,
                     initialDescriptions, targetDescriptions)
    mappings = ConceptMapping[]
    for initial in initialDescriptions
        for target in targetDescriptions
            if initial.descriptionType === target.descriptionType
                if initial.descriptor === target.descriptor ||
                   slipLinked(initial.descriptor, target.descriptor)
                    push!(mappings, ConceptMapping(
                        initial.descriptionType, target.descriptionType,
                        initial.descriptor, target.descriptor,
                        objectFromInitial, objectFromTarget))
                end
            end
        end
    end
    return mappings
end
