# Ported from Metacat's coderack.ss.
#
# The coderack holds the pending codelets, sorted into seven urgency bins. A
# codelet is chosen by first picking a bin with probability proportional to the
# bin's urgency sum, then picking uniformly at random inside that bin. Both the
# bin urgencies and the posting probabilities are functions of temperature, so
# the whole scheduler anneals along with the rest of the program.
#
# The codelet PROCEDURES - what each codelet type actually does - live in the
# structure files (bonds.ss, groups.ss, bridges.ss, ...) and are ported with
# their layers; this file is the scheduling machinery around them.

const MAX_CODERACK_SIZE = 100
const NUM_OF_CODERACK_BINS = 7

const EXTREMELY_LOW_URGENCY = 7
const VERY_LOW_URGENCY = 21
const LOW_URGENCY = 35
const MEDIUM_URGENCY = 49
const HIGH_URGENCY = 63
const VERY_HIGH_URGENCY = 77
const EXTREMELY_HIGH_URGENCY = 91

function urgency_name(v)
    v <= EXTREMELY_LOW_URGENCY && return :extremely_low_urgency
    v <= VERY_LOW_URGENCY && return :very_low_urgency
    v <= LOW_URGENCY && return :low_urgency
    v <= MEDIUM_URGENCY && return :medium_urgency
    v <= HIGH_URGENCY && return :high_urgency
    v <= VERY_HIGH_URGENCY && return :very_high_urgency
    return :extremely_high_urgency
end

"""`%urgency-value-table%` — bin urgency by (bin number, temperature),
precomputed once. Note the 15.0: this exponent is inexact, so the whole entry
is computed in floating point and then rounded."""
const URGENCY_VALUE_TABLE = [sround(sexpt(bin + 1, ((100 - temp) + 10) / 15.0))
                             for bin in 0:(NUM_OF_CODERACK_BINS - 1), temp in 0:100]

bin_urgency(bin_number::Int, temperature::Int) =
    URGENCY_VALUE_TABLE[bin_number + 1, temperature + 1]

mutable struct CodeletType
    name::Symbol
    codelet_proc::Any
    urgency_clamped::Bool
    clamped_relative_urgency::Int
end

CodeletType(name::Symbol) = CodeletType(name, nothing, false, 0)

mutable struct Codelet
    codelet_type::CodeletType
    original_urgency::Real
    relative_urgency::Real
    coderack_bin::Int              # 0-based bin number
    index_in_bin::Int              # 0-based; -1 when not in a bin
    arguments::Vector{Any}
    proposed_structure_argument::Bool
    time_stamp::Int
    selection_probability::Float64
    codelet_count::Int
end

"""`(get-coderack-bin urgency)` — which bin an urgency falls in."""
function coderack_bin_for(urgency)
    i = urgency <= 0 ? 0 :
        urgency >= 100 ? NUM_OF_CODERACK_BINS - 1 :
        sfloor(pct(urgency) * NUM_OF_CODERACK_BINS)
    return Int(i)
end

"""A codelet argument is a "proposed structure" when it is a bond, group or
bridge - descriptions do not count, since they are not stored in the
workspace. NB both methods must be dispatched on, not written as an untyped
predicate plus an `::Any` fallback: those are the same signature, and the
second silently replaces the first."""
is_proposed_structure(::Union{Bond,Group,Bridge}) = true
is_proposed_structure(::Any) = false

function make_codelet(ct::CodeletType, urgency::Real, arguments::Vector{Any} = Any[])
    relative_urgency = ct.urgency_clamped ? ct.clamped_relative_urgency : urgency
    return Codelet(ct, urgency, relative_urgency, coderack_bin_for(relative_urgency),
                   -1, arguments,
                   !isempty(arguments) && is_proposed_structure(arguments[1]),
                   0, 0.0, 0)
end

mutable struct CoderackBin
    bin_number::Int
    codelet_vector::Vector{Union{Nothing,Codelet}}
    current_index::Int
    codelet_list::Vector{Codelet}
end

CoderackBin(n::Int) = CoderackBin(n, Union{Nothing,Codelet}[nothing for _ in 1:MAX_CODERACK_SIZE],
                                  0, Codelet[])

