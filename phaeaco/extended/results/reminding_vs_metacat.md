# Being reminded of a past answer: Metacat and PhaeacoX

Both FARG systems in this repository keep an episodic memory of answers, and
both can be reminded of an earlier one. They do it at opposite ends of
solving, and by different things.

| | Metacat (Marshall 1999, §5.2.3) | PhaeacoX X14 |
|---|---|---|
| when | after an answer is found | before solving, after the first look |
| reminded by | the answer: the themes it rests on and its rule | the problem: which kinds of thing its boxes show |
| distance | `calculate-answer-distance`: 1, + 1 per dimension held with different relations, + 2 per theme only one answer has, + 2 per rule difference | weighted difference of the fractions of boxes showing each kind of thing |
| strength | 100 − 100 · min(1, d / 5) | GCM over episodes grouped by answer (X13) |
| effect | commentary ("This answer strongly reminds me of …"); the memory also stops Metacat repeating an answer | the recalled answer is refitted to the new boxes (with slippage) and verified first |

To compare them, PhaeacoX was also given Metacat's kind of reminding (X18,
`answer_distance` in `src/solver/memory.jl`). An answer's theme is its
dimension, meaning the kind of idea, the kind of node and the feature's
concept (an object's area, a pair's `above`), plus the relation on that
dimension (its quantifier and direction). Its "rule" is the tags that name
which things it is about. The arithmetic is Metacat's. A different
dimension costs 2 + 2, so answers about different dimensions never remind
each other.

## Metacat, on the demo families

The reminding demos of `demos.ss`, 13 answers in three families, were run
through one memory in justify mode, with seven replications using
different seeds (`metacat/bench/reminding_families.jl`,
`metacat/results/reminding_families.txt`).

| pairs of answers | n | reminding > 0 | ≥ 40 | mean |
|---|---|---|---|---|
| same problem, different answer | 61 | 9.8% | 1.6% | 3.0 |
| same target string, different source | 91 | 31.9% | 20.9% | 17.6 |
| different target string | 370 | 11.1% | 9.7% | 4.9 |

Two answers to the same problem (xyz → xyd, wyz, dyz) almost never remind
Metacat of each other. The same kind of answer reached from another
source string does. "abc→abd, xyz→xyd" and "rst→rsu, xyz→xyu" do so in 7 of
7 replications, at 80. So do answers in different families built on the
same themes: the answers that lengthen something (mrrjjjj, aaabaaa,
aaabccc) remind each other in 5–6 of 7 replications.

## PhaeacoX, on Bongard's problems

The 100 problems were solved in order with the memory on, seeds 1–10. For
every pair of solved problems, the bench recorded how alike they look and
how alike their answers are (`bench/run_reminding.jl`,
`results/reminding_10.txt`). There were 7397 pairs.

| pairs of solved problems | n | answers alike (≥ 40) | same answer | mean reminding |
|---|---|---|---|---|
| look alike (d < 0.06; X14 can recall) | 231 | 5.2% | 2.6% | 3.9 |
| somewhat (0.06–0.12) | 1886 | 4.2% | 2.7% | 3.7 |
| look different (d ≥ 0.12) | 5280 | 1.8% | 1.1% | 1.7 |

- Looking alike makes alike answers 2.9 times as likely, but the rank
  correlation between the two distances is 0.07.
- Of the 186 pairs whose answers Metacat would find alike, X14 could recall
  6.5%.
- Of X14's 271 actual recalls, 5.9% led to an answer like the recalled one;
  93.7% to one Metacat would find unrelated. They cost little because the
  transfer is refitted and checked against the boxes before anything is
  verified (X14).
- The analogies X14 cannot see are the interesting ones. #22 (figures of
  equal size), #39 (lines nearly parallel) and #56 (same texture) are all
  answered "every X has the same Y": #22 ~ #39 and #39 ~ #56 remind each
  other at 40 in 5–6 of 10 seeds, though the problems look nothing alike. #11 ~ #76 (both elongation) and
  #9 ~ #86 (both core ends) are the same answer to different-looking
  problems.

## What the comparison says

In both systems, how alike two situations look says little about whether
their answers are analogous. Metacat's answers to the very same problem are
the least alike pairs; PhaeacoX's look-alike problems mostly have unrelated
answers. Reminding by appearance (PhaeacoX) is prospective and cheap, and
can steer a search, but it finds only the analogies whose problems share a
look (#36 → #37, #27 → #28). Reminding by answer (Metacat) recognises the deep
ones (sameness across sizes, slopes and textures; lengthening across letter
strings), but only once the answer is already found.

Foundalis's report puts the core between the two: "successive abstractions"
of a situation, down to what is "most abstract". PhaeacoX's problem core is
built from what is seen; Metacat's answer description from what was
understood. Neither alone is the report's core, which would let a new
problem remind of #22 because its *answer-to-be* is "sameness". One
direction this suggests is a problem core that includes the holistic
stage's candidate ideas (its salient differences between the sides), which
are the abstract part of a problem visible before it is solved.

## Also found

A bug of the original Metacat. `get-intrinsic-transforms` sends
`get-constituent-objects` to a letter, which only groups and strings
answer. It occurs in justify mode on `eqe qeq abbba`, answer `aaabaaa`, seed
2062194226, identically in Chez Scheme ("bad message") and in the port
(`MethodError`). It is recorded in `CONTINUE.md`, and the study counts it as
a failed try.
