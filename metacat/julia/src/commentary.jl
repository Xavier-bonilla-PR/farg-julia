# Ported from Metacat's answers.ss (95-928) — the COMMENTARY: the English
# Metacat writes about its own answers.
#
# This is the part of the program the thesis is really about. Everything else
# in the port answers "what did the model build?"; this answers "what does the
# model say it was thinking?", and it says it out of the episodic memory alone
# — an answer description, and at most one other to compare it with. No
# workspace, no coderack, no slipnet activation: by the time these run, the run
# that produced the answer is over and all that is left is what was abstracted
# from it.
#
# Kept in its own file rather than appended to `answers.jl` because it shares
# nothing with the machinery there: it is pure string composition over
# `memory.jl`'s descriptions, plus `justify.jl`'s rule comparison. It loads
# after both.
#
# The output is prose, so the port is a transcription, and the probe compares
# it character for character. Two things make that less tedious than it sounds:
# every branch is reachable by choosing the two descriptions, and a wrong word
# is as visible as a wrong number.
#
# NOT ported: the `*comment-window*` sends themselves. Each of these functions
# returns the text the Scheme would have drawn.
#
# Worth knowing before looking for callers: in Metacat 1.0 nothing in the model
# calls any of this. `compare-answers` is called only from `memory-graphics.ss`,
# when a person clicks two answers in the memory window, and `explain` and
# `coherence-phrase` are not called from anywhere in the vendored source at all.
# The commentary is what Metacat says when asked, not something it says as it
# runs — so the probe is the only thing that exercises it, and that is not a
# gap in the probe.

"""`(punctuate-with-commas conj l)` — "a", "a and b", "a, b, and c". NB the
two-element case has a comma before the conjunction and the general case ends
with ", <conj> <last>", so three items read "a, b, and c"."""
function punctuate_with_commas(conj, l)
    isempty(l) && return ""
    length(l) == 1 && return l[1]
    length(l) == 2 && return string(l[1], ", ", conj, " ", l[2])
    return string(join([string(x, ", ") for x in l[1:(end - 1)]]),
                  conj, " ", l[end])
end

"""`(intersect l1 l2)` — the Scheme's `eq?` intersection, which is a CROSS
PRODUCT keeping the element from the first list, so an element of `l1` appears
once per match in `l2`. `themes.jl`'s `sintersect` is the deduplicated form;
the two agree whenever `l2` has no duplicates, which is the case here (a theme
pattern holds one entry per dimension) — but the shape is worth keeping."""
chez_intersect(l1, l2) = Any[x for x in l1 for y in l2 if x === y]

"""`(member-equal? theme l)` for THEME ENTRIES. `utilities.jl`'s `member_equal`
is `==`, which in Julia distinguishes a tuple from a vector; the Scheme's
`equal?` sees only the structure, and entries reach here from both hand-written
patterns and abstracted ones. `theme_entry_equal` (memory.jl) is the structural
test `remove-elements` already uses, so use it here too."""
member_theme(x, l) = any(y -> theme_entry_equal(y, x), l)

"""`(remove-duplicates l)` — value equality, keeping the LAST of each group."""
remove_duplicates_equal(l) =
    Any[x for (i, x) in enumerate(l) if !member_theme(x, l[(i + 1):end])]

"""`(get-snag-explanation answer)` — what went wrong the last time this answer's
problem was attempted with this rule, if the memory holds such a snag."""
function get_snag_explanation(a::AnswerDescription, mem, net::Slipnet)
    mem === nothing && return ""
    snag = get_equivalent_snag(mem::Memory, a, net)
    return snag === nothing ? "" : (snag::SnagDescription).snag_explanation
end

