# Ported from Metacat's images.ss — the data structure only.
#
# An image is a compact description of an object's "shape": the letter it
# starts from, the facet it is bonded on, the letter and length relations
# running through it, its direction, and the images of its constituents. Groups
# build one at construction time.
#
# images.ss also contains the machinery for applying rule transforms to an
# image and instantiating the result. That belongs with rules.ss and is not
# ported yet; nothing in the workspace layers reads it.

mutable struct Image
    start_letter::Union{Nothing,Node}
    bond_facet::Union{Nothing,Node}
    letter_relation::Union{Nothing,Node}
    length_relation::Union{Nothing,Node}
    direction::Union{Nothing,Node}
    sub_images::Vector{Image}
end

make_image(start_letter, bond_facet, letter_relation, length_relation,
           direction, sub_images) =
    Image(start_letter, bond_facet, letter_relation, length_relation,
          direction, Image[s for s in sub_images])

"""`(make-letter-image letter-category)`."""
make_letter_image(letter_category::Node) =
    Image(letter_category, nothing, nothing, nothing, nothing, Image[])

is_letter_image(im::Image) = isempty(im.sub_images)
