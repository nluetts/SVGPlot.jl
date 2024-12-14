# This code defines the `Element` type, as one layer of abstraction above SVG
# tags. Elements are build from SVG tags under some restrictions to produce
# meaningful plots.


# ----------------------------------------------------------------------------
#
#
# Julia representation of Elements, the basic building blocks of Figures.
#
#
# ----------------------------------------------------------------------------


abstract type Element end

# this type is used to create circular dependency in Figure
# and Axis elements
abstract type AbstractAxis <: Element end

"""
The entrypoint of creating a Figure. This is the "canvas" to draw axis on.
"""
struct Figure{T<:AbstractAxis} <: Element
    width::Int64
    height::Int64
    axes::Vector{T}
    annotations::Vector{Element}
end

struct Axis <: AbstractAxis
    fig::Figure{Axis}
    u::Float64
    v::Float64
    width::Float64
    height::Float64
    limits::Vector{Float64}
    elements::Vector{Element}
    properties::Dict{Symbol,Any}
    function Axis(fig, u, v, w, h, lims, els; kw...)
        new(fig, u, v, w, h, lims, els, kw)
    end
end

struct Text <: Element
    text::String
    u::Float64
    v::Float64
    axis::Axis
    properties::Dict{Symbol,Any}
    function Text(text, u, v, ax; kw...)
        new(text, u, v, ax, kw)
    end
end

struct Ticks{T<:Val} <: Element
    positions::Vector{Float64}
    color::String
    linewidth::Float64
    axis::Axis
end

abstract type Plot <: Element end

struct LinePlot <: Plot
    xs::Vector{Float64}
    ys::Vector{Float64}
    axis::Axis
    properties::Dict{Symbol,Any}
    function LinePlot(xs, ys, ax; kw...)
        new(xs, ys, ax, kw)
    end
end

struct BarPlot <: Plot
    xs::Vector{Float64}
    ys::Vector{Float64}
    axis::Axis
    width::Float64
    properties::Dict{Symbol,Any}
    function BarPlot(xs, ys, ax, w=1.0; kw...)
        new(xs, ys, ax, w, kw)
    end
end

struct ScatterPlot <: Plot
    xs::Vector{Float64}
    ys::Vector{Float64}
    axis::Axis
    properties::Dict{Symbol,Any}
    function ScatterPlot(xs, ys, ax; kw...)
        new(xs, ys, ax, kw)
    end
end


# ----------------------------------------------------------------------------
#
#
# Conversion of elements to SVG tags.
#
#
# ----------------------------------------------------------------------------


function to_tags(ax::Axis)
    w, h = ax.fig.width, ax.fig.height
    ax_rect = rect_tag(w * ax.u, h * ax.v, ax.width * w, ax.height * h; ax.properties...)
    local tags = []
    push!(tags, ax_rect)
    for el in ax.elements
        ts = to_tags(el)
        if typeof(ts) <: Vector
            push!(tags, ts...)
        else
            push!(tags, ts)
        end
    end
    tags
end

"""
Return transformations functions needed to place objects correctly within
axis `ax`.

Functions returned:

x(u), y(v), u(x), v(y)

"""
function transformations(ax)
    fw, fh = ax.fig.width, ax.fig.height
    au, av, aw, ah = ax.u, ax.v, ax.width, ax.height
    xmin, xmax, ymin, ymax = ax.limits

    x(u) = fw * (au + u * aw)
    y(v) = fh * (av + v * ah)
    u(x) = (x - xmin) / (xmax - xmin)
    v(y) = 1 - (y - ymin) / (ymax - ymin)

    x, y, u, v
end

function crop_to_axis(sctr::LinePlot)
    xs, ys = sctr.xs, sctr.ys
    return xs, ys
    #TODO
    xmin, xmax, ymin, ymax = sctr.axis.limits

    xy_cropped = [(x, y) for (x, y) in zip(xs, ys) if xmin <= x <= xmax && ymin <= y <= ymax]

    map(first, xy_cropped), map(last, xy_cropped)
end

function crop_to_axis(sctr::ScatterPlot)
    xs, ys = sctr.xs, sctr.ys
    xmin, xmax, ymin, ymax = sctr.axis.limits

    xy_cropped = [(x, y) for (x, y) in zip(xs, ys) if xmin <= x <= xmax && ymin <= y <= ymax]

    map(first, xy_cropped), map(last, xy_cropped)
end

function to_tags(txt::Text)::Tag{Val{:text}}
    x, y, _, _ = transformations(txt.axis)

    x, y = x(txt.u), y(1 - txt.v)
    θ = get(txt.properties, :angle, nothing)

    if !isnothing(θ)
        x, y = [x y] * [cosd(θ) -sind(θ); sind(θ) cosd(θ)]
        text_tag(x, y, txt.text; transform="rotate($(θ),0,0)", txt.properties...)
    else
        text_tag(x, y, txt.text; txt.properties...)
    end
end

function to_tags(line::LinePlot)
    x, y, u, v = transformations(line.axis)

    xs, ys = crop_to_axis(line)
    xs = [x(u(xi)) for xi in xs]
    ys = [y(v(yi)) for yi in ys]

    polyline_tag(xs, ys; line.properties...)
end

function to_tags(sctr::ScatterPlot)
    x, y, u, v = transformations(sctr.axis)

    xs, ys = crop_to_axis(sctr)
    xs = [x(u(xi)) for xi in xs]
    ys = [y(v(yi)) for yi in ys]

    [circle_tag(xi, yi, 1; sctr.properties...) for (xi, yi) in zip(xs, ys)]
