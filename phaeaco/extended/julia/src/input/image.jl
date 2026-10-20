# Boxes and Bongard problems.
#
# A box is a BitMatrix indexed [y, x]: y grows downward, x rightward, both
# 1-based, `true` = foreground ("black"). That is the thesis's internal array
# of 0s and 1s after the background has been decided (§10.1.1).
#
# Geometry elsewhere uses (x, y) points in the same frame. Angles reported to
# the cognitive level are measured with y pointing *up*, so a line rising to
# the right has a slope of 45°, as a person would say.

const BOXSIZE = 100

"""A Bongard problem: six boxes on the left (1:6), six on the right (7:12)."""
struct BP
    name::String
    boxes::Vector{BitMatrix}
    left_label::String          # the expected solution, when known
    right_label::String
end

BP(name, boxes) = BP(name, boxes, "", "")

leftboxes(bp::BP) = bp.boxes[1:6]
rightboxes(bp::BP) = bp.boxes[7:12]
side_of(i::Integer) = i <= 6 ? :left : :right
"""Foundalis's labels: I-A … I-F on the left, II-A … II-F on the right."""
boxlabel(i::Integer) = string(i <= 6 ? "I-" : "II-", 'A' + (i - 1) % 6)

# --- PBM ------------------------------------------------------------------
#
# Plain (P1) PBM: human-readable, diff-friendly, and needs no image library.
# A BP is stored as one 100 × 1200 image, its twelve boxes stacked top to
# bottom in order I-A … I-F, II-A … II-F, with the labels in a comment.

function write_pbm(io::IO, img::AbstractMatrix{Bool}; comment::AbstractString="")
    h, w = size(img)
    println(io, "P1")
    for line in split(comment, '\n')
        isempty(line) || println(io, "# ", line)
    end
    println(io, w, ' ', h)
    for y in 1:h
        for x in 1:w
            print(io, img[y, x] ? '1' : '0')
            (x % 70 == 0 && x < w) && println(io)
        end
        println(io)
    end
end

write_pbm(path::AbstractString, img; kw...) = open(io -> write_pbm(io, img; kw...), path, "w")

"""Read a P1 or P4 PBM. Returns (image, comment lines)."""
function read_pbm(path::AbstractString)
    data = read(path)
    pos = 1
    comments = String[]
    function token()
        while true
            while pos <= length(data) && isspace(Char(data[pos]))
                pos += 1
            end
            if pos <= length(data) && data[pos] == UInt8('#')
                s = pos
                while pos <= length(data) && data[pos] != UInt8('\n')
                    pos += 1
                end
                push!(comments, strip(String(data[s+1:pos-1])))
                continue
            end
            break
        end
        s = pos
        while pos <= length(data) && !isspace(Char(data[pos]))
            pos += 1
        end
        return String(data[s:pos-1])
    end
    magic = token()
    w = parse(Int, token())
    h = parse(Int, token())
    img = falses(h, w)
    if magic == "P1"
        i = 0
        while i < w * h && pos <= length(data)
            c = data[pos]
            pos += 1
            if c == UInt8('0') || c == UInt8('1')
                img[i ÷ w + 1, i % w + 1] = c == UInt8('1')
                i += 1
            end
        end
    elseif magic == "P4"
        pos += 1                        # the single whitespace after the header
        rowbytes = cld(w, 8)
        for y in 1:h, x in 1:w
            byte = data[pos + (y - 1) * rowbytes + (x - 1) ÷ 8]
            img[y, x] = (byte >> (7 - (x - 1) % 8)) & 0x01 == 0x01
        end
    else
        error("$path: not a PBM (magic $magic)")
    end
    return img, comments
end

function save_bp(path::AbstractString, bp::BP)
    sheet = vcat(bp.boxes...)
    comment = "BP $(bp.name)\nleft: $(bp.left_label)\nright: $(bp.right_label)"
    write_pbm(path, sheet; comment=comment)
end

function load_bp(path::AbstractString)
    img, comments = read_pbm(path)
    size(img) == (12 * BOXSIZE, BOXSIZE) ||
        error("$path: expected a 100×1200 stack of twelve boxes, got $(size(img))")
    boxes = [BitMatrix(img[(i-1)*BOXSIZE+1:i*BOXSIZE, :]) for i in 1:12]
    name, left, right = splitext(basename(path))[1], "", ""
    for c in comments
        startswith(c, "BP ") && (name = c[4:end])
        startswith(c, "left: ") && (left = c[7:end])
        startswith(c, "right: ") && (right = c[8:end])
    end
    return BP(name, boxes, left, right)
end

"""
Lay a BP out the way it is printed — left side in two columns of three,
right side likewise, with gutters — for looking at. Returns a BitMatrix where
`true` is black; box frames are drawn.
"""
function sheet_image(bp::BP; gap::Int=8, midgap::Int=24)
    W = 4 * BOXSIZE + 2 * gap + midgap + 2 * gap
    H = 3 * BOXSIZE + 4 * gap
    img = falses(H, W)
    for i in 1:12
        k = (i - 1) % 6                       # 0..5 within the side
        row, col = k ÷ 2, k % 2
        x0 = gap + col * (BOXSIZE + gap) + (i > 6 ? 2 * (BOXSIZE + gap) + midgap - gap : 0)
        y0 = gap + row * (BOXSIZE + gap)
        img[y0+1:y0+BOXSIZE, x0+1:x0+BOXSIZE] .= bp.boxes[i]
        img[y0, x0:x0+BOXSIZE+1] .= true
        img[y0+BOXSIZE+1, x0:x0+BOXSIZE+1] .= true
        img[y0:y0+BOXSIZE+1, x0] .= true
        img[y0:y0+BOXSIZE+1, x0+BOXSIZE+1] .= true
    end
    return img
end

# --- Background (§10.1.1) ---------------------------------------------------

"""
Given a two-colour image as a Bool matrix of "is colour A", decide which
colour is the background: the one making up more than half of a frame whose
thickness is 5% of the width and height. Returns the foreground mask.
"""
function foreground_mask(isA::AbstractMatrix{Bool})
    h, w = size(isA)
    fy, fx = max(1, round(Int, 0.05h)), max(1, round(Int, 0.05w))
    a = total = 0
    for y in 1:h, x in 1:w
        if y <= fy || y > h - fy || x <= fx || x > w - fx
            total += 1
            a += isA[y, x]
        end
    end
    return a * 2 > total ? .!isA : BitMatrix(isA)
end
