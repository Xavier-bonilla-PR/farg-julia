# Mirrors copycat/rule.py.

Rule(ctx, facet, descriptor, category, relation) =
    Rule(ctx, 0.0, 0.0, 0.0, facet, descriptor, category, relation)

updateExternalStrength!(r::Rule) = (r.externalStrength = r.internalStrength)

function updateInternalStrength!(r::Rule)
    workspace = (r.ctx::Copycat).workspace
    if r.descriptor === nothing || r.relation === nothing
        r.internalStrength = 50.0
        return
    end
    descriptor = r.descriptor::Slipnode
    relation = r.relation::Slipnode
    averageDepth = (descriptor.conceptualDepth + relation.conceptualDepth) / 2.0
    averageDepth ^= 1.1
    # see if the object corresponds to an object; if so, see if the descriptor
    # is present (modulo slippages) in the corresponding object
    changedObjects = WSObject[o for o in workspace.initial.objects if o.changed]
    changed = changedObjects[1]
    sharedDescriptorTerm = 0.0
    if changed.correspondence !== nothing
        targetObject = (changed.correspondence::Correspondence).objectFromTarget
        slipnode = applySlippages(descriptor, slippages(workspace))
        if !described(targetObject, slipnode)
            r.internalStrength = 0.0
            return
        end
        sharedDescriptorTerm = 100.0
    end
    conceptual_height = (100.0 - descriptor.conceptualDepth) / 10.0
    sharedDescriptorWeight = conceptual_height^1.4
    depthDifference = 100.0 - abs(descriptor.conceptualDepth - relation.conceptualDepth)
    r.internalStrength = weightedAverage(((depthDifference, 12),
                                          (averageDepth, 18),
                                          (sharedDescriptorTerm, sharedDescriptorWeight)))
    if r.internalStrength > 100.0
        r.internalStrength = 100.0
    end
end

function ruleEqual(r::Rule, other)
    other === nothing && return false
    o = other::Rule
    r.relation === o.relation || return false
    r.facet === o.facet || return false
    r.category === o.category || return false
    return r.descriptor === o.descriptor
end

function activateRuleDescriptions!(r::Rule)
    r.relation === nothing || ((r.relation::Slipnode).buffer = 100.0)
    r.facet === nothing || ((r.facet::Slipnode).buffer = 100.0)
    r.category === nothing || ((r.category::Slipnode).buffer = 100.0)
    r.descriptor === nothing || ((r.descriptor::Slipnode).buffer = 100.0)
end

function incompatibleRuleCorrespondence(r::Rule, correspondence)
    workspace = (r.ctx::Copycat).workspace
    correspondence === nothing && return false
    c = correspondence::Correspondence
    changeds = WSObject[o for o in workspace.initial.objects if o.changed]
    isempty(changeds) && return false
    c.objectFromInitial === changeds[1] || return false
    # incompatible if the rule descriptor is not in the mapping list
    return any(m -> m.initialDescriptor === r.descriptor, c.conceptMappings)
end

"""Apply this rule's change to a substring, e.g. take its successor."""
function changeString(r::Rule, s::AbstractString)
    slipnet = (r.ctx::Copycat).slipnet
    if r.facet === slipnet.length
        r.relation === slipnet.predecessor && return s[1:end-1]
        # "Lengthening" is not really an operation on strings, only on groups,
        # but this mirrors the Python original.
        r.relation === slipnet.successor && return s * s[1:1]
        return s
    end
    if r.relation === slipnet.predecessor
        occursin('a', s) && return nothing
        return String([Char(Int(c) - 1) for c in s])
    elseif r.relation === slipnet.successor
        occursin('z', s) && return nothing
        return String([Char(Int(c) + 1) for c in s])
    else
        return lowercase((r.relation::Slipnode).name)
    end
end

function buildTranslatedRule(r::Rule)
    workspace = (r.ctx::Copycat).workspace
    if r.descriptor === nothing || r.relation === nothing
        return workspace.targetString
    end
    slips = slippages(workspace)
    r.category = applySlippages(r.category::Slipnode, slips)
    r.facet = applySlippages(r.facet::Slipnode, slips)
    r.descriptor = applySlippages(r.descriptor::Slipnode, slips)
    r.relation = applySlippages(r.relation::Slipnode, slips)
    # generate the final string
    changeds = WSObject[o for o in workspace.target.objects
                        if described(o, r.descriptor::Slipnode) &&
                           described(o, r.category::Slipnode)]
    isempty(changeds) && return workspace.targetString
    if length(changeds) > 1
        # More than one letter changed; can't solve problems like this yet.
        return nothing
    end
    changed = changeds[1]
    left = changed.leftIndex - 1
    right = changed.rightIndex
    s = workspace.targetString
    changed_middle = changeString(r, s[left+1:right])
    changed_middle === nothing && return nothing
    return s[1:left] * changed_middle * s[right+1:end]
end
