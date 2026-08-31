# Julia counterpart of bench/metacat_coderack_probe.ss.
include("../julia/src/pyrandom.jl")
include("../julia/src/metacat/schemenum.jl")
include("../julia/src/metacat/utilities.jl")
include("../julia/src/metacat/slipnet.jl")
include("../julia/src/metacat/workspace.jl")
include("../julia/src/metacat/concept_mappings.jl")
include("../julia/src/metacat/images.jl")
include("../julia/src/metacat/bonds.jl")
include("../julia/src/metacat/groups.jl")
include("../julia/src/metacat/bridges.jl")
include("../julia/src/metacat/coderack.jl")

uname_display(s::Symbol) = replace(String(s), "_" => "-")

for b in 0:(NUM_OF_CODERACK_BINS - 1), t in 0:10:100
    println("URG\t", b, "\t", t, "\t", bin_urgency(b, t))
end

for u in 0:100
    println("BIN\t", u, "\t", coderack_bin_for(u))
end

for u in (0, 7, 8, 21, 22, 35, 36, 49, 50, 63, 64, 77, 78, 91, 92, 100)
    println("UNAME\t", u, "\t", uname_display(urgency_name(u)))
end

const CTS = make_bottom_up_codelet_types()

for temp in (0, 25, 50, 75, 100)
    for ct in CTS
        println("BUURG\t", temp, "\t", codelet_type_display(ct), "\t",
                bottom_up_urgency(ct, temp))
    end
end

function probe_coderack(seed, temp, n)
    println("RUN\t", seed, "\t", temp, "\t", n)
    cr = Coderack()
    rng = PyRandom(seed)
    codelet_count = 0
    for i in 0:(n - 1)
        codelet_count = i
        ct = CTS[mod(i, length(CTS)) + 1]
        urgency = mod(7 * i, 101)
        post!(cr, make_codelet(ct, urgency), codelet_count, rng, temp)
    end
    println("POSTED\t", cr.current_num, "\t", total_urgency_sum(cr, temp))
    for bin in cr.bins
        println("BINSTATE\t", bin.current_index, "\t", bin_urgency(bin.bin_number, temp),
                "\t", bin_urgency_sum(bin, temp))
    end
    update_all_selection_probabilities!(cr, temp)
    for k in 0:29
        c = choose_codelet!(cr, rng, temp)
        println("CHOSE\t", k, "\t", codelet_type_display(c.codelet_type), "\t",
                sround(c.relative_urgency), "\t", cr.current_num)
    end
end

probe_coderack(4242, 50, 40)
probe_coderack(909, 10, 120)
probe_coderack(31337, 90, 100)
