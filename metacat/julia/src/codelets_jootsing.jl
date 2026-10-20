# Ported from Metacat's jootsing.ss.
#
# JOOTS is Hofstadter's "Jumping Out Of The System". These two codelets are the
# model noticing that it is stuck in a way it cannot notice from inside the
# workspace — not "this bond is weak" but "I have now clamped the same pattern
# three times and got nowhere". That judgement can only be made from the TRACE,
# which is why all of this waited on trace.ss.
#
# The `jootser` looks for repetition: three equivalent clamps, or three
# equivalent snags. Recurring clamps mean the model's own ideas are not working,
# and it gives up. Recurring snags mean something about how it is SEEING the
# problem is wrong, so it clamps the NEGATION of the themes the snags keep
# implicating — telling itself to stop assuming what it has been assuming.
#
# The `progress-watcher` is the quieter one: it ends clamp periods that have run
# their course, and notices when nothing at all is happening.

"""`%satisfactory-rule-quality%` — below this the model is not happy with its
rules."""
const SATISFACTORY_RULE_QUALITY = 80

"""`%settling-period%` — how long after any event before a progress-watcher will
draw conclusions about how the clamp is going."""
const SETTLING_PERIOD = 250

# %max-clamp-period% and %grace-period% live in trace.jl, which needs them.

"""`(get-most-recent-event-set event-type)` — the largest recency-ranked cluster
of EQUIVALENT events of one type: the same thing having happened repeatedly.

Snags are counted only since the last answer (a snag before an answer is old
news); clamps are counted over the whole trace."""
function get_most_recent_event_set(tr::TemporalTrace, event_type::Symbol, ctx)
    all_recent = event_type === :snag ? get_new_events_since_last(tr, :answer) :
                                        get_all_events(tr)
    of_type = Any[e for e in all_recent if event_type_is(e, event_type)]
    isempty(of_type) && return Any[]
    clusters = partition_pred((e1, e2) -> jootsing_events_equal(e1, e2, ctx), of_type)
    # the cluster whose youngest member is youngest of all
    most_recent = select_extreme(minimum,
                                 c -> minimum(get_age(e, ctx) for e in c),
                                 clusters)
    return most_recent === nothing ? Any[] : most_recent
end

"""`equal?` across the two event types this clustering sees."""
function jootsing_events_equal(e1, e2, ctx)
    e1 isa ClampEvent && return events_equal(e1, e2, ctx.net)
    e1 isa SnagEvent && return events_equal(e1, e2, ctx.net)
    return false
end

"""`(get-clamp-jootsing-probability clamps)` — how ready the model is to give up
on a kind of clamp.

The progress each clamp achieved is averaged, weighted by HOW LATE it happened
(a clamp late in the run says more about the current situation than one at the
start). Low average progress and many clamps push the probability up. The
clamp-type factor is the model's prior about which kinds of clamp are worth
persisting with: rule-codelet clamps get the benefit of the doubt (0.5), and a
justify clamp only counts if it was the very last thing that happened."""
function get_clamp_jootsing_probability(clamps, tr::TemporalTrace, ctx)
    clamp_type = get_clamp_type(clamps[1]::ClampEvent)
    num_of_clamps = length(clamps)
    elapsed_time_weights = [mul_100(sdiv(get_time(c), ctx.codelet_count))
                            for c in clamps]
    average_progress = sround(weighted_average(
        [get_progress_achieved(c::ClampEvent) for c in clamps], elapsed_time_weights))
    last_event = get_last_event(tr, :any)
    clamp_type_factor =
        clamp_type === :justify_clamp ?
            (last_event !== nothing && event_type_is(last_event, :clamp) ? 1 : 0) :
        clamp_type === :snag_response_clamp ? 1 : 0.5
    return sub_from_1(pct(average_progress)) *
           pct(min(100, 10 * num_of_clamps)) * clamp_type_factor
end

"""`(joots-from-rule-codelet-clamps)` / `(joots-from-snag-response-clamps)` —
both give up. The commentary that distinguishes them is `*comment-window*`."""
joots_from_rule_codelet_clamps(clamps, ctx) = give_up!(ctx)
joots_from_snag_response_clamps(clamps, ctx) = give_up!(ctx)

