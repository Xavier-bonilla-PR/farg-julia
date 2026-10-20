# Julia counterpart of metacat/bench/metacat_images_probe.ss: exhaustive dump of
# the image transform algebra.
include("../../copycat/julia/src/pyrandom.jl")  # shared MT19937 (Copycat side)
include("../julia/src/schemenum.jl")
include("../julia/src/utilities.jl")
include("../julia/src/slipnet.jl")
include("../julia/src/workspace.jl")
include("../julia/src/concept_mappings.jl")
include("../julia/src/images.jl")

nm(n) = n === nothing ? "-" : n.lowercase_name
net = build_slipnet()
const ID = net[:plato_identity]

"""render the nested letter structure (generate) as a flat readable string"""
render(g) = g === nothing ? "-" :
            g isa AbstractVector ? string("(", join([string(render(x), " ") for x in g]), ")") :
            g.lowercase_name

show_image(im::Image) =
    string("[", nm(im.start_letter), " ", nm(im.bond_facet), " ",
           nm(im.letter_relation), " ", nm(im.length_relation), " ",
           nm(im.direction), " n=", length(im.sub_images), " ", render(generate(im)), "]")

"""build an image for a run of letters under a relation, in a direction"""
function run_image(start::Node, relation::Node, n::Int, direction::Node, facet::Node)
    letters = Node[]
    cur = start
    for k in 0:(n - 1)
        push!(letters, cur)
        k + 1 < n && (cur = get_related_node(cur, relation, ID)::Node)
    end
    return make_image(letters[1], facet, relation, ID, direction,
                      Image[make_letter_image(l) for l in letters])
end

"""a group of groups: ((a) (b b) (c c c)) style"""
function nested_image(specs, relation::Node, direction::Node, facet::Node)
    subs = Image[run_image(sp[1], ID, sp[2], net[:plato_right],
                           net[:plato_letter_category]) for sp in specs]
    return make_image(subs[1].start_letter, facet, relation,
                      relationship_between(Union{Nothing,Node}[get_length(s, net)
                                                               for s in subs], ID),
                      direction, subs)
end

images() = [
    ("a", make_letter_image(net[:plato_a])),
    ("z", make_letter_image(net[:plato_z])),
    ("abc", run_image(net[:plato_a], net[:plato_successor], 3, net[:plato_right],
                      net[:plato_letter_category])),
    ("cba", run_image(net[:plato_c], net[:plato_predecessor], 3, net[:plato_right],
                      net[:plato_letter_category])),
    ("abc-left", run_image(net[:plato_a], net[:plato_successor], 3, net[:plato_left],
                           net[:plato_letter_category])),
    ("xyz", run_image(net[:plato_x], net[:plato_successor], 3, net[:plato_right],
                      net[:plato_letter_category])),
    ("aaa", run_image(net[:plato_a], net[:plato_identity], 3, net[:plato_right],
                      net[:plato_letter_category])),
    ("ab", run_image(net[:plato_a], net[:plato_successor], 2, net[:plato_right],
                     net[:plato_letter_category])),
    ("abcde", run_image(net[:plato_a], net[:plato_successor], 5, net[:plato_right],
                        net[:plato_letter_category])),
    ("a-bb-ccc", nested_image([(net[:plato_a], 1), (net[:plato_b], 2), (net[:plato_c], 3)],
                              net[:plato_successor], net[:plato_right], net[:plato_length])),
    ("aa-bb", nested_image([(net[:plato_a], 2), (net[:plato_b], 2)],
                           net[:plato_successor], net[:plato_right],
                           net[:plato_letter_category])),
]

const TRANSFORMS = [
    ("letter", (im, f) -> letter!(im, net, f)),
    ("group", (im, f) -> group!(im, net, f)),
    ("rev-dir", (im, f) -> reverse_direction!(im, net, f)),
    ("rev-med-lett", (im, f) -> reverse_medium!(im, net[:plato_letter_category], net, f)),
    ("rev-med-len", (im, f) -> reverse_medium!(im, net[:plato_length], net, f)),
    ("start-succ", (im, f) -> new_start_letter!(im, net[:plato_successor], net, f)),
    ("start-pred", (im, f) -> new_start_letter!(im, net[:plato_predecessor], net, f)),
    ("start-iden", (im, f) -> new_start_letter!(im, net[:plato_identity], net, f)),
    ("start-m", (im, f) -> new_start_letter!(im, net[:plato_m], net, f)),
    ("start-a", (im, f) -> new_start_letter!(im, net[:plato_a], net, f)),
    ("start-none", (im, f) -> new_start_letter!(im, nothing, net, f)),
    ("len-succ", (im, f) -> new_length!(im, net[:plato_successor], net, f)),
    ("len-pred", (im, f) -> new_length!(im, net[:plato_predecessor], net, f)),
    ("len-one", (im, f) -> new_length!(im, net[:plato_one], net, f)),
    ("len-two", (im, f) -> new_length!(im, net[:plato_two], net, f)),
    ("len-four", (im, f) -> new_length!(im, net[:plato_four], net, f)),
    ("len-five", (im, f) -> new_length!(im, net[:plato_five], net, f)),
    ("alpha-first",
     (im, f) -> new_alpha_position_category!(im, net[:plato_alphabetic_first], net, f)),
    ("alpha-last",
     (im, f) -> new_alpha_position_category!(im, net[:plato_alphabetic_last], net, f)),
    ("alpha-opp",
     (im, f) -> new_alpha_position_category!(im, net[:plato_opposite], net, f)),
    ("singleton", (im, f) -> letter_to_singleton_group!(im, net, f)),
    ("shorten", (im, f) -> shorten!(im, net, f)),
    ("extend-succ-iden",
     (im, f) -> extend!(im, net[:plato_successor], net[:plato_identity], net, f)),
    ("extend-iden-succ",
     (im, f) -> extend!(im, net[:plato_identity], net[:plato_successor], net, f)),
]

