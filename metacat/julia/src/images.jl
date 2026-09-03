# Ported from Metacat's images.ss.
#
# An image is a compact description of an object's "shape": the letter it starts
# from, the facet it is bonded on, the letter and length relations running
# through it, its direction, and the images of its constituents. Groups build one
# at construction time.
#
# The second half of this file is the algebra rules.ss works in. A rule is a set
# of TRANSFORMS — "letter-category becomes its successor", "length becomes
# three", "reverse the group" — and applying a rule means applying those
# transforms to the image of an object and reading the result back out. The
# transforms mutate the image in place and are meant to be undone: `get_state`
# and `new_state` snapshot and restore, and `reset` puts an image back to how it
# was built.
#
# Every transform takes a `fail` thunk, called when the transform cannot be
# carried out at all — z has no successor, a two-letter group cannot be
# shortened twice. In the Scheme that thunk is an escape continuation that
# abandons the whole rule; here it throws, which is the same thing.
#
# Deferred: `make-string-image`, which rules.ss uses for whole-string images, and
# `instantiate-as-letter` / `instantiate-as-group`, which need the answer string
# that answers.ss builds. Both come with those layers.

mutable struct Image
    start_letter::Union{Nothing,Node}
    bond_facet::Union{Nothing,Node}
    letter_relation::Union{Nothing,Node}
    length_relation::Union{Nothing,Node}
    direction::Union{Nothing,Node}
    sub_images::Vector{Image}
    """Set by the rule and answer layers; only `reset` touches them here."""
    swapped_image::Union{Nothing,Image}
    instantiated_object::Union{Nothing,WSObject}
    """The state the image was built with, restored by `reset`."""
    original_state::Any
end

function make_image(start_letter, bond_facet, letter_relation, length_relation,
                    direction, sub_images)
    subs = Image[s for s in sub_images]
    im = Image(start_letter, bond_facet, letter_relation, length_relation,
               direction, subs, nothing, nothing, nothing)
    im.original_state = get_state(im)
    return im
end

"""`(make-letter-image letter-category)`."""
make_letter_image(letter_category::Node) =
    make_image(letter_category, nothing, nothing, nothing, nothing, Image[])

is_letter_image(im::Image) = isempty(im.sub_images)

get_length(im::Image, net::Slipnet) =
    is_letter_image(im) ? net[:plato_one] :
                          number_to_platonic_number(net, length(im.sub_images))

# --- state ------------------------------------------------------------------

"""`(get-state)` — a snapshot a later `new-state` can restore. The sub-image
VECTOR is captured by reference, which is safe because every transform that
changes the constituents replaces the vector rather than mutating it."""
get_state(im::Image) = (im.start_letter, im.bond_facet, im.letter_relation,
                        im.length_relation, im.direction, im.sub_images)

function new_state!(im::Image, state)
    im.start_letter, im.bond_facet, im.letter_relation,
    im.length_relation, im.direction, im.sub_images = state
    return im
end

"""`(reset)` — back to how the image was built, recursively."""
function reset_image!(im::Image)
    new_state!(im, im.original_state)
    im.swapped_image = nothing
    im.instantiated_object = nothing
    foreach(reset_image!, im.sub_images)
    return im
end

copy_image(im::Image) =
    make_image(im.start_letter, im.bond_facet, im.letter_relation,
               im.length_relation, im.direction, Image[copy_image(s)
                                                       for s in im.sub_images])

# --- reading an image out ---------------------------------------------------

"""`(generate)` — the nested letter structure the image describes, read in its
own direction."""
generate(im::Image) =
    is_letter_image(im) ? im.start_letter :
    im.direction === nothing ? Any[generate(s) for s in im.sub_images] :
    Any[generate(s) for s in ordered_sub_images(im)]

"""Sub-images in reading order: a leftward group is stored left-to-right but
read right-to-left."""
ordered_sub_images(im::Image) =
    im.direction !== nothing && im.direction.name === :plato_left ?
    reverse(im.sub_images) : im.sub_images

"""`(leaf-walk action)` — the letters of the image, in reading order."""
function leaf_walk(action, im::Image)
    if is_letter_image(im)
        action(im)
    else
        for s in ordered_sub_images(im)
            leaf_walk(action, s)
        end
    end
    return im
end