"""`(joots-from-justify-clamps clamps)` — the one arm that does not simply give
up, because in justify mode there is always an answer; the question is whether
the model can justify it.

It re-translates the clamped top rule and asks how far the translation is from
the bottom rule. No unjustified slippages at all means the two halves DO line
up and the jootser was wrong to be here, so it posts an answer-justifier and
fizzles. Otherwise it settles: with probability 1/n for n unjustified
slippages, it reports the answer anyway, carrying those slippages with it — an
answer the model accepts without being able to justify.

NB the two `currently-works?` guards: a rule that no longer works cannot be
settled for, and the codelet fizzles rather than reporting a stale answer."""
function joots_from_justify_clamps(clamps, ctx)
    net = ctx.net
    mem = ctx.memory
    answer_string = ctx.answer_string::WorkspaceString
    clamp = clamps[1]::ClampEvent
    top_rule = get_event_rule(clamp, :top)
    bottom_rule = get_event_rule(clamp, :bottom)
    (top_rule === nothing || bottom_rule === nothing) && return
    mem !== nothing &&
        answer_present(mem::Memory, answer_string.letter_categories,
                       top_rule::Rule, bottom_rule::Rule, ctx, net) && return
    (currently_works(top_rule::Rule, ctx) &&
     currently_works(bottom_rule::Rule, ctx)) || return
    result = translate(ctx.rng, top_rule::Rule, ctx.initial_string,
                       ctx.target_string, net)
    result === nothing && return
    unjustified_slippages = get_unifying_slippages(result.translated_rule,
                                                   bottom_rule::Rule, net)
    if isempty(unjustified_slippages)
        post!(ctx.coderack,
              make_codelet(CODELET_TYPES[:answer_justifier], EXTREMELY_HIGH_URGENCY),
              ctx.codelet_count, ctx.rng, ctx.temperature, ctx)
        return
    end
    # stochastic-if* ALWAYS draws, and the test is phrased backwards: this
    # FIZZLES with probability 1 - 1/n.
    random_real(ctx.rng, 1.0) < sub_from_1(sdiv(1, length(unjustified_slippages))) &&
        return
    all_supporting_groups = remq_duplicates(
        Any[result.vertical_mapping_supporting_groups...,
            get_rule_supporting_groups(top_rule::Rule, bottom_rule::Rule, ctx, net)...])
    bottom_rule_ref_objects = Any[o for o in
                                  get_all_reference_objects(ctx.target_string,
                                                            bottom_rule::Rule, net)
                                  if !(o isa WorkspaceString)]
    return report_new_answer!(answer_string, top_rule::Rule, bottom_rule::Rule,
                              result.supporting_vertical_bridges,
                              all_supporting_groups,
                              result.from_string_ref_objects,
                              bottom_rule_ref_objects,
                              result.slippage_log, unjustified_slippages, mem, ctx)
end

"""`jootser` — notice that the model is going round in circles, and jump out.

Two passes. First recurring CLAMPS: three or more equivalent ones (manual clamps
excluded — those were the user's idea, not the model's) and it may simply give
up. Then recurring SNAGS: three or more, and the themes they keep implicating
are NEGATED and clamped, which is the model telling itself to stop assuming what
it has been assuming."""
function jootser(ctx::MetacatCtx, args::Vector{Any})
    TEMPERATURE[] = ctx.temperature
    net = ctx.net
    SELF_WATCHING_ENABLED[] || return
    tr = ctx.trace
    tr === nothing && return
    get_last_event(tr::TemporalTrace, :any) === nothing && return
    # Wait until not in a clamp period before judging repeated clamping.
    (tr::TemporalTrace).within_clamp_period && return
    clamps = Any[c for c in get_most_recent_event_set(tr::TemporalTrace, :clamp, ctx)
                 if !is_clamp_type(c::ClampEvent, :manual_clamp)]
    if length(clamps) >= 3
        clamp_type = get_clamp_type(clamps[1]::ClampEvent)
        p = get_clamp_jootsing_probability(clamps, tr::TemporalTrace, ctx)
        # stochastic-if* ALWAYS draws
        if random_real(ctx.rng, 1.0) < p
            clamp_type === :rule_codelet_clamp &&
                return joots_from_rule_codelet_clamps(clamps, ctx)
            clamp_type === :snag_response_clamp &&
                return joots_from_snag_response_clamps(clamps, ctx)
            clamp_type === :justify_clamp &&
                return joots_from_justify_clamps(clamps, ctx)
            return
        end
    end
    snags = get_most_recent_event_set(tr::TemporalTrace, :snag, ctx)
    length(snags) >= 3 || return
    num_of_snags = length(snags)
    snag_theme_patterns = Any[get_snag_theme_pattern(s::SnagEvent) for s in snags]
    all_entries = Any[e for p in snag_theme_patterns for e in p[2:end]]
    # How often each theme entry recurs across the snags: a dimension every snag
    # implicates is what the model should stop assuming.
    overlap_clusters = partition_pred(theme_pattern_entries_equal, all_entries)
    theme_overlap_table = Any[Any[c[1], mul_100(sdiv(length(c), num_of_snags))]
                              for c in overlap_clusters]
    max_theme_overlap = maximum_or_zero(Any[e[2] for e in theme_overlap_table])
    jootsing_probability = pct(max_theme_overlap) * pct(min(100, 10 * num_of_snags))
    # NB phrased backwards: this FIZZLES with probability 1 - p.
    random_real(ctx.rng, 1.0) < sub_from_1(jootsing_probability) && return
    permission_to_clamp(tr::TemporalTrace, ctx) || return
    all_possible_entries = remove_duplicates_last(all_entries)
    snag_objects = Any[]
    for s in snags
        append!(snag_objects, get_snag_objects(s::SnagEvent))
    end
    snag_object_descriptions = remq_duplicates(
        Any[d for o in snag_objects for d in o.descriptions])
    # Each entry survives with probability (its overlap) x (how deep the snagged
    # objects' descriptions along that dimension are): a shallow coincidence is
    # not worth jumping out of.
    chosen_entries = Any[]
    for entry in all_possible_entries
        i = findfirst(e -> theme_pattern_entries_equal(e[1], entry),
                      theme_overlap_table)
        overlap = i === nothing ? 0 : theme_overlap_table[i][2]
        descriptions_for_theme = Any[d for d in snag_object_descriptions
                                     if d.description_type === entry[1]]
        average_depth = isempty(descriptions_for_theme) ? 0 :
            sdiv(sum(conceptual_depth(d) for d in descriptions_for_theme),
                 length(descriptions_for_theme))
        prob(ctx.rng, pct(overlap) * pct(average_depth)) && push!(chosen_entries, entry)
    end
    isempty(chosen_entries) && return
    negative_theme_pattern = Any[:vertical_bridge,
                                 Any[negate_theme_pattern_entry(e)
                                     for e in chosen_entries]...]
    clamp_event = make_clamp_event(:snag_response_clamp,
                                   Any[negative_theme_pattern,
                                       bottom_up_codelet_pattern()],
                                   Any[], :workspace, ctx)
    add_event!(tr::TemporalTrace, clamp_event, ctx)
    activate!(clamp_event, tr::TemporalTrace, ctx)
    return