"""`(theme-phrases prep conj verb-ending themes snag-justified-themes
unjustified-themes initial target snag-explanation add-caveats? the-strings?
two-strings)` — the heart of the commentary: a list of themes turned into
English.

Only four dimensions get a phrase — string-position, alphabetic-position,
group-category and bond-facet — and they interact. String-position and
group-category share one clause when both are present ("seeing abc and pqrs as
symmetric predecessor and successor groups going in opposite directions"), so
group-category only gets a clause of its own when string-position is absent;
and bond-facet rides along inside the group-category clause in that case, but
gets its own clause otherwise.

`add-caveats?` is what makes the model honest about itself: a theme it has no
justification for is followed by "(although there is no good reason for doing
so)", and one that only exists because it dodges a remembered snag says so."""
function theme_phrases(prep, conj, verb_ending, themes, snag_justified_themes,
                       unjustified_themes, initial, target, snag_explanation,
                       add_caveats::Bool, the_strings::Bool, two_strings, net::Slipnet)
    all_themes = Any[themes..., unjustified_themes...]
    assq(node) = (i = findfirst(t -> t[1] === node, all_themes);
                  i === nothing ? nothing : all_themes[i])
    string_pos_theme = assq(net[:plato_string_position_category])
    # The direction theme should always agree with the string-position one.
    alpha_pos_theme = assq(net[:plato_alphabetic_position_category])
    group_ctgy_theme = assq(net[:plato_group_category])
    bond_facet_theme = assq(net[:plato_bond_facet])
    strings = two_strings !== nothing ? string("two strings ", two_strings) :
              string(initial, " and ", target)
    identity = net[:plato_identity]
    opposite = net[:plato_opposite]
    function caveat(theme)
        add_caveats || return ""
        member_theme(theme, unjustified_themes) &&
            return " (although there is no good reason for doing so)"
        member_theme(theme, snag_justified_themes) &&
            return string(" (which avoids a snag that would otherwise ",
                          "arise from the fact that ", snag_explanation, ")")
        return ""
    end
    # `the-strings?` and a present string-position theme both mean the strings
    # have already been named, so a later clause can just say "the strings".
    named_strings = (string_pos_theme !== nothing || the_strings) ? "the strings" : strings
    group_ctgy_unjustified = group_ctgy_theme !== nothing &&
                             member_theme(group_ctgy_theme, unjustified_themes)
    phrases = String[]
    if string_pos_theme !== nothing
        group_part = (group_ctgy_theme === nothing || group_ctgy_unjustified) ? "" :
                     group_ctgy_theme[2] === identity ? "groups of the same type " :
                     group_ctgy_theme[2] === opposite ?
                         "symmetric predecessor and successor groups " :
                         "different kinds of groups "
        direction_part =
            string_pos_theme[2] === identity ? "going in the same direction" :
            string_pos_theme[2] === opposite ? "going in opposite directions" :
                "neither going in the same nor in opposite directions"
        push!(phrases, string(prep, "see", verb_ending, " ", strings, " as ",
                              group_part, direction_part, caveat(string_pos_theme)))
    end
    if group_ctgy_theme !== nothing && string_pos_theme === nothing &&
       !group_ctgy_unjustified
        group_part = group_ctgy_theme[2] === identity ? "groups of the same type" :
                     group_ctgy_theme[2] === opposite ?
                         "symmetric predecessor and successor groups" :
                         "different kinds of groups"
        facet_part = bond_facet_theme === nothing ? "" :
                     string(" by viewing one string in terms of letters ",
                            "and the other in terms of numbers")
        push!(phrases, string(prep, "see", verb_ending, " ", strings, " as ",
                              group_part, facet_part, caveat(group_ctgy_theme)))
    end
    if bond_facet_theme !== nothing &&
       (string_pos_theme !== nothing || group_ctgy_theme === nothing ||
        group_ctgy_unjustified)
        push!(phrases, string(prep, "view", verb_ending, " one of ", named_strings,
                              " in terms of letters ",
                              "and the other in terms of numbers",
                              caveat(bond_facet_theme)))
    end
    if alpha_pos_theme !== nothing
        relation = alpha_pos_theme[2] === identity ? "sameness" : "symmetry"
        push!(phrases, string(prep, "see", verb_ending, " alphabetic-position ",
                              relation, " between ", named_strings,
                              caveat(alpha_pos_theme)))
    end
    return punctuate_with_commas(conj, phrases)