"""`(postorder-interior-walk action)` — every non-letter image, children first."""
function postorder_interior_walk(action, im::Image)
    is_letter_image(im) && return im
    for s in ordered_sub_images(im)
        postorder_interior_walk(action, s)
    end
    action(im)
    return im
end

# --- the transforms ---------------------------------------------------------

"""Thrown by a transform that cannot be carried out. `apply-transforms` in
rules.ss catches it and abandons the whole rule."""
struct ImageTransformFailure <: Exception
    detail::Any
end

"""`(reverse-direction)`."""
reverse_direction!(im::Image, net::Slipnet, fail) =
    (im.direction = inverse(im.direction, net); im)

"""`(replace-all method-name new-args fail)` — apply a transform to each
sub-image with its own argument."""
function replace_all!(transform!, im::Image, new_args, net::Slipnet, fail)
    chez_map((s, arg) -> transform!(s, arg, net, fail), im.sub_images, new_args)
    return im
end

"""`(reverse-medium medium fail)` — turn the group around in one medium only:
the letters run the other way, or the lengths do. This is what expresses
`succgrp` becoming `predgrp`."""
function reverse_medium!(im::Image, medium::Node, net::Slipnet, fail)
    is_letter_image(im) && return im
    if medium === net[:plato_letter_category]
        letters = Union{Nothing,Node}[s.start_letter for s in im.sub_images]
        replace_all!(new_start_letter!, im, reverse(letters), net, fail)
        im.letter_relation = inverse(im.letter_relation, net)
        im.start_letter = letters[end]
    elseif medium === net[:plato_length]
        lengths = Union{Nothing,Node}[get_length(s, net) for s in im.sub_images]
        replace_all!(new_length!, im, reverse(lengths), net, fail)
        im.length_relation = inverse(im.length_relation, net)
    end
    return im
end

"""`(new-alpha-position-category arg fail)` — "make it start at the beginning of
the alphabet", or at the end, or swap whichever end it is at."""
function new_alpha_position_category!(im::Image, arg::Union{Nothing,Node}, net::Slipnet,
                                      fail)
    if arg === net[:plato_alphabetic_first] ||
       (arg === net[:plato_opposite] && im.start_letter === net[:plato_z])
        return new_start_letter!(im, net[:plato_a], net, fail)
    elseif arg === net[:plato_alphabetic_last] ||
           (arg === net[:plato_opposite] && im.start_letter === net[:plato_a])
        return new_start_letter!(im, net[:plato_z], net, fail)
    end
    fail()
end

"""`(new-start-letter arg fail)` — arg is either a relation to slide by or a
letter to land on. NB when a RELATION is applied to a group image, the group's
own start letter is slid without checking the result, so it can legitimately
become nothing."""
function new_start_letter!(im::Image, arg::Union{Nothing,Node}, net::Slipnet, fail)
    arg === nothing && fail()
    a = arg::Node
    if is_letter_image(im)
        if platonic_relation(a, net)
            new_letter = get_related_node(im.start_letter::Node, a, net[:plato_identity])
            new_letter === nothing && fail()
            im.start_letter = new_letter
        else
            im.start_letter = a
        end
    elseif platonic_relation(a, net)
        # `tell-all`, i.e. Chez's `map`: applied from the END of the list, in
        # pairs. Only shows when one sub-image's slide fails and the ones the
        # Scheme had not reached yet must be left alone.
        chez_map(s -> new_start_letter!(s, a, net, fail), im.sub_images)
        im.start_letter = get_related_node(im.start_letter::Node, a, net[:plato_identity])
    elseif platonic_letter(a, net)
        new_letters = enumerate_letters(a, im.letter_relation, length(im.sub_images),
                                        net, fail)
        replace_all!(new_start_letter!, im, new_letters, net, fail)
        im.start_letter = a
    end
    return im
end

"""`(new-length arg fail)` — arg is a relation or a platonic number. A letter
image becomes a singleton group first, since only groups have a length to
change."""
function new_length!(im::Image, arg::Union{Nothing,Node}, net::Slipnet, fail)
    arg === nothing && fail()
    a = arg::Node
    (a === net[:plato_identity] ||
     (platonic_number(a, net) && get_length(im, net) === a)) && return im
    if is_letter_image(im)
        letter_to_singleton_group!(im, net, fail)
        return new_length!(im, a, net, fail)
    elseif a === net[:plato_predecessor]
        return shorten!(im, net, fail)
    elseif a === net[:plato_successor]
        return extend!(im, im.letter_relation, im.length_relation, net, fail)
    elseif platonic_number(a, net)
        n = platonic_number_to_number(a, net)::Int
        len = length(im.sub_images)
        if n <= len
            for _ in 1:(len - n)
                shorten!(im, net, fail)
            end
        else
            for _ in 1:(n - len)
                extend!(im, im.letter_relation, im.length_relation, net, fail)
            end
        end
        return im
    end
    fail()