"""Run a transform, reporting the tag the Scheme's escape continuation would."""
function attempt(tag, body)
    try
        return body()
    catch e
        e isa ImageTransformFailure || rethrow()
        return tag
    end
end

# single transforms
for (tname, proc) in TRANSFORMS
    for (iname, base) in images()
        im = copy_image(base)
        result = attempt("FAIL", () -> (proc(im, () -> throw(ImageTransformFailure(tname)));
                                        show_image(im)))
        println("T1\t", tname, "\t", iname, "\t", result)
    end
end

# pairs of transforms, to catch order-dependent behaviour
for (n1, p1) in TRANSFORMS[[1, 2, 12, 13, 21]]
    for (n2, p2) in TRANSFORMS
        for (iname, base) in images()
            im = copy_image(base)
            result = try
                p1(im, () -> throw(ImageTransformFailure(1)))
                p2(im, () -> throw(ImageTransformFailure(2)))
                show_image(im)
            catch e
                e isa ImageTransformFailure ? string("FAIL", e.detail) : rethrow()
            end
            println("T2\t", n1, "\t", n2, "\t", iname, "\t", result)
        end
    end
end

# state save / restore / reset
for (iname, base) in images()
    im = copy_image(base)
    saved = get_state(im)
    attempt("x", () -> new_length!(im, net[:plato_four], net,
                                   () -> throw(ImageTransformFailure(:x))))
    println("ST\t", iname, "\tafter\t", show_image(im))
    new_state!(im, saved)
    println("ST\t", iname, "\trestored\t", show_image(im))
    attempt("x", () -> new_start_letter!(im, net[:plato_successor], net,
                                         () -> throw(ImageTransformFailure(:x))))
    reset_image!(im)
    println("ST\t", iname, "\treset\t", show_image(im))
end

# walks and lengths
for (iname, im) in images()
    leaves = String[]
    interiors = Int[]
    leaf_walk(i -> push!(leaves, nm(i.start_letter)), im)
    postorder_interior_walk(i -> push!(interiors, length(i.sub_images)), im)
    println("W\t", iname, "\t(", join(leaves, " "), ")\t(", join(interiors, " "), ")\t",
            nm(get_length(im, net)), "\t", is_letter_image(im) ? "leaf" : "node")
end

# change-length-first? and enumerate, directly
for len_arg in (net[:plato_predecessor], net[:plato_successor], net[:plato_identity],
                net[:plato_one], net[:plato_two], net[:plato_four])
    for cur in (net[:plato_one], net[:plato_two], net[:plato_three], net[:plato_five],
                nothing)
        println("CLF\t", nm(len_arg), "\t", nm(cur), "\t",
                change_length_first(len_arg, cur, net) ? "y" : "n")
    end
end

for (start, relation, n) in ((net[:plato_a], net[:plato_successor], 3),
                             (net[:plato_x], net[:plato_successor], 3),
                             (net[:plato_x], net[:plato_successor], 4),
                             (net[:plato_a], net[:plato_predecessor], 2),
                             (net[:plato_c], net[:plato_predecessor], 3),
                             (net[:plato_a], net[:plato_identity], 4),
                             (net[:plato_a], nothing, 1),
                             (net[:plato_a], nothing, 2),
                             (net[:plato_one], net[:plato_successor], 3),
                             (net[:plato_four], net[:plato_successor], 3))
    result = attempt("FAIL",
                     () -> string("(", join([nm(x) for x in
                                             enumerate_letters(start, relation, n, net,
                                                 () -> throw(ImageTransformFailure(:e)))],
                                            " "), ")"))
    println("EN\t", nm(start), "\t", nm(relation), "\t", n, "\t", result)
end