bin_urgency_sum(b::CoderackBin, temperature::Int) =
    b.current_index * bin_urgency(b.bin_number, temperature)

function add_codelet!(b::CoderackBin, c::Codelet, codelet_count::Int)
    b.codelet_vector[b.current_index + 1] = c
    c.index_in_bin = b.current_index
    b.current_index += 1
    pushfirst!(b.codelet_list, c)
    c.time_stamp = codelet_count
    return b
end

"""`(choose-random-codelet)` — uniform over the bin's occupied slots."""
choose_random_codelet(rng::PyRandom, b::CoderackBin) =
    b.codelet_vector[random_int(rng, b.current_index) + 1]::Codelet

"""`(remove-codelet codelet)` — swaps the last codelet into the freed slot."""
function remove_codelet!(b::CoderackBin, c::Codelet)
    index = c.index_in_bin
    b.current_index -= 1
    if index != b.current_index
        swap = b.codelet_vector[b.current_index + 1]::Codelet
        b.codelet_vector[index + 1] = swap
        swap.index_in_bin = index
    end
    c.index_in_bin = -1
    i = findfirst(x -> x === c, b.codelet_list)
    i === nothing || deleteat!(b.codelet_list, i)
    return b
end

function clear_codelets!(b::CoderackBin)
    b.current_index = 0
    b.codelet_list = Codelet[]
    return b
end

mutable struct Coderack
    bins::Vector{CoderackBin}
    codelet_list::Vector{Codelet}
    current_num::Int
    deferred_codelets::Vector{Codelet}
end

Coderack() = Coderack([CoderackBin(n) for n in 0:(NUM_OF_CODERACK_BINS - 1)],
                      Codelet[], 0, Codelet[])

coderack_empty(cr::Coderack) = isempty(cr.codelet_list)
total_urgency_sum(cr::Coderack, temperature::Int) =
    ssum([bin_urgency_sum(b, temperature) for b in cr.bins])
highest_bin_urgency(cr::Coderack, temperature::Int) =
    bin_urgency(cr.bins[end].bin_number, temperature)

function initialize!(cr::Coderack)
    foreach(clear_codelets!, cr.bins)
    cr.codelet_list = Codelet[]
    cr.current_num = 0
    cr.deferred_codelets = Codelet[]
    return cr
end

add_deferred_codelet!(cr::Coderack, c::Codelet) = (pushfirst!(cr.deferred_codelets, c); cr)

"""`(post codelet)`."""
function post!(cr::Coderack, c::Codelet, codelet_count::Int, rng::PyRandom,
               temperature::Int)
    cr.current_num == MAX_CODERACK_SIZE &&
        delete_codelets!(cr, 1, codelet_count, rng, temperature)
    add_codelet!(cr.bins[c.coderack_bin + 1], c, codelet_count)
    pushfirst!(cr.codelet_list, c)
    cr.current_num += 1
    return cr
end

"""`(post-deferred-codelets)` — makes room first, then posts them all."""
function post_deferred_codelets!(cr::Coderack, codelet_count::Int, rng::PyRandom,
                                 temperature::Int)
    num_to_delete = cr.current_num + length(cr.deferred_codelets) - MAX_CODERACK_SIZE
    num_to_delete > 0 && delete_codelets!(cr, num_to_delete, codelet_count, rng, temperature)
    for c in cr.deferred_codelets
        add_codelet!(cr.bins[c.coderack_bin + 1], c, codelet_count)
        pushfirst!(cr.codelet_list, c)
        cr.current_num += 1
    end
    cr.deferred_codelets = Codelet[]
    return cr
end

"""`(get-removal-weight)` — older codelets in low-urgency bins go first."""
removal_weight(c::Codelet, cr::Coderack, codelet_count::Int, temperature::Int) =
    (codelet_count - c.time_stamp) *
    (1 + (highest_bin_urgency(cr, temperature) - bin_urgency(c.coderack_bin, temperature)))

"""`(delete-proposed-structure struc)` from workspace.ss — when a codelet
carrying a proposed structure is culled, the structure goes with it. The
methods live with their structure layers, which load after this file."""
function delete_proposed_structure! end