end

"""`(shorten fail)` — drop the last constituent. NB both relation repairs sit in
the body of the SAME `if*`, so they happen together once more than one
constituent is left, rather than being an either/or."""
function shorten!(im::Image, net::Slipnet, fail)
    length(im.sub_images) < 2 && fail()
    im.sub_images = im.sub_images[1:(end - 1)]
    if length(im.sub_images) > 1
        if im.letter_relation === nothing
            im.letter_relation = relationship_between(
                Union{Nothing,Node}[s.start_letter for s in im.sub_images],
                net[:plato_identity])
        end
        if im.length_relation === nothing
            im.length_relation = relationship_between(
                Union{Nothing,Node}[get_length(s, net) for s in im.sub_images],
                net[:plato_identity])
        end
    end
    return im
end

"""`(extend letter-arg length-arg fail)` — add one more constituent, made by
carrying the last one forward. Which of the two changes goes first matters:
shrinking a length before changing its letters avoids enumerating letters that
are about to be thrown away."""
function extend!(im::Image, letter_arg::Union{Nothing,Node},
                 length_arg::Union{Nothing,Node}, net::Slipnet, fail)
    if is_letter_image(im)
        letter_to_singleton_group!(im, net, fail)
        return extend!(im, letter_arg, length_arg, net, fail)
    end
    new_image = copy_image(im.sub_images[end])
    if change_length_first(length_arg, get_length(new_image, net), net)
        new_length!(new_image, length_arg, net, fail)
        new_start_letter!(new_image, letter_arg, net, fail)
    else
        new_start_letter!(new_image, letter_arg, net, fail)
        new_length!(new_image, length_arg, net, fail)
    end
    im.sub_images = vcat(im.sub_images, Image[new_image])
    im.letter_relation = relationship_between(
        Union{Nothing,Node}[s.start_letter for s in im.sub_images], net[:plato_identity])
    im.length_relation = relationship_between(
        Union{Nothing,Node}[get_length(s, net) for s in im.sub_images],
        net[:plato_identity])
    return im
end

"""`(letter fail)` — collapse the image to a bare letter. A length-bonded group
cannot be collapsed: its letters are not what it is about."""
function letter!(im::Image, net::Slipnet, fail)
    is_letter_image(im) && return im
    im.bond_facet === net[:plato_length] && fail()
    im.bond_facet = nothing
    im.letter_relation = nothing
    im.length_relation = nothing
    im.direction = nothing
    im.sub_images = Image[]
    return im
end

"""`(group fail)`."""
group!(im::Image, net::Slipnet, fail) =
    is_letter_image(im) ? letter_to_singleton_group!(im, net, fail) : im

"""`(letter->singleton-group fail)` — wrap a letter image in a group of one."""
function letter_to_singleton_group!(im::Image, net::Slipnet, fail)
    sub_image = copy_image(im)
    im.bond_facet = net[:plato_letter_category]
    im.letter_relation = net[:plato_identity]
    im.length_relation = net[:plato_identity]
    im.direction = net[:plato_right]
    im.sub_images = Image[sub_image]
    return new_length!(im, net[:plato_one], net, fail)
end

"""`(change-length-first? length-arg current-length)`."""
change_length_first(length_arg::Union{Nothing,Node}, current_length::Union{Nothing,Node},
                    net::Slipnet) =
    length_arg === net[:plato_predecessor] ||
    (length_arg !== nothing && platonic_number(length_arg::Node, net) &&
     (current_length === nothing ||
      platonic_number_to_number(length_arg::Node, net)::Int <
      platonic_number_to_number(current_length::Node, net)::Int))