end

"""`(explain answer)` — what the model says about one answer, on its own.

The Scheme sends two versions to the comment window: the short one, which gives
the quality as a phrase, and the long one, which gives the number. Both share
the same first line, so both are returned."""
function explain(a::AnswerDescription, mem, net::Slipnet)
    initial = letters_print_name(a.initial_letters)
    target = letters_print_name(a.target_letters)
    themes = get_themes(a)
    snag_justified_themes = get_snag_justified_themes(a, mem, net)
    snag_explanation = get_snag_explanation(a, mem, net)
    unjustified_themes = remove_elements(snag_justified_themes,
                                         get_unjustified_themes(a))
    explanation = string("This answer is based ",
                         theme_phrases("on ", "and", "ing", themes,
                                       snag_justified_themes, unjustified_themes,
                                       initial, target, snag_explanation,
                                       true, false, nothing, net),
                         ".")
    return (String[explanation,
                   string("  Personally, I think this answer is ",
                          answer_quality_phrase(a.quality), ".")],
            String[explanation, string("  Answer quality = ", a.quality, ".")])
end

"""`(coherence-phrase coherence)`. NB the boundary: anything under 10 but not
negative is "very coherent", and 10 or more is merely "coherent"."""
coherence_phrase(coherence) =
    coherence < -50 ? "very incoherent" :
    coherence < -10 ? "incoherent" :
    coherence < 0 ? "somewhat incoherent" :
    coherence < 10 ? "very coherent" : "coherent"

