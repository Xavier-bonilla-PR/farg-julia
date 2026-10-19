# Overlay what the retina found on a BP's boxes, for looking at.
#   julia --project=phaeaco/julia phaeaco/bench/render_retina.jl OUT.ppm synth_name [seed] [σ]
# grey = ink, red = lines, blue = junctions, green = ellipses, orange = dots
using PhaeacoJL, Random
const P = PhaeacoJL

function overlay(bp::P.BP, params; seed=1)
    S = 3                                    # magnification
    gap = 6
    W = 6 * (100 * S + gap)
    H = 2 * (100 * S + gap)
    img = fill((255, 255, 255), H, W)
    function put(x, y, c, x0, y0)
        X, Y = round(Int, x0 + (x - 0.5) * S), round(Int, y0 + (y - 0.5) * S)
        (1 <= X <= W && 1 <= Y <= H) && (img[Y, X] = c)
    end
    function line(a, b, c, x0, y0)
        n = max(2, ceil(Int, 2S * P.dist(a, b)))
        for k in 0:n
            t = k / n
            put(a[1] + t * (b[1] - a[1]), a[2] + t * (b[2] - a[2]), c, x0, y0)
        end
    end
    for i in 1:12
        x0 = ((i - 1) % 6) * (100S + gap)
        y0 = ((i - 1) ÷ 6) * (100S + gap)
        r = P.see(bp.boxes[i], params, Xoshiro(seed + i))
        for y in 1:100, x in 1:100
            bp.boxes[i][y, x] || continue
            for dy in 0:S-1, dx in 0:S-1
                img[y0 + (y - 1) * S + dy + 1, x0 + (x - 1) * S + dx + 1] = (200, 200, 200)
            end
        end
        for x in 0:100S-1
            img[y0+1, x0+x+1] = img[y0+100S, x0+x+1] = (0, 0, 0)
            img[y0+x+1, x0+1] = img[y0+x+1, x0+100S] = (0, 0, 0)
        end
        for l in r.lines
            l.alive && line(l.p1, l.p2, l.src == :exo ? (160, 0, 160) : (220, 0, 0), x0, y0)
        end
        for e in r.ellipses
            pts = P.ellipse_points(P.Shape(:ellipse, [e.centre]; a=e.axes[1], b=e.axes[2], theta=e.theta), 64)
            for k in 1:64
                line(pts[k], pts[k%64+1], e.circle ? (0, 150, 0) : (0, 200, 120), x0, y0)
            end
        end
        for j in r.junctions, dx in -1:1, dy in -1:1
            put(j.p[1] + dx / S, j.p[2] + dy / S, j.kind == :V ? (0, 0, 255) : j.kind == :T ? (0, 160, 255) : (0, 0, 120), x0, y0)
        end
        for d in r.dots, dx in -2:2, dy in -2:2
            put(d.centre[1] + dx / S, d.centre[2] + dy / S, (255, 140, 0), x0, y0)
        end
    end
    return img
end

function write_ppm(path, img)
    open(path, "w") do io
        H, W = size(img)
        println(io, "P6\n$W $H\n255")
        for y in 1:H, x in 1:W
            write(io, UInt8.(collect(img[y, x])))
        end
    end
end

out, name = ARGS[1], Symbol(ARGS[2])
seed = length(ARGS) >= 3 ? parse(Int, ARGS[3]) : 1
σ = length(ARGS) >= 4 ? parse(Float64, ARGS[4]) : 0.0
bp, _ = P.synth_bp(name; seed=seed, σ=σ)
write_ppm(out, overlay(bp, P.load_params(); seed=seed))