"""`(enumerate start relation n fail)` — the run of n nodes starting at `start`
and stepping by `relation`. A run longer than one needs a relation to step by,
and fails if the run walks off the end of the alphabet."""
function enumerate_letters(start::Node, relation::Union{Nothing,Node}, n::Int,
                           net::Slipnet, fail)
    (n > 1 && relation === nothing) && fail()
    result = Union{Nothing,Node}[start]
    current = start
    for _ in 2:n
        next = get_related_node(current, relation, net[:plato_identity])
        next === nothing && fail()
        current = next::Node
        push!(result, current)
    end
    return result
end

# --- the string image -------------------------------------------------------
#
# A workspace string's image is NOT an `Image`: it has no start letter, no
# relations and no length of its own, and it reads its sub-images straight off
# the string's top-level objects each time it is asked, so building a group
# changes what the string image is made of. It answers the same messages, so
# rule application treats the two alike. Its one extra trick is `new-appearance`,
# which a verbatim rule uses to replace the string wholesale with a fixed list
# of letters.

mutable struct StringImage
    string::Any                    # the WorkspaceString it belongs to
    direction::Node
    # `reset` puts the direction back to `plato-right`, which the Scheme reads
    # from the global; the constructor is only ever called with it, so the
    # string image keeps its own handle on the node.
    plato_right::Node
    verbatim_images::Vector{Image}
    verbatim::Bool
end

make_string_image(string, direction::Node) =
    StringImage(string, direction, direction, Image[], false)

"""`(get-sub-images)` — read off the string's constituent objects, unless a
verbatim appearance has been imposed."""
sub_images(si::StringImage) =
    si.verbatim ? si.verbatim_images :
    Image[get_image(o) for o in get_constituent_objects(si.string)]

ordered_sub_images(si::StringImage) =
    si.direction.name === :plato_right ? sub_images(si) : reverse(sub_images(si))

generate(si::StringImage) = Any[generate(im) for im in ordered_sub_images(si)]

function reset_image!(si::StringImage)
    si.verbatim = false
    # NB the direction is reset BEFORE the sub-images are read, so the reset
    # walks the string's objects left to right whatever direction it was in.
    si.direction = si.plato_right
    for im in sub_images(si)
        reset_image!(im)
    end
    return si
end

leaf_walk(action, si::StringImage) =
    (foreach(im -> leaf_walk(action, im), ordered_sub_images(si)); si)
postorder_interior_walk(action, si::StringImage) =
    (foreach(im -> postorder_interior_walk(action, im), ordered_sub_images(si)); si)

get_length(si::StringImage, net::Slipnet) =
    number_to_platonic_number(net, length(sub_images(si)))

new_start_letter!(si::StringImage, arg::Union{Nothing,Node}, net::Slipnet, fail) =
    (foreach(im -> new_start_letter!(im, arg, net, fail), sub_images(si)); si)

"""NB the Scheme really does send `new-start-letter`, not
`new-alpha-position-category`, to each sub-image here."""
new_alpha_position_category!(si::StringImage, arg::Union{Nothing,Node}, net::Slipnet,
                             fail) =
    (foreach(im -> new_start_letter!(im, arg, net, fail), sub_images(si)); si)

new_length!(si::StringImage, arg::Union{Nothing,Node}, net::Slipnet, fail) = fail()

"""`(new-appearance letter-categories)` — what a verbatim rule does to a
string."""
function new_appearance!(si::StringImage, letter_categories, net::Slipnet)
    si.verbatim_images = Image[make_letter_image(c) for c in letter_categories]
    si.direction = net[:plato_right]
    si.verbatim = true
    return si
end

reverse_direction!(si::StringImage, net::Slipnet, fail) =
    (si.direction = inverse(si.direction, net)::Node; si)

function reverse_medium!(si::StringImage, medium::Node, net::Slipnet, fail)
    if medium === net[:plato_letter_category]
        letters = Union{Nothing,Node}[im.start_letter for im in sub_images(si)]
        replace_all!(new_start_letter!, si, reverse(letters), net, fail)
    elseif medium === net[:plato_length]
        lengths = Union{Nothing,Node}[get_length(im, net) for im in sub_images(si)]
        replace_all!(new_length!, si, reverse(lengths), net, fail)
    end
    return si
end

function replace_all!(transform!, si::StringImage, new_args, net::Slipnet, fail)
    chez_map((im, arg) -> transform!(im, arg, net, fail), sub_images(si), new_args)
    return si
end

letter!(si::StringImage, net::Slipnet, fail) = fail()
group!(si::StringImage, net::Slipnet, fail) = fail()
