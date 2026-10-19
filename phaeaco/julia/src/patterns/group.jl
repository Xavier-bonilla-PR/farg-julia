# Group and pattern formation (§8.3): the *Patterns* algorithm.

"""
Update a pattern with an exemplar (or another pattern) — §8.3.3. Feature and
numerosity statistics merge (Eqs. 8.9–8.11, generalised to samples). Parts
are put in correspondence type by type; corresponding parts merge
recursively; parts with no counterpart join the pattern weakly (support 1 of
many). A count the exemplar lacks counts as zero for it if it has none of
those things, and is skipped if it has some but did not count them.
"""
function update!(M::Matcher, p::RNode, e::RNode; depth::Int=0)
    oldsupport = p.support
    p.support += e.support
    for (f, s) in e.feats
        merge!(get!(p.feats, f, Stats()), s)
    end
    for t in union(keys(p.nums), keys(e.nums))
        if !haskey(e.nums, t)
            # zero only if the exemplar has none of these; uncounted ones add nothing
            if count_of(e, t) !== nothing
                for _ in 1:e.support
                    push!(p.nums[t], 0.0)
                end
            end
        elseif !haskey(p.nums, t)
            z = Stats()
            for _ in 1:oldsupport
                push!(z, 0.0)
            end
            p.nums[t] = merge!(z, e.nums[t])
        else
            merge!(p.nums[t], e.nums[t])
        end
    end
    for t in unique(c.type for c in e.children)
        ec = [c for c in e.children if c.type == t]
        pc = [c for c in p.children if c.type == t]
        matched = Set{Int}()
        for (i, j) in correspond(M, ec, pc, depth + 1)
            update!(M, pc[j], ec[i]; depth=depth + 1)
            push!(matched, i)
        end
        for (i, c) in enumerate(ec)
            i in matched || push!(p.children, copy(c))
        end
    end
    p.origin = 0
    return p
end

"""A pattern begun from one exemplar."""
pattern_of(e::RNode) = (p = copy(e); p.origin = 0; p)

"""A group the Patterns algorithm found: its pattern and which exemplars it holds."""
mutable struct Group
    pattern::RNode
    members::Vector{Int}
end

"""
    find_patterns(M, exemplars; threshold) -> Vector{Group}

The *Patterns* algorithm of Fig. 8.6, with Fig. 8.8 as its first test. Each
exemplar, in order and seen once:

1. If it resembles some pattern (similarity above the clustering threshold),
   it updates the most similar one.
2. Otherwise it is compared with the exemplars kept so far that belong to
   no pattern; if the closest is similar enough, the two form a new pattern
   — unless that pattern resembles an existing one, in which case the
   exemplar is kept on its own (D27) — and the partner leaves the kept list.
3. Otherwise it is kept.

At the end, every kept exemplar becomes a group of one.
"""
function find_patterns(M::Matcher, exemplars::Vector{RNode}; threshold::Float64)
    groups = Group[]
    known = Int[]
    for (i, ex) in enumerate(exemplars)
        # Fig. 8.8: similar to one of the patterns?
        best, bests = 0, 0.0
        for (g, grp) in enumerate(groups)
            s = similarity(M, grp.pattern, ex)
            s > threshold && s > bests && (best = g; bests = s)
        end
        if best != 0
            update!(M, groups[best].pattern, ex)
            push!(groups[best].members, i)
            continue
        end
        closest, maxs = 0, 0.0
        for j in known
            s = similarity(M, exemplars[j], ex)
            s > maxs && (closest = j; maxs = s)
        end
        if closest != 0 && maxs > threshold
            p = update!(M, pattern_of(exemplars[closest]), ex)
            if any(g -> similarity(M, g.pattern, p) > threshold, groups)
                push!(known, i)
            else
                push!(groups, Group(p, [closest, i]))
                filter!(!=(closest), known)
            end
        else
            push!(known, i)
        end
    end
    for j in known
        push!(groups, Group(pattern_of(exemplars[j]), [j]))
    end
    return groups
end
