# All struct definitions live here because Julia needs a type to be defined
# before it is referenced. Where the Python object graph is genuinely cyclic
# (a Letter points at its Bond, a Bond points back at its Letter) the field is
# typed with an abstract supertype that has exactly one concrete subtype; the
# methods recover the concrete type with a cheap `::T` assertion.

abstract type AbstractCtx end
abstract type AbstractSlipnet end
abstract type AbstractSliplink end

mutable struct Slipnode
    slipnet::AbstractSlipnet
    name::String
    conceptualDepth::Float64
    intrinsicLinkLength::Float64
    shrunkLinkLength::Float64
    activation::Float64
    oldActivation::Float64
    buffer::Float64
    clamped::Bool
    categoryLinks::Vector{AbstractSliplink}
    instanceLinks::Vector{AbstractSliplink}
    propertyLinks::Vector{AbstractSliplink}
    lateralSlipLinks::Vector{AbstractSliplink}
    lateralNonSlipLinks::Vector{AbstractSliplink}
    incomingLinks::Vector{AbstractSliplink}
    outgoingLinks::Vector{AbstractSliplink}
    codelets::Vector{String}
end

mutable struct Sliplink <: AbstractSliplink
    source::Slipnode
    destination::Slipnode
    label::Union{Nothing,Slipnode}
    fixedLength::Float64
end

mutable struct Slipnet <: AbstractSlipnet
    slipnodes::Vector{Slipnode}
    sliplinks::Vector{Sliplink}
    letters::Vector{Slipnode}
    numbers::Vector{Slipnode}
    initiallyClampedSlipnodes::Vector{Slipnode}
    numberOfUpdates::Int
    # named nodes
    leftmost::Slipnode
    rightmost::Slipnode
    middle::Slipnode
    single::Slipnode
    whole::Slipnode
    first::Slipnode
    last::Slipnode
    left::Slipnode
    right::Slipnode
    predecessor::Slipnode
    successor::Slipnode
    sameness::Slipnode
    predecessorGroup::Slipnode
    successorGroup::Slipnode
    samenessGroup::Slipnode
    identity::Slipnode
    opposite::Slipnode
    letter::Slipnode
    group::Slipnode
    letterCategory::Slipnode
    stringPositionCategory::Slipnode
    alphabeticPositionCategory::Slipnode
    directionCategory::Slipnode
    bondCategory::Slipnode
    groupCategory::Slipnode
    length::Slipnode
    objectCategory::Slipnode
    bondFacet::Slipnode

    Slipnet() = new(Slipnode[], Sliplink[], Slipnode[], Slipnode[], Slipnode[], 0)
end

# --- workspace ---------------------------------------------------------------

abstract type WSStructure end
abstract type WSObject <: WSStructure end
# Only WorkspaceString <-> Bond is a genuine definition cycle, so that is the
# one field left with an abstract element type; everything else below is
# declared concretely, which matters because these vectors are iterated in the
# hottest loops (Description.localSupport, Bond.localDensity).
abstract type AbstractBond <: WSStructure end

mutable struct WorkspaceString
    ctx::AbstractCtx
    string::String
    bonds::Vector{AbstractBond}
    objects::Vector{WSObject}
    letters::Vector{WSObject}
    length::Int
    intraStringUnhappiness::Float64

    WorkspaceString(ctx, s::AbstractString) =
        new(ctx, String(s), Bond[], WSObject[], WSObject[], length(s), 0.0)
end

mutable struct Description <: WSStructure
    ctx::AbstractCtx
    string::WorkspaceString
    internalStrength::Float64
    externalStrength::Float64
    totalStrength::Float64
    object::WSObject
    descriptionType::Slipnode
    descriptor::Slipnode
end

mutable struct Bond <: AbstractBond
    ctx::AbstractCtx
    string::WorkspaceString
    internalStrength::Float64
    externalStrength::Float64
    totalStrength::Float64
    source::WSObject
    destination::WSObject
    leftObject::WSObject
    rightObject::WSObject
    directionCategory::Union{Nothing,Slipnode}
    facet::Slipnode
    sourceDescriptor::Slipnode
    destinationDescriptor::Slipnode
    category::Slipnode
end

mutable struct ConceptMapping
    slipnet::Slipnet
    initialDescriptionType::Slipnode
    targetDescriptionType::Slipnode
    initialDescriptor::Slipnode
    targetDescriptor::Slipnode
    initialObject::Union{Nothing,WSObject}
    targetObject::Union{Nothing,WSObject}
    label::Union{Nothing,Slipnode}
end

mutable struct Correspondence <: WSStructure
    ctx::AbstractCtx
    internalStrength::Float64
    externalStrength::Float64
    totalStrength::Float64
    objectFromInitial::WSObject
    objectFromTarget::WSObject
    conceptMappings::Vector{ConceptMapping}
    flipTargetObject::Bool
    accessoryConceptMappings::Vector{ConceptMapping}
end

