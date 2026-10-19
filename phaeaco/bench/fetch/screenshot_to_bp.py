"""Convert a screenshot of a Bongard problem page (Foundalis's site renders
the BP GIF at native size) into the 100x1200 PBM stack PhaeacoJL reads.

    python3 screenshot_to_bp.py SHOT.png OUT.pbm NUMBER [LEFT RIGHT]

LEFT and RIGHT label the sides; without them, the built-in labels below are
used (for the fifteen BPs of Appendix A).

Each box is a 100x100 frame with a one-pixel border and a drop shadow. The
98x98 interior is padded with one white pixel all round to 100x100. Boxes
are ordered as Foundalis labels them: left page I-A..I-F row by row, then
the right page II-A..II-F.

This is a data-preparation tool, kept outside the Julia package (which uses
only the standard library); it needs Pillow.
"""
import sys
from PIL import Image

def boxes(path):
    im = Image.open(path).convert('L')
    W, H = im.size
    px = im.load()
    blk = lambda x, y: 0 <= x < W and 0 <= y < H and px[x, y] < 100
    tops = []
    for y in range(1, H):
        x = 0
        while x < W:
            if blk(x, y):
                s = x
                while x < W and blk(x, y):
                    x += 1
                # a top edge: exactly 100 long, white above, a vertical edge down each side
                if 99 <= x - s <= 101 and not any(blk(i, y - 1) for i in range(s, x)) \
                        and all(blk(s, y + k) for k in range(1, 99)) and all(blk(x - 1, y + k) for k in range(1, 99)):
                    tops.append((y, s))
            else:
                x += 1
    if len(tops) != 12:
        raise SystemExit(f"{path}: found {len(tops)} boxes, expected 12")
    xs = sorted(set(s for _, s in tops))
    mid = (xs[1] + xs[2]) / 2                         # between the two pages
    left = sorted([t for t in tops if t[1] < mid])
    right = sorted([t for t in tops if t[1] > mid])
    out = []
    for page in (left, right):
        for y, s in sorted(page, key=lambda t: (t[0], t[1])):
            b = [[False] * 100 for _ in range(100)]
            for yy in range(98):
                for xx in range(98):
                    b[yy + 1][xx + 1] = blk(s + 1 + xx, y + 1 + yy)
            out.append(b)
    return out

def write_pbm(path, bxs, number, left, right):
    with open(path, 'w') as f:
        f.write(f"P1\n# BP {number}\n# left: {left}\n# right: {right}\n100 1200\n")
        for b in bxs:
            for row in b:
                f.write(''.join('1' if v else '0' for v in row) + '\n')

LABELS = {
    1: ("empty box", "something in the box"),
    2: ("large figures", "small figures"),
    3: ("outlined figures", "filled figures"),
    4: ("convex figures", "concave figures"),
    5: ("polygons", "curved figures"),
    6: ("triangles", "quadrilaterals"),
    8: ("figures on the right", "figures on the left"),
    11: ("elongated figures", "not elongated figures"),
    15: ("closed figures", "open figures"),
    21: ("a small figure present", "no small figure"),
    22: ("figures of equal size", "figures of different sizes"),
    23: ("one figure", "two figures"),
    39: ("lines almost parallel", "lines not all parallel"),
    56: ("same texture", "different textures"),
    85: ("three lines", "five lines"),
}

if __name__ == '__main__':
    shot, out, n = sys.argv[1], sys.argv[2], int(sys.argv[3])
    l, r = (sys.argv[4], sys.argv[5]) if len(sys.argv) >= 6 else LABELS.get(n, ("", ""))
    write_pbm(out, boxes(shot), n, l, r)
