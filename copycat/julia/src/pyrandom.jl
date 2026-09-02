# A bit-exact reimplementation of CPython's `random.Random` for the operations
# Copycat uses: random(), getrandbits() and _randbelow().
#
# Reproducing CPython's stream exactly is what lets the Julia port be validated
# against the Python original: seeded with the same integer, both programs draw
# the identical sequence of numbers and therefore must reach the identical
# answer on every trial. Any behavioural divergence is then a real porting bug
# rather than RNG noise.

const MT_N = 624
const MT_M = 397
const MATRIX_A = 0x9908b0df
const UPPER_MASK = 0x80000000
const LOWER_MASK = 0x7fffffff

mutable struct PyRandom
    mt::Vector{UInt32}
    mti::Int
    ncalls::Int          # high-level draws, for cross-checking against CPython
end

function init_genrand!(r::PyRandom, s::UInt32)
    mt = r.mt
    mt[1] = s
    for i in 1:(MT_N - 1)
        prev = mt[i]
        mt[i + 1] = (1812433253 * (prev ⊻ (prev >> 30)) + UInt32(i)) & 0xffffffff
    end
    r.mti = MT_N
    return r
end

"""CPython's init_by_array seeding (mt19937ar `init_by_array`)."""
function init_by_array!(r::PyRandom, key::Vector{UInt32})
    init_genrand!(r, UInt32(19650218))
    mt = r.mt
    klen = length(key)
    i = 1
    j = 0
    k = max(MT_N, klen)
    while k > 0
        prev = mt[i]                       # mt[i-1] in 0-based C indexing
        mt[i + 1] = ((mt[i + 1] ⊻ ((prev ⊻ (prev >> 30)) * 1664525)) +
                     key[j + 1] + UInt32(j)) & 0xffffffff
        i += 1
        j += 1
        if i >= MT_N
            mt[1] = mt[MT_N]
            i = 1
        end
        if j >= klen
            j = 0
        end
        k -= 1
    end
    k = MT_N - 1
    while k > 0
        prev = mt[i]
        mt[i + 1] = ((mt[i + 1] ⊻ ((prev ⊻ (prev >> 30)) * 1566083941)) -
                     UInt32(i)) & 0xffffffff
        i += 1
        if i >= MT_N
            mt[1] = mt[MT_N]
            i = 1
        end
        k -= 1
    end
    mt[1] = 0x80000000
    r.mti = MT_N
    return r
end

"""Split a non-negative integer into 32-bit little-endian words, as CPython
`random_seed` does for an integer seed (at least one word)."""
function seed_key(n::Integer)
    v = abs(big(n))
    key = UInt32[]
    if v == 0
        push!(key, UInt32(0))
    else
        while v > 0
            push!(key, UInt32(v & 0xffffffff))
            v >>= 32
        end
    end
    return key
end

PyRandom(seed::Integer) = init_by_array!(PyRandom(zeros(UInt32, MT_N), MT_N + 1, 0),
                                         seed_key(seed))

function PyRandom()
    # CPython seeds from os.urandom when no seed is given.
    PyRandom(rand(UInt128))
end

function genrand_int32(r::PyRandom)::UInt32
    mt = r.mt
    if r.mti >= MT_N
        @inbounds for kk in 1:(MT_N - MT_M)
            y = (mt[kk] & UPPER_MASK) | (mt[kk + 1] & LOWER_MASK)
            mt[kk] = mt[kk + MT_M] ⊻ (y >> 1) ⊻ (isodd(y) ? MATRIX_A : UInt32(0))
        end
        @inbounds for kk in (MT_N - MT_M + 1):(MT_N - 1)
            y = (mt[kk] & UPPER_MASK) | (mt[kk + 1] & LOWER_MASK)
            mt[kk] = mt[kk + (MT_M - MT_N)] ⊻ (y >> 1) ⊻ (isodd(y) ? MATRIX_A : UInt32(0))
        end
        @inbounds begin
            y = (mt[MT_N] & UPPER_MASK) | (mt[1] & LOWER_MASK)
            mt[MT_N] = mt[MT_M] ⊻ (y >> 1) ⊻ (isodd(y) ? MATRIX_A : UInt32(0))
        end
        r.mti = 0
    end
    @inbounds y = mt[r.mti + 1]
    r.mti += 1
    y ⊻= (y >> 11)
    y ⊻= (y << 7) & 0x9d2c5680
    y ⊻= (y << 15) & 0xefc60000
    y ⊻= (y >> 18)
    return y
end

"""CPython's `random.random()` (genrand_res53): 53 bits from two draws."""
function py_random(r::PyRandom)::Float64
    r.ncalls += 1
    a = genrand_int32(r) >> 5
    b = genrand_int32(r) >> 6
    return (Float64(a) * 67108864.0 + Float64(b)) * (1.0 / 9007199254740992.0)
end

"""CPython's `getrandbits(k)` for 0 < k <= 32, which is all Copycat needs."""
function py_getrandbits(r::PyRandom, k::Int)::UInt32
    r.ncalls += 1
    k == 0 && return UInt32(0)
    k <= 32 || throw(ArgumentError("only k <= 32 supported (k=$k)"))
    return genrand_int32(r) >> (32 - k)
end

"""CPython's `Random._randbelow_with_getrandbits`: rejection sampling."""
function py_randbelow(r::PyRandom, n::Int)::Int
    n <= 0 && return 0
    k = 64 - leading_zeros(UInt64(n))   # n.bit_length()
    v = py_getrandbits(r, k)
    while v >= n
        v = py_getrandbits(r, k)
    end
    return Int(v)
end
