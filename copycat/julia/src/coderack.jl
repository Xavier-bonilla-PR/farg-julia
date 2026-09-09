# Mirrors copycat/coderack.py and codelet.py.

const NUMBER_OF_BINS = 7

function getUrgencyBin(urgency::Real)
    # Python's `int(urgency) * NUMBER_OF_BINS / 100` is float division, so the
    # result is a float and urgencies are not integers.
    i = trunc(Int, urgency) * NUMBER_OF_BINS / 100
    i >= NUMBER_OF_BINS && return Float64(NUMBER_OF_BINS)
    return i + 1
end

function reset!(c::Coderack)
    c.codelets = Codelet[]
    c.codeletsRun = 0
end

function updateCodelets!(c::Coderack)
    if c.codeletsRun > 0
        postTopDownCodelets!(c)
        postBottomUpCodelets!(c)
    end
end

function probabilityOfPosting(c::Coderack, codeletName::String)
    ctx = c.ctx::Copycat
    temperature = ctx.temperature
    workspace = ctx.workspace
    codeletName == "breaker" && return 1.0
    if occursin("replacement", codeletName)
        return numberOfUnreplacedObjects(workspace) > 0 ? 1.0 : 0.0
    end
    if occursin("rule", codeletName)
        workspace.rule === nothing && return 1.0
        return totalWeakness(workspace.rule::Rule) / 100.0
    end
    occursin("correspondence", codeletName) && return workspace.interStringUnhappiness / 100.0
    occursin("description", codeletName) && return (value(temperature) / 100.0)^2
    return workspace.intraStringUnhappiness / 100.0
end

function howManyToPost(c::Coderack, codeletName::String)
    ctx = c.ctx::Copycat
    random = ctx.random
    workspace = ctx.workspace
    (codeletName == "breaker" || occursin("description", codeletName)) && return 1
    if occursin("translator", codeletName)
        return workspace.rule === nothing ? 0 : 1
    end
    occursin("rule", codeletName) && return 2
    occursin("group", codeletName) && numberOfBonds(workspace) == 0 && return 0
    occursin("replacement", codeletName) && workspace.rule !== nothing && return 0
    number = 0
    occursin("bond", codeletName) && (number = numberOfUnrelatedObjects(workspace))
    occursin("group", codeletName) && (number = numberOfUngroupedObjects(workspace))
    occursin("replacement", codeletName) && (number = numberOfUnreplacedObjects(workspace))
    occursin("correspondence", codeletName) && (number = numberOfUncorrespondingObjects(workspace))
    number < sqrtBlur(random, 2.0) && return 1
    number < sqrtBlur(random, 4.0) && return 2
    return 3
end

function post!(c::Coderack, codelet::Codelet)
    push!(c.codelets, codelet)
    if length(c.codelets) > 100
        removeCodelet!(c, chooseOldCodelet(c))
    end
end

function postTopDownCodelets!(c::Coderack)
    ctx = c.ctx::Copycat
    random = ctx.random
    for node in ctx.slipnet.slipnodes
        node.activation != 100.0 && continue
        for codeletName in node.codelets
            probability = probabilityOfPosting(c, codeletName)
            howMany = howManyToPost(c, codeletName)
            for _ in 1:howMany
                coinFlip(random, probability) || continue
                urgency = getUrgencyBin(node.activation * node.conceptualDepth / 100.0)
                post!(c, Codelet(codeletName, urgency, Any[node], c.codeletsRun))
            end
        end
    end
end

function postBottomUpCodelets!(c::Coderack)
    for name in ("bottom-up-description-scout", "bottom-up-bond-scout",
                 "group-scout--whole-string", "bottom-up-correspondence-scout",
                 "important-object-correspondence-scout", "replacement-finder",
                 "rule-scout", "rule-translator", "breaker")
        postBottomUpCodelet!(c, name)
    end
end

function postBottomUpCodelet!(c::Coderack, codeletName::String)
    ctx = c.ctx::Copycat
    random = ctx.random
    temperature = ctx.temperature
    probability = probabilityOfPosting(c, codeletName)
    howMany = howManyToPost(c, codeletName)
    urgency = codeletName == "breaker" ? 1.0 : 3.0
    if value(temperature) < 25.0 && occursin("translator", codeletName)
        urgency = 5.0
    end
    for _ in 1:howMany
        if coinFlip(random, probability)
            post!(c, Codelet(codeletName, urgency, Any[], c.codeletsRun))
        end
    end
end

removeCodelet!(c::Coderack, codelet) = remove_first!(c.codelets, codelet)

function newCodelet!(c::Coderack, name::String, strength::Real, arguments::Vector{Any})
    post!(c, Codelet(name, getUrgencyBin(strength), arguments, c.codeletsRun))
end