end

"""`(remove-duplicates l)` on theme-pattern entries — value equality, keeping
the LAST of each group."""
remove_duplicates_last(l) =
    Any[x for (i, x) in enumerate(l)
        if !any(y -> theme_pattern_entries_equal(y, x), l[(i + 1):end])]

"""`progress-watcher` — end a clamp that has run its course, or notice that
nothing is happening.

Inside a clamp period it waits for things to settle (no event for a whole
settling period) before undoing the clamp and judging what it achieved; the
better the progress, the more likely it posts an answer-finder to capitalise on
it. Outside a clamp period it only acts when activity has fallen to zero, and
then only if the rules are not good enough — at which point it clamps the
rule-codelet pattern, which is the model deciding to concentrate on rules."""
function progress_watcher(ctx::MetacatCtx, args::Vector{Any})
    TEMPERATURE[] = ctx.temperature
    SELF_WATCHING_ENABLED[] || return
    tr = ctx.trace
    tr === nothing && return
    if (tr::TemporalTrace).within_clamp_period
        time_since_last_event = get_elapsed_time(tr::TemporalTrace, :any, ctx)
        time_since_last_event > SETTLING_PERIOD || return
        last_clamp = get_last_event(tr::TemporalTrace, :clamp)
        undo_last_clamp!(tr::TemporalTrace, ctx)
        last_clamp === nothing && return
        progress_achieved = get_progress_achieved(last_clamp::ClampEvent)
        # stochastic-if* ALWAYS draws
        if random_real(ctx.rng, 1.0) < pct(progress_achieved)
            post!(ctx.coderack,
                  make_codelet(CODELET_TYPES[ctx.answer_string === nothing ?
                                             :answer_finder : :answer_justifier],
                               progress_achieved),
                  ctx.codelet_count, ctx.rng, ctx.temperature, ctx)
        end
        return
    end
    get_activity(ctx) == 0 || return
    max_top_rule_quality = maximum_or_zero([r.quality for r in get_rules(ctx, :top)])
    max_bottom_rule_quality = maximum_or_zero([r.quality for r in get_rules(ctx, :bottom)])
    poor_top = max_top_rule_quality < SATISFACTORY_RULE_QUALITY
    poor_bottom = ctx.answer_string !== nothing &&
                  max_bottom_rule_quality < SATISFACTORY_RULE_QUALITY
    (poor_top || poor_bottom) || return
    permission_to_clamp(tr::TemporalTrace, ctx) || return
    clamp_probability = ctx.answer_string !== nothing ?
        sub_from_1(pct(min(max_top_rule_quality, max_bottom_rule_quality))) :
        sub_from_1(pct(max_top_rule_quality))
    random_real(ctx.rng, 1.0) < clamp_probability || return
    clamped_rule_codelet_pattern = against_background(VERY_LOW_URGENCY,
                                                      rule_codelet_pattern())
    clamp_event = make_clamp_event(:rule_codelet_clamp,
                                   Any[clamped_rule_codelet_pattern], Any[], :rule, ctx)
    add_event!(tr::TemporalTrace, clamp_event, ctx)
    activate!(clamp_event, tr::TemporalTrace, ctx)
    return
end

"""`(how-strings-change string1 string2)` — used only by the commentary the
progress-watcher writes, which is `*comment-window*`."""
how_strings_change(string1, string2) =
    string("how \"", string1.print_name, "\" changes to \"", string2.print_name, "\"")

register_codelet_type!(:jootser, jootser)
register_codelet_type!(:progress_watcher, progress_watcher)