mutable struct Replacement <: WSStructure
    ctx::AbstractCtx
    internalStrength::Float64
    externalStrength::Float64
    totalStrength::Float64
    objectFromInitial::WSObject
    objectFromModified::WSObject
    relation::Union{Nothing,Slipnode}
end

mutable struct Rule <: WSStructure
    ctx::AbstractCtx
    internalStrength::Float64
    externalStrength::Float64
    totalStrength::Float64
    facet::Union{Nothing,Slipnode}
    descriptor::Union{Nothing,Slipnode}
    category::Union{Nothing,Slipnode}
    relation::Union{Nothing,Slipnode}
end

# The fields shared by every WorkspaceObject, in the order Python declares them.
macro ws_object_fields()
    esc(quote
        ctx::AbstractCtx
        string::WorkspaceString
        internalStrength::Float64
        externalStrength::Float64
        totalStrength::Float64
        descriptions::Vector{Description}
        bonds::Vector{Bond}
        group::Union{Nothing,Group}
        changed::Bool
        correspondence::Union{Nothing,Correspondence}
        rawImportance::Float64
        relativeImportance::Float64
        leftBond::Union{Nothing,Bond}
        rightBond::Union{Nothing,Bond}
        name::String
        replacement::Union{Nothing,Replacement}
        rightIndex::Int
        leftIndex::Int
        leftmost::Bool
        rightmost::Bool
        intraStringSalience::Float64
        interStringSalience::Float64
        totalSalience::Float64
        intraStringUnhappiness::Float64
        interStringUnhappiness::Float64
        totalUnhappiness::Float64
    end)
end

# Group is declared before Letter because a Letter names its enclosing Group;
# Group's own `group` field is self-referential, which Julia allows.
mutable struct Group <: WSObject
    @ws_object_fields
    groupCategory::Slipnode
    directionCategory::Union{Nothing,Slipnode}
    facet::Slipnode
    objectList::Vector{WSObject}
    bondList::Vector{Bond}
    bondCategory::Slipnode
    bondDescriptions::Vector{Description}
end

mutable struct Letter <: WSObject
    @ws_object_fields
end

# Both concrete object types are known by this point, so the workspace's own
# object list can use a small Union, which Julia splits into a branch instead of
# a dynamic lookup. This is the list scanned by Description.localSupport, the
# hottest loop in the program.
const WSObj = Union{Group,Letter}

mutable struct Workspace
    ctx::AbstractCtx
    totalUnhappiness::Float64
    intraStringUnhappiness::Float64
    interStringUnhappiness::Float64
    targetString::String
    initialString::String
    modifiedString::String
    finalAnswer::Union{Nothing,String}
    changedObject::Union{Nothing,WSObject}
    objects::Vector{WSObj}
    structures::Vector{WSStructure}
    rule::Union{Nothing,Rule}
    initial::WorkspaceString
    modified::WorkspaceString
    target::WorkspaceString

    function Workspace(ctx)
        w = new()
        w.ctx = ctx
        w.totalUnhappiness = 0.0
        w.intraStringUnhappiness = 0.0
        w.interStringUnhappiness = 0.0
        w.targetString = ""
        w.initialString = ""
        w.modifiedString = ""
        w.finalAnswer = nothing
        w.changedObject = nothing
        w.objects = WSObj[]
        w.structures = WSStructure[]
        w.rule = nothing
        return w
    end
end

# --- coderack ----------------------------------------------------------------

mutable struct Codelet
    name::String
    urgency::Float64
    arguments::Vector{Any}
    birthdate::Int
end

mutable struct Coderack
    ctx::AbstractCtx
    codelets::Vector{Codelet}
    codeletsRun::Int
    Coderack(ctx) = new(ctx, Codelet[], 0)
end

# --- temperature -------------------------------------------------------------

mutable struct Temperature
    history::Vector{Float64}
    actual_value::Float64
    last_unclamped_value::Float64
    clamped::Bool
    clampTime::Int
    adjustmentType::Symbol
    diffs::Float64
    ndiffs::Int
    Temperature() = new([100.0], 100.0, 100.0, true, 30, :inverse, 0.0, 0)
end

# --- randomness --------------------------------------------------------------

mutable struct Randomness
    rng::PyRandom
end
Randomness(seed::Integer) = Randomness(PyRandom(seed))
Randomness(::Nothing) = Randomness(PyRandom())
Randomness() = Randomness(PyRandom())

# --- reporters ---------------------------------------------------------------

abstract type Reporter end
struct NullReporter <: Reporter end
struct SimpleReporter <: Reporter end

mutable struct Copycat <: AbstractCtx
    coderack::Coderack
    random::Randomness
    slipnet::Slipnet
    temperature::Temperature
    workspace::Workspace
    reporter::Reporter
    lastUpdate::Float64
    # Partially initialised; the fields are filled in by the outer
    # constructor, which is how the cyclic ctx <-> workspace links are tied.
    Copycat(::Nothing) = new()
end
