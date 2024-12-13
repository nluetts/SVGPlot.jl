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

struct Tick{T<:Val} <: Element
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
    properties::Dict{Symbol, Any}
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

    xs = [x(u(xi)) for xi in line.xs]
    ys = [y(v(yi)) for yi in line.ys]

    polyline_tag(xs, ys; line.properties...)
end

function to_tags(sctr::ScatterPlot)
    x, y, u, v = transformations(sctr.axis)

    xs = [x(u(xi)) for xi in sctr.xs]
    ys = [y(v(yi)) for yi in sctr.ys]

    [circle_tag(xi, yi, 1; sctr.properties...) for (xi, yi) in zip(xs, ys)]
end

function to_tags(bplt::BarPlot)
    x, y, u, v = transformations(bplt.axis)

    xs = [x(u(xi)) for xi in bplt.xs]
    ys = [y(v(yi)) for yi in bplt.ys]

    [rect_tag(xi - bplt.width / 2, yi, bplt.width, abs(yi - y(v(0))); bplt.properties...)
     for (xi, yi) in zip(xs, ys)]
end

function to_tags(tk::Tick{Val{:x}})
    x, y, u, _ = transformations(tk.axis)

    vcat(
        [line_tag(x(u(xi)), x(u(xi)), y(0.99), y(1.01), "black", 1.0) for xi in tk.positions],
        [text_tag(x(u(xi)), y(1.1), "$xi"; text_anchor="middle") for xi in tk.positions]
    )
end

function to_tags(tk::Tick{Val{:y}})
    x, y, _, v = transformations(tk.axis)

    vcat(
        [line_tag(x(-0.005), x(0.005), y(1 - v(yi)), y(1 - v(yi)), "black", 1.0) for yi in tk.positions],
        [text_tag(x(-0.03), y(1 - v(yi) + 0.02), "$(round(yi; digits=4))"; text_anchor="end") for yi in tk.positions]
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
    push!(ax.elements, Tick{Val{:x}}(collect(xticks), "black", 1.0, ax))
    push!(ax.elements, Tick{Val{:y}}(collect(yticks), "black", 1.0, ax))
end

function histogram(xs, start, stop, step, ax; autoscale = true, w=4, kw...)
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
        ax.limits[end] = maximum(rel_counts) * 1.1
    end
    for el in ax.elements
        if typeof(el) == Tick{Val{:y}}
            #TODO: factor out autoscaling function
            max = ax.limits[end]
            f = 10^(floor(log10(max)) - 1)
            empty!(el.positions)
            push!(el.positions, collect(0:f*5:max)...)
        end
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
    render(root) |> take! |> String
end
