# Mirrors copycat/workspace.py and workspaceFormulas.py.

function resetWithStrings!(w::Workspace, initial, modified, target)
    w.targetString = String(target)
    w.initialString = String(initial)
    w.modifiedString = String(modified)
    reset!(w)
end

function reset!(w::Workspace)
    w.finalAnswer = nothing
    w.changedObject = nothing
    w.objects = WSObj[]
    w.structures = WSStructure[]
    w.rule = nothing
    ctx = w.ctx
    w.initial = build_string!(ctx, w.initialString)
    w.modified = build_string!(ctx, w.modifiedString)
    w.target = build_string!(ctx, w.targetString)
    return w
end

function calculateIntraStringUnhappiness!(w::Workspace)
    total = 0.0
    for o in w.objects
        total += o.relativeImportance * o.intraStringUnhappiness
    end
    w.intraStringUnhappiness = min(total / 2.0, 100.0)
end

function calculateInterStringUnhappiness!(w::Workspace)
    total = 0.0
    for o in w.objects
        total += o.relativeImportance * o.interStringUnhappiness
    end
    w.interStringUnhappiness = min(total / 2.0, 100.0)
end

function calculateTotalUnhappiness!(w::Workspace)
    total = 0.0
    for o in w.objects
        total += o.relativeImportance * o.totalUnhappiness
    end
    w.totalUnhappiness = min(total / 2.0, 100.0)
end

function updateEverything!(w::Workspace)
    for structure in w.structures
        updateStrength!(structure)
    end
    for obj in w.objects
        updateValue!(obj)
    end
    updateRelativeImportance!(w.initial)
    updateRelativeImportance!(w.target)
    updateIntraStringUnhappiness!(w.initial)
    updateIntraStringUnhappiness!(w.target)
end

"""Global tolerance towards irrelevance."""
function getUpdatedTemperature(w::Workspace)
    calculateIntraStringUnhappiness!(w)
    calculateInterStringUnhappiness!(w)
    calculateTotalUnhappiness!(w)
    if w.rule !== nothing
        rule = w.rule::Rule
        updateStrength!(rule)
        ruleWeakness = 100.0 - rule.totalStrength
    else
        ruleWeakness = 100.0
    end
    return weightedAverage(((w.totalUnhappiness, 0.8), (ruleWeakness, 0.2)))
end

"""Objects in the workspace with >= 1 open bond slots."""
function numberOfUnrelatedObjects(w::Workspace)
    count = 0
    for o in w.objects
        (o.string === w.initial || o.string === w.target) || continue
        spansString(o) && continue
        if (o.leftBond === nothing && !o.leftmost) || (o.rightBond === nothing && !o.rightmost)
            count += 1
        end
    end
    return count
end

"""Objects in the workspace that have no group."""
function numberOfUngroupedObjects(w::Workspace)
    count = 0
    for o in w.objects
        (o.string === w.initial || o.string === w.target) || continue
        spansString(o) && continue
        o.group === nothing && (count += 1)
    end
    return count
end

"""Unreplaced objects in the initial string."""
function numberOfUnreplacedObjects(w::Workspace)
    count = 0
    for o in w.objects
        if o.string === w.initial && o isa Letter && o.replacement === nothing
            count += 1
        end
    end
    return count
end

"""Uncorresponded objects in the initial and target strings."""
function numberOfUncorrespondingObjects(w::Workspace)
    count = 0
    for o in w.objects
        (o.string === w.initial || o.string === w.target) || continue
        o.correspondence === nothing && (count += 1)
    end
    return count
end

numberOfBonds(w::Workspace) = count(s -> s isa Bond, w.structures)

correspondences(w::Workspace) =
    Correspondence[s::Correspondence for s in w.structures if s isa Correspondence]

function slippages(w::Workspace)
    result = ConceptMapping[]
    if w.changedObject !== nothing
        co = w.changedObject::WSObject
        if co.correspondence !== nothing
            append!(result, (co.correspondence::Correspondence).conceptMappings)
        end
    end
    for o in w.initial.objects
        if o.correspondence !== nothing
            for mapping in slippages(o.correspondence::Correspondence)
                if !isNearlyContainedBy(mapping, result)
                    push!(result, mapping)
                end
            end
        end
    end
    return result
end

function buildRule!(w::Workspace, rule::Rule)
    if w.rule !== nothing
        remove_first!(w.structures, w.rule::Rule)
    end
    w.rule = rule
    push!(w.structures, rule)
    activateRuleDescriptions!(rule)
end

function breakRule!(w::Workspace)
    if w.rule !== nothing
        remove_first!(w.structures, w.rule::Rule)
    end
    w.rule = nothing
end

function buildDescriptions!(w::Workspace, objekt::WSObject)
    for d in objekt.descriptions
        description = d::Description
        description.descriptionType.buffer = 100.0
        description.descriptor.buffer = 100.0
        if !contains_identical(w.structures, description)
            push!(w.structures, description)
        end
    end
end

# --- workspaceFormulas -------------------------------------------------------

function chooseObjectFromList(ctx, objects::Vector{WSObject}, attribute::Symbol)
    cc = ctx::Copycat
    weights = Float64[getAdjustedValue(cc.temperature, getfield(o, attribute)) for o in objects]
    return weighted_choice(cc.random, objects, weights)
end

function chooseUnmodifiedObject(ctx, attribute::Symbol, inObjects)
    workspace = (ctx::Copycat).workspace
    objects = WSObject[o for o in inObjects if o.string !== workspace.modified]
    return chooseObjectFromList(ctx, objects, attribute)
end

function chooseNeighbor(ctx, source::WSObject)
    workspace = (ctx::Copycat).workspace
    objects = WSObject[o for o in workspace.objects if beside(o, source)]
    return chooseObjectFromList(ctx, objects, :intraStringSalience)
end

function chooseDirectedNeighbor(ctx, source::WSObject, direction::Slipnode)
    cc = ctx::Copycat
    workspace = cc.workspace
    objects = WSObject[]
    if direction === cc.slipnet.left
        for o in workspace.objects
            if o.string === source.string && source.leftIndex == o.rightIndex + 1
                push!(objects, o)
            end
        end
    else
        for o in workspace.objects
            if o.string === source.string && o.leftIndex == source.rightIndex + 1
                push!(objects, o)
            end
        end
    end
    return chooseObjectFromList(ctx, objects, :intraStringSalience)
end