"""Create a proposed rule and post a rule-strength-tester codelet whose urgency
is a function of the conceptual depth of the rule's descriptions."""
function proposeRule!(c::Coderack, facet, description, category, relation)
    rule = Rule(c.ctx, facet, description, category, relation)
    updateStrength!(rule)
    if description !== nothing && relation !== nothing
        averageDepth = ((description::Slipnode).conceptualDepth +
                        (relation::Slipnode).conceptualDepth) / 2.0
        urgency = 100.0 * sqrt(averageDepth / 100.0)
    else
        urgency = 0.0
    end
    newCodelet!(c, "rule-strength-tester", urgency, Any[rule])
end

function proposeCorrespondence!(c::Coderack, initialObject, targetObject,
                                conceptMappings, flipTargetObject)
    correspondence = Correspondence(c.ctx, initialObject, targetObject,
                                    conceptMappings, flipTargetObject)
    for mapping in conceptMappings
        mapping.initialDescriptionType.buffer = 100.0
        mapping.initialDescriptor.buffer = 100.0
        mapping.targetDescriptionType.buffer = 100.0
        mapping.targetDescriptor.buffer = 100.0
    end
    mappings = distinguishingConceptMappings(correspondence)
    urgency = 0.0
    for mapping in mappings
        urgency += strength(mapping)
    end
    if urgency != 0
        urgency /= length(mappings)
    end
    newCodelet!(c, "correspondence-strength-tester", urgency, Any[correspondence])
end

function proposeDescription!(c::Coderack, objekt, type_::Slipnode, descriptor::Slipnode)
    description = Description(c.ctx, objekt.string, 0.0, 0.0, 0.0, objekt, type_, descriptor)
    descriptor.buffer = 100.0
    newCodelet!(c, "description-strength-tester", type_.activation, Any[description])
end

function proposeSingleLetterGroup!(c::Coderack, source::WSObject)
    slipnet = (c.ctx::Copycat).slipnet
    proposeGroup!(c, WSObject[source], Bond[], slipnet.samenessGroup, nothing,
                  slipnet.letterCategory)
end

function proposeGroup!(c::Coderack, objects::Vector{WSObject}, bondList::Vector{Bond},
                       groupCategory::Slipnode, directionCategory, bondFacet::Slipnode)
    slipnet = (c.ctx::Copycat).slipnet
    bondCategory = getRelatedNode(groupCategory, slipnet.bondCategory)::Slipnode
    bondCategory.buffer = 100.0
    if directionCategory !== nothing
        (directionCategory::Slipnode).buffer = 100.0
    end
    group = Group(objects[1].string, groupCategory, directionCategory, bondFacet,
                  objects, bondList)
    newCodelet!(c, "group-strength-tester", bondDegreeOfAssociation(bondCategory), Any[group])
end

function proposeBond!(c::Coderack, source::WSObject, destination::WSObject,
                      bondCategory::Slipnode, bondFacet::Slipnode,
                      sourceDescriptor::Slipnode, destinationDescriptor::Slipnode)
    bondFacet.buffer = 100.0
    sourceDescriptor.buffer = 100.0
    destinationDescriptor.buffer = 100.0
    bond = Bond(c.ctx, source, destination, bondCategory, bondFacet,
                sourceDescriptor, destinationDescriptor)
    newCodelet!(c, "bond-strength-tester", bondDegreeOfAssociation(bondCategory), Any[bond])
end

"""Select an old codelet to remove; lower-urgency codelets are likelier."""
function chooseOldCodelet(c::Coderack)
    urgencies = Float64[(c.codeletsRun - codelet.birthdate) * (7.5 - codelet.urgency)
                        for codelet in c.codelets]
    return weighted_choice((c.ctx::Copycat).random, c.codelets, urgencies)
end

function postInitialCodelets!(c::Coderack)
    workspace = (c.ctx::Copycat).workspace
    n = length(workspace.objects)
    if n == 0
        # The most pathological case.
        post!(c, Codelet("rule-scout", 1.0, Any[], c.codeletsRun))
    else
        for name in ("bottom-up-bond-scout", "replacement-finder",
                     "bottom-up-correspondence-scout")
            for _ in 1:(2 * n)
                post!(c, Codelet(name, 1.0, Any[], c.codeletsRun))
            end
        end
    end
end

function chooseAndRunCodelet!(c::Coderack)
    if isempty(c.codelets)
        # Indeed, this happens fairly often.
        postInitialCodelets!(c)
    end
    run_codelet!(c, chooseCodeletToRun!(c))
end

function chooseCodeletToRun!(c::Coderack)
    ctx = c.ctx::Copycat
    scale = (100.0 - value(ctx.temperature) + 10.0) / 15.0
    weights = Float64[codelet.urgency^scale for codelet in c.codelets]
    chosen = weighted_choice(ctx.random, c.codelets, weights)::Codelet
    removeCodelet!(c, chosen)
    return chosen
end

function run_codelet!(c::Coderack, codelet::Codelet)
    c.codeletsRun += 1
    dispatch_codelet(c.ctx::Copycat, codelet)
end