"""`(get-answer-comparison-text self other)` — what the model says when a new
answer reminds it of an old one. The longest single piece of prose in Metacat,
and the one that most obviously has a POINT OF VIEW: it works out what the two
answers agree about, what they disagree about, what one of them never even
considered, which ideas neither answer has any justification for, and then says
which it prefers and why.

The vocabulary, in the order the `let*` builds it:

  common themes         — ideas both answers rest on
  differing dimensions  — dimensions both have an opinion about, and DIFFERENT
                          opinions (one sees sameness where the other sees
                          opposition)
  unique themes         — ideas one answer has and the other has no opinion on
                          at all, so they do not even disagree
  justification         — an idea common to both, but justified in only one

`answer2-mentioned-first?` is the trap. When there are theme differences but
answer1 contributed none of the answer-only themes, the text opens with answer2,
and if the two answers happen to be the SAME STRING the ordinals have to swap
too, so that "the first dyz" means the one named first."""
function get_answer_comparison_text(self::AnswerDescription, other::AnswerDescription,
                                    mem, net::Slipnet)
    initial1 = letters_print_name(self.initial_letters)
    modified1 = letters_print_name(self.modified_letters)
    target1 = letters_print_name(self.target_letters)
    answer1 = letters_print_name(self.answer_letters)
    initial2 = letters_print_name(other.initial_letters)
    modified2 = letters_print_name(other.modified_letters)
    target2 = letters_print_name(other.target_letters)
    answer2 = letters_print_name(other.answer_letters)
    problem1 = string("\"", initial1, " -> ", modified1, ", ", target1, " -> ?\"")
    problem2 = string("\"", initial2, " -> ", modified2, ", ", target2, " -> ?\"")
    change1 = string("the change from ", initial1, " to ", modified1)
    change2 = string("the change from ", initial2, " to ", modified2)
    full_answer1 = string(answer1, " to the problem ", problem1)
    full_answer2 = string(answer2, " to the problem ", problem2)
    same_problem = problem1 == problem2
    answer1_phrase = same_problem ? answer1 : full_answer1
    answer2_phrase = same_problem ? answer2 : full_answer2
    both_answers_phrase = string("the answer ", answer1_phrase, " and the answer ",
                                 full_answer2)
    # every idea, justified or not, underlying each answer
    all_themes1 = Any[get_themes(self)..., get_unjustified_themes(self)...]
    all_themes2 = Any[get_themes(other)..., get_unjustified_themes(other)...]
    snag_justified_themes1 = get_snag_justified_themes(self, mem, net)
    snag_justified_themes2 = get_snag_justified_themes(other, mem, net)
    unjustified_themes1 = remove_elements(snag_justified_themes1,
                                          get_unjustified_themes(self))
    unjustified_themes2 = remove_elements(snag_justified_themes2,
                                          get_unjustified_themes(other))
    all_unjustified_themes = remove_duplicates_equal(
        Any[unjustified_themes1..., unjustified_themes2...])
    snag_explanation1 = get_snag_explanation(self, mem, net)
    snag_explanation2 = get_snag_explanation(other, mem, net)
    common_themes = intersect_themes(all_themes1, all_themes2)
    common_dimensions = Any[t[1] for t in common_themes]
    differing_dimensions = remq_elements(
        common_dimensions,
        chez_intersect(Any[t[1] for t in all_themes1], Any[t[1] for t in all_themes2]))
    answer1_only_themes = remove_elements(common_themes, all_themes1)
    answer2_only_themes = remove_elements(common_themes, all_themes2)
    differing_themes1 = Any[t for t in all_themes1
                            if any(d -> d === t[1], differing_dimensions)]
    differing_themes2 = Any[t for t in all_themes2
                            if any(d -> d === t[1], differing_dimensions)]
    unique_themes1 = remove_elements(differing_themes1, answer1_only_themes)
    unique_themes2 = remove_elements(differing_themes2, answer2_only_themes)
    common_unjustified_themes = intersect_themes(unjustified_themes1,
                                                 unjustified_themes2)
    answer1_only_unjustified_themes = remove_elements(common_unjustified_themes,
                                                      unjustified_themes1)
    answer2_only_unjustified_themes = remove_elements(common_unjustified_themes,
                                                      unjustified_themes2)
    # ideas common to both answers but justified in only one of them
    common_answer1_only_unjustified_themes =
        remove_elements(differing_themes1, answer1_only_unjustified_themes)
    common_answer2_only_unjustified_themes =
        remove_elements(differing_themes2, answer2_only_unjustified_themes)
    justification_differences = !isempty(common_answer1_only_unjustified_themes) ||
                                !isempty(common_answer2_only_unjustified_themes)
    # NB `theme-phrases` is called here with the SAME list as both `themes` and
    # `unjustified-themes`, so its `all-themes` holds each entry twice. `assq`
    # takes the first, so it makes no difference — but it is what the Scheme
    # does, and the shape is worth preserving.
    function snag_avoidance_clause(themes, initial, target, explanation)
        isempty(themes) && return ""
        return string(", where ",
                      theme_phrases("", "and", "ing", themes, Any[], themes,
                                    initial, target, "", false, true, nothing, net),
                      " avoids a snag that would otherwise ",
                      "arise from the fact that ", explanation)
    end
    no_justification1 = string(
        "in the former case, there is no compelling reason ",
        theme_phrases("to ", "or", "", common_answer1_only_unjustified_themes,
                      snag_justified_themes1, unjustified_themes1,
                      initial1, target1, "", false, true, nothing, net),
        ", unlike in the latter case with ", initial2, " and ", target2,
        snag_avoidance_clause(intersect_themes(common_answer1_only_unjustified_themes,
                                               snag_justified_themes2),
                              initial2, target2, snag_explanation2))
    no_justification2 = string(
        "in the latter case, there is no compelling reason ",
        theme_phrases("to ", "or", "", common_answer2_only_unjustified_themes,
                      snag_justified_themes2, unjustified_themes2,
                      initial2, target2, "", false, true, nothing, net),
        ", unlike in the former case with ", initial1, " and ", target1,
        snag_avoidance_clause(intersect_themes(common_answer2_only_unjustified_themes,
                                               snag_justified_themes1),
                              initial1, target1, snag_explanation1))
    num_theme_differences = length(differing_dimensions) + length(unique_themes1) +
                            length(unique_themes2)
    theme_differences = num_theme_differences != 0
    # --- the rules
    rule1_clauses = self.top_rule_clauses
    rule2_clauses = other.top_rule_clauses
    rule1_abstractness = self.top_rule_abstractness
    rule2_abstractness = other.top_rule_abstractness
    rule_differences = compare_rule_clause_lists(rule1_clauses, rule2_clauses, net)
    num_rule_differences = rule_differences === nothing ? -1 :
        count(pair -> pair[1].conceptual_depth != pair[2].conceptual_depth,
              rule_differences)
    rule_differences_exist = num_rule_differences != 0
    rule_difference_phrase =
        rule_differences === nothing ? "in a completely different way" :
        rule1_abstractness > rule2_abstractness ? "in a more abstract way" :
        rule1_abstractness < rule2_abstractness ? "in a more literal way" :
            "somewhat differently"
    # In one branch answer2 is named before answer1, so if both answers are the
    # same string the ordinals have to swap with them.
    answer2_mentioned_first = theme_differences && isempty(answer1_only_themes)
    answer1_order = answer2_mentioned_first ? "second" : "first"
    answer2_order = answer2_mentioned_first ? "first" : "second"
    same_answer = answer1 == answer2
    answer1_ref = same_answer ? string("the ", answer1_order, " ", answer1) : answer1
    answer2_ref = same_answer ? string("the ", answer2_order, " ", answer2) : answer2
    rule_explanation(adjective, between) = string(
        adjective, " difference between ", between,
        " is that ", change1, " is viewed ", rule_difference_phrase, " for ",
        same_answer ? string("the ", answer1_order, " answer") :
                      string("the answer ", answer1),
        " than",
        change1 == change2 ? " it is" : string(" ", change2),
        " in ",
        same_answer ? string("the ", answer2_order, " answer's case") :
                      string("the case of ", answer2),
        ".")
    quality1 = self.quality
    quality2 = other.quality
    average_theme_abstractness1 = average_theme_abstractness(self, net)
    average_theme_abstractness2 = average_theme_abstractness(other, net)
    answer1_incoherent = answer_incoherent(self, net)
    answer2_incoherent = answer_incoherent(other, net)
    similarities(caveats::Bool) = string(
        "rely ",
        theme_phrases("on ", "and", "ing", common_themes, Any[],
                      all_unjustified_themes, nothing, nothing, "", caveats, false,
                      (initial1 == initial2 && target1 == target2) ?
                          string("(", initial1, " and ", target1, " in both cases)") :
                          string("(", initial1, " and ", target1,
                                 " in one case and ", initial2, " and ", target2,
                                 " in the other)"),
                      net))
    # --- the text itself
    parts = String[]
    if !theme_differences
        if !rule_differences_exist && !justification_differences
            push!(parts, string(
                "The answer ", answer1_phrase, " is essentially the same as the answer ",
                full_answer2, ".  Both answers ", similarities(true),
                ".  Furthermore, ",
                change1 == change2 ?
                    string(change1, " is viewed in essentially the same way in both cases") :
                    string(change1, " is viewed in essentially the same way as ", change2),
                "."))
        elseif !justification_differences
            push!(parts, string(rule_explanation("The only essential",
                                                 both_answers_phrase),
                                "  Both answers ", similarities(true), "."))
        elseif isempty(common_answer1_only_unjustified_themes)
            push!(parts, string("The answer ", answer1_phrase, " is similar to the answer ",
                                full_answer2, ", since both ", similarities(false),
                                ".  However, ", no_justification2, "."))
        elseif isempty(common_answer2_only_unjustified_themes)
            push!(parts, string("The answer ", answer1_phrase, " is similar to the answer ",
                                full_answer2, ", since both ", similarities(false),
                                ".  However, ", no_justification1, "."))
        else
            push!(parts, string("The answer ", answer1_phrase, " is similar to the answer ",
                                full_answer2, ", since both ", similarities(false),
                                ".  However, ", no_justification1, ".  Likewise, ",
                                no_justification2, "."))
        end
    elseif isempty(answer1_only_themes)
        push!(parts, string("The answer ", full_answer2, " is based ",
                            isempty(common_themes) ? "" : "in part ",
                            theme_phrases("on ", "and", "ing", answer2_only_themes,
                                          snag_justified_themes2, unjustified_themes2,
                                          initial2, target2, snag_explanation2,
                                          true, false, nothing, net), "."))
    elseif isempty(answer2_only_themes)
        push!(parts, string("The answer ", full_answer1, " is based ",
                            isempty(common_themes) ? "" : "in part ",
                            theme_phrases("on ", "and", "ing", answer1_only_themes,
                                          snag_justified_themes1, unjustified_themes1,
                                          initial1, target1, snag_explanation1,
                                          true, false, nothing, net), "."))
    else
        push!(parts, string("The answer ", full_answer1, " is based ",
                            isempty(common_themes) ? "" : "in part ",
                            theme_phrases("on ", "and", "ing", answer1_only_themes,
                                          snag_justified_themes1, unjustified_themes1,
                                          initial1, target1, snag_explanation1,
                                          true, false, nothing, net),
                            ", while the answer ", answer2_phrase, " is based ",
                            isempty(common_themes) ? "" : "in part ",
                            theme_phrases("on ", "and", "ing", answer2_only_themes,
                                          snag_justified_themes2, unjustified_themes2,
                                          initial2, target2, snag_explanation2,
                                          true, false, nothing, net), "."))
    end
    if !isempty(unique_themes1)
        push!(parts, string(
            (isempty(answer1_only_themes) || isempty(answer2_only_themes)) ?
                "  In contrast, in" : "  In", " ",
            isempty(answer2_only_themes) ?
                string("the case of the answer ", answer2_phrase) :
                string(answer2_ref, "'s case"),
            ", the idea ",
            theme_phrases("of ", "and", "ing", unique_themes1, snag_justified_themes1,
                          unjustified_themes1, initial2, target2, "", false, false,
                          nothing, net),
            " does not arise."))
    end
    if !isempty(unique_themes2)
        push!(parts, string(
            ((isempty(answer1_only_themes) || isempty(answer2_only_themes)) &&
             isempty(unique_themes1)) ? "  In contrast, in" : "  In", " ",
            isempty(answer1_only_themes) ?
                string("the case of the answer ", answer1_phrase) :
                string(answer1_ref, "'s case"),
            ", the idea ",
            theme_phrases("of ", "and", "ing", unique_themes2, snag_justified_themes2,
                          unjustified_themes2, initial1, target1, "", false, false,
                          nothing, net),
            " does not arise."))
    end
    if rule_differences_exist && (theme_differences || justification_differences)
        push!(parts, rule_explanation("  Another key",
                                      same_answer ?
                                          string("the two ", answer1, " answers") :
                                          "the answers"))
    end
    if answer1_incoherent
        push!(parts, string(
            "  The answer ", answer1,
            ", however, seems incoherent to me, since it involves seeing",
            length(all_themes1) > 1 ? " abstract similarities" : " an abstract similarity",
            " between ", initial1, " and ", target1, " (",
            theme_phrases("", "and", "ing", all_themes1, snag_justified_themes1,
                          unjustified_themes1, initial1, target1, "", false, false,
                          nothing, net),
            "), while at the same time viewing ", change1, " in a more literal way."))
    end
    if answer2_incoherent
        push!(parts, string(
            "  The answer ", answer2, answer1_incoherent ? " also" : ", however,",
            " seems incoherent", answer1_incoherent ? "" : " to me",
            ", since it involves seeing",
            length(all_themes2) > 1 ? " abstract similarities" : " an abstract similarity",
            " between ", initial2, " and ", target2, " (",
            theme_phrases("", "and", "ing", all_themes2, snag_justified_themes2,
                          unjustified_themes2, initial2, target2, "", false, false,
                          nothing, net),
            "), while at the same time viewing ", change2, " in a more literal way."))
    end
    # --- and which it prefers
    answer1_better(intro, reason) =
        string(intro, "I'd say ", answer1_ref, " is the better answer", reason, ".")
    answer2_better(intro, reason) =
        string(intro, "I'd say ", answer2_ref, " is the better answer", reason, ".")
    function neither_better(intro)
        q1 = answer_quality_phrase(quality1)
        q2 = answer_quality_phrase(quality2)
        q1 == q2 && return string(intro, "I'd say they're both ", q1, " answers.")
        return string(intro, "I'd say ", answer1_ref, " is ", q1, " and ",
                      answer2_ref, " is ", q2, ".")
    end
    verdict =
        if answer1_incoherent && answer2_incoherent
            if (average_theme_abstractness1 < average_theme_abstractness2 &&
                length(all_themes1) <= length(all_themes2)) ||
               (length(all_themes1) < length(all_themes2) &&
                average_theme_abstractness1 <= average_theme_abstractness2)
                answer1_better("  Overall, though, ",
                               string(", because it doesn't seem quite as incoherent as ",
                                      answer2_ref))
            elseif (average_theme_abstractness2 < average_theme_abstractness1 &&
                    length(all_themes2) <= length(all_themes1)) ||
                   (length(all_themes2) < length(all_themes1) &&
                    average_theme_abstractness2 <= average_theme_abstractness1)
                answer2_better("  Overall, though, ",
                               string(", because it doesn't seem quite as incoherent as ",
                                      answer1_ref))
            else
                neither_better("  All in all, ")
            end
        elseif !answer1_incoherent && answer2_incoherent
            answer1_better("  All in all, ", ", since it is more coherent")
        elseif !answer2_incoherent && answer1_incoherent
            answer2_better("  All in all, ", ", since it is more coherent")
        elseif length(unjustified_themes1) < length(unjustified_themes2)
            answer1_better("  All in all, ",
                           isempty(unjustified_themes1) ?
                               ", since it involves no unjustified ideas" :
                               ", since it involves fewer unjustified ideas")
        elseif length(unjustified_themes2) < length(unjustified_themes1)
            answer2_better("  All in all, ",
                           isempty(unjustified_themes2) ?
                               ", since it involves no unjustified ideas" :
                               ", since it involves fewer unjustified ideas")
        elseif !theme_differences && num_rule_differences != -1 &&
               rule1_abstractness > rule2_abstractness
            answer1_better("  All in all, ",
                           change1 == change2 ?
                               string(", since it involves seeing ", change1,
                                      " in a more abstract way") :
                               string(", since ", change1,
                                      " is seen in a more abstract way than ", change2))
        elseif !theme_differences && num_rule_differences != -1 &&
               rule2_abstractness > rule1_abstractness
            answer2_better("  All in all, ",
                           change1 == change2 ?
                               string(", since it involves seeing ", change2,
                                      " in a more abstract way") :
                               string(", since ", change2,
                                      " is seen in a more abstract way than ", change1))
        elseif length(all_themes1) > length(all_themes2)
            answer1_better("  All in all, ", ", since it is based on a richer set of ideas")
        elseif length(all_themes2) > length(all_themes1)
            answer2_better("  All in all, ", ", since it is based on a richer set of ideas")
        else
            neither_better("  All in all, ")
        end
    push!(parts, verdict)
    return join(parts)
end

"""`(compare-answers answer1 answer2)` — the comment window send, which is
graphics; the text is what matters."""
compare_answers(answer1::AnswerDescription, answer2::AnswerDescription, mem,
                net::Slipnet) = get_answer_comparison_text(answer1, answer2, mem, net)