end

function to_tags(bplt::BarPlot)
    x, y, u, v = transformations(bplt.axis)
    yv(yi) = y(v(yi))

    xmin, xmax, ymin, ymax = bplt.axis.limits

    tags = []
    for (xi, yi) in zip(bplt.xs, bplt.ys)
        # if bar falls outside drawing range, we do nothing
        if xi < xmin || xi > xmax || yi > 0 > ymax || yi < 0 < ymin
            continue
        end

        # if we end up here, at least a part of the bar has to be drawn
        x_screen = x(u(xi)) - bplt.width / 2

        height_screen =
            if yi < 0
                # keep in mind that the direction is swapped
                # in figure space
                yv(max(yi, ymin)) - yv(min(0, ymax))
            else
                yv(max(0, ymin)) - yv(min(yi, ymax))
            end
        y_screen =
            if yi < 0
                yv(max(ymin, yi)) - height_screen
            else
                yv(min(ymax, yi))
            end

        push!(tags, rect_tag(x_screen, y_screen, bplt.width, height_screen; bplt.properties...))
    end

    tags
end

function to_tags(tk::Ticks{Val{:x}})
    x, y, u, _ = transformations(tk.axis)
    xmin, xmax, _, _ = tk.axis.limits

    vcat(
        [line_tag(x(u(xi)), x(u(xi)), y(0.99), y(1.01); stroke=tk.color, stroke_width=tk.linewidth)
         for xi in tk.positions if xmin <= xi <= xmax],
        [text_tag(x(u(xi)), y(1.1), "$xi"; text_anchor="middle") for xi in tk.positions if xmin <= xi <= xmax]
    )
end

function to_tags(tk::Ticks{Val{:y}})
    x, y, _, v = transformations(tk.axis)
    _, _, ymin, ymax = tk.axis.limits

    vcat(
        [line_tag(x(-0.005), x(0.005), y(v(yi)), y(v(yi)); stroke=tk.color, stroke_width=1.0)
         for yi in tk.positions if ymin <= yi <= ymax],
        [text_tag(x(-0.03), y(v(yi) + 0.02), "$(round(yi; digits=4))"; text_anchor="end") for yi in tk.positions if ymin <= yi <= ymax]
    )
end


# ----------------------------------------------------------------------------
#
#
# Higher level functions to create and manipulate figures / axes / plots.
#
#
# ----------------------------------------------------------------------------


function axis!(fig::Figure{Axis}, uvwh::Tuple{Number,Number,Number,Number}, lims::Tuple{Number,Number,Number,Number}; kw...)::Axis
    u, v, w, h = uvwh
    ax = Axis(fig, u, v, w, h, [lims...], []; kw...)
    push!(fig.axes, ax)
    ax
end

function ticks!(ax::Axis, xticks, yticks)
    push!(ax.elements, Ticks{Val{:x}}(collect(xticks), "black", 1.0, ax))
    push!(ax.elements, Ticks{Val{:y}}(collect(yticks), "black", 1.0, ax))
end

function autoticks!(ax::Axis)
    mx, my = ax.width < ax.height ? (5, 2.5) : (2.5, 5)
    function set_ticks(idx, tmin, tmax, mult)
        span_mag = floor(log10(abs(tmax - tmin)))
        f = 10^(span_mag - 1)
        pos = (ceil(tmin / f)*f):(f*mult):(floor(tmax / f)*f) |> collect
        empty!(ax.elements[idx].positions)
        push!(ax.elements[idx].positions, pos...)
    end

    i = findfirst(el -> typeof(el) == Ticks{Val{:x}}, ax.elements)
    if !(isnothing(i))
        xmin, xmax = ax.limits[1:2]
        set_ticks(i, xmin, xmax, mx)
    end
    i = findfirst(el -> typeof(el) == Ticks{Val{:y}}, ax.elements)
    if !(isnothing(i))
        ymin, ymax = ax.limits[3:4]
        set_ticks(i, ymin, ymax, my)
    end
end

function histogram(xs, start, stop, step, ax; autoscale=true, w=4, kw...)
    limits = start:step:stop
    d = Dict((l, r) => 0 for (l, r) in zip(limits[1:end-1], limits[2:end]))

    for (l, r) in keys(d)
        for x in xs
            if l < x <= r
                d[(l, r)] += 1
            end
        end
    end

    output = zeros(length(keys(d)), 2)
    for (i, (l, r)) in sort(collect(keys(d)), by=first) |> enumerate
        output[i, 1] = (l + r) / 2
        output[i, 2] = d[(l, r)]
    end
    output[:, 2] /= sum(output[:, 2])
    bins = output[:, 1]
    rel_counts = output[:, 2]
    if autoscale
        ax.limits[3:4] = [0.0, maximum(rel_counts) * 1.1]
        autoticks!(ax)
    end
    BarPlot(bins, rel_counts, ax; width=w, kw...)
end


# ----------------------------------------------------------------------------
#
#
# Rendering of Elements to final SVG output.
#
#
# ----------------------------------------------------------------------------


function render(fig::Figure)::String
    root = svg_tag(fig.width, fig.height)
    for ax in fig.axes
        ax_tags = to_tags(ax)
        add_child!.(Ref(root), ax_tags)
    end
    render(root)
end