function delete_codelets!(cr::Coderack, num_to_delete::Int, codelet_count::Int,
                          rng::PyRandom, temperature::Int)
    for _ in 1:num_to_delete
        weights = [removal_weight(c, cr, codelet_count, temperature) for c in cr.codelet_list]
        c = stochastic_pick(rng, cr.codelet_list, weights)::Codelet
        c.proposed_structure_argument && delete_proposed_structure!(c.arguments[1])
        remove_codelet!(cr.bins[c.coderack_bin + 1], c)
        i = findfirst(x -> x === c, cr.codelet_list)
        i === nothing || deleteat!(cr.codelet_list, i)
    end
    cr.current_num -= num_to_delete
    return cr
end

"""`(choose-codelet)` — pick a bin weighted by its urgency sum, then a codelet
uniformly within it."""
function choose_codelet!(cr::Coderack, rng::PyRandom, temperature::Int)
    bin = stochastic_pick(rng, cr.bins,
                          [bin_urgency_sum(b, temperature) for b in cr.bins])::CoderackBin
    c = choose_random_codelet(rng, bin)
    remove_codelet!(bin, c)
    i = findfirst(x -> x === c, cr.codelet_list)
    i === nothing || deleteat!(cr.codelet_list, i)
    cr.current_num -= 1
    return c
end

"""`(update-all-selection-probabilities)`."""
function update_all_selection_probabilities!(cr::Coderack, temperature::Int)
    for c in cr.codelet_list
        c.selection_probability = 0.0
        c.codelet_count = 0
    end
    total = total_urgency_sum(cr, temperature)
    total == 0 && return cr
    for b in cr.bins
        b.current_index == 0 && continue
        urgency_sum = bin_urgency_sum(b, temperature)
        codelet_probability = sdiv(sdiv(urgency_sum, total), b.current_index)
        for c in b.codelet_list
            c.codelet_count += 1
            c.selection_probability += sinexact(codelet_probability)
        end
    end
    return cr
end

"""`(bottom-up-urgency codelet-type)`."""
function bottom_up_urgency(ct::CodeletType, temperature::Int)
    ct.name === :answer_finder && return sub_from_100(temperature)
    ct.name === :answer_justifier && return sub_from_100(temperature)
    ct.name === :breaker && return EXTREMELY_LOW_URGENCY
    ct.name === :progress_watcher && return MEDIUM_URGENCY
    ct.name === :jootser && return MEDIUM_URGENCY
    return LOW_URGENCY
end

"""`*bottom-up-codelet-types*`, in declaration order. The codelet procedures
themselves live with their structure layers; these are the scheduling
identities."""
const BOTTOM_UP_CODELET_TYPE_NAMES = [
    :bottom_up_bond_scout, :group_scout_whole_string, :bottom_up_bridge_scout,
    :important_object_bridge_scout, :bottom_up_description_scout, :rule_scout,
    :answer_finder, :answer_justifier, :progress_watcher, :jootser, :breaker,
]

make_bottom_up_codelet_types() = [CodeletType(n) for n in BOTTOM_UP_CODELET_TYPE_NAMES]

"""The Scheme prints codelet type names with hyphens, and a colon before the
qualifier on the scouts that have one."""
function codelet_type_display(ct::CodeletType)
    name = String(ct.name)
    for (suffix, replacement) in ("_scout_whole_string" => "-scout:whole-string",
                                  "_scout_category" => "-scout:category",
                                  "_scout_direction" => "-scout:direction")
        endswith(name, suffix) &&
            return replace(name[1:(end - length(suffix))], "_" => "-") * replacement
    end
    return replace(name, "_" => "-")
end

"""The codelet-type registry. Procedures are attached by the codelet layers as
they are ported, mirroring set-codelet-procedure in the Scheme."""
const CODELET_TYPES = Dict{Symbol,CodeletType}()

function register_codelet_type!(name::Symbol, proc)
    ct = get!(CODELET_TYPES, name, CodeletType(name))
    ct.codelet_proc = proc
    return ct
end

"""Run a codelet: apply its type's procedure to its arguments."""
run_codelet!(ctx, c::Codelet) = c.codelet_type.codelet_proc(ctx, c.arguments)
