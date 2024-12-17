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

function crop_to_axis(line::LinePlot)
    # This function checks the xy-data in LinePlot for going out of the axis
    # boundaries. If the data goes out of the axis, a new datapoint is added
    # (at the crossing of the axis). Furthermore, the data is subdivided into
    # segments at each axis crossing, so it can be rendered with several svg
    # polyline elements.
    # This function is the definition of spaghetti code ... but I am currently
    # unable to find a better solution, and there seem to be just many cases
    # to consider.

    xs, ys = line.xs, line.ys
    nx, ny = length(xs), length(ys)
    n = min(nx, ny)
    if nx < 2 || ny < 2
        nx < 2 && @warn "need more than two points to draw line (length x < 2)"
        ny < 2 && @warn "need more than two points to draw line (length y < 2)"
        return xs, ys
    end

    # The axis limits, but correctly ordered, no matter if axis directions are
    # reversed:
    xmin, xmax, ymin, ymax = let
        l, r, b, t = line.axis.limits
        min(l, r), max(l, r), min(b, t), max(b, t)
    end

    # Short circuit if everything fits into axis.
    if all(xmin < x < xmax && ymin < y < ymax for (x, y) in zip(xs, ys))
        return [(xs, ys)]
    end

    xspan = xmax - xmin
    yspan = ymax - ymin

    # Helper function to find point outside of axis, refering to point by index:
    outside(i) = xs[i] < xmin || xs[i] > xmax || ys[i] < ymin || ys[i] > ymax

    # Containers to hold data segments:
    T = typeof(first(xs))
    xp_cur = T[]
    yp_cur = T[]
    segments = [(xp_cur, yp_cur)]

    for i in 1:(n - 1) # iterate datapoints
        # Current datapoints normalized to axis from 0 to 1 in both x and y
        # directions. This normalization makes later checks and calculations
        # of crossings easier.
        xm, xn, ym, yn = let
            k, l = xs[i] < xs[i + 1] ? (i, i + 1) : (i + 1, i) # to make sure that xm < xn
            (xs[k] - xmin)/xspan, (xs[l] - xmin)/xspan,  (ys[k] - ymin)/yspan,  (ys[l] - ymin)/yspan
        end

        # If the datapoints are _both_ to the left, above, right, or under the
        # axis, respectively, there cannot be any crossings and we can continue.
        if (xm < 0 && xn < 0) || (xm > 1 && xn > 1) || (ym < 0 && yn < 0) || (ym > 1 && yn > 1)
            continue
        end

        # If the ith point is outside axis and the current segment is not empty,
        # we have to start a new segment of datapoints.
        if outside(i)
            if !isempty(xp_cur)
                xp_cur = T[]
                yp_cur = T[]
                push!(segments, (xp_cur, yp_cur))
            end
        else
            # If ith point lies within axis, we add it to the current segment.
            push!(xp_cur, xs[i])
            push!(yp_cur, ys[i])
            # If (i + 1)th datapoint is also within axis, we do not need to check
            # for crossings ...
            if !outside(i + 1)
                # ... but we have to check if it is the last point, because then
                # we have to add it to the current (and last) segment.
                if i + 1 == n
                    push!(xp_cur, xs[i + 1])
                    push!(yp_cur, ys[i + 1])
                    break
                end
                continue
            end
        end

        # This is an edge case where we cannot use a line function to interpolate
        # positions of crossings.
        if xm == xn
            # Because of the earlier check, we know that 0 < x < 1.
            if (ym > 1 || yn > 1)
                push!(xp_cur, xs[i])
                push!(yp_cur, ymax)
            end
            if (ym < 0 || yn < 0)
                push!(xp_cur, xs[i])
                push!(yp_cur, ymin)
            end
            # There cannot be any other crossings, so we continue.
            continue
        end

        # The line function defined by current data points:
        m = (yn - ym) / (xn - xm) # slope
        b = ym - xm * m           # offset

        # We keep track of the number of crossings: because there can only be two
        # we can skip further checks if we reach that number.
        num_crossings = 0

        # This tests whether the line defined by data points crosses left boundary:
        if 0 < b <= 1 && xm < 0
            num_crossings += 1
            push!(xp_cur, xmin)
            push!(yp_cur, b * yspan - ymin)
        end

        # This tests whether the line defined by data points crosses top boundary:
        if 0 <= (1 - b)/m < 1 && (yn > 1 || ym > 1)
            num_crossings += 1
            push!(xp_cur, xspan*(1 - b)/m + xmin)
            push!(yp_cur, ymax)
        end

        # If we cross two times, we can skip checking for more crossings.
        num_crossings == 2 && @goto check_last

        # This tests whether the line defined by data points crosses right boundary:
        if 0 < m + b <= 1 && xn > 1
            num_crossings += 1
            push!(xp_cur, xmax)
            push!(yp_cur, (m + b) * yspan - ymin)
        end

        # If we cross two times, we can skip checking for more crossings.
        num_crossings == 2 && @goto check_last

        # This tests whether the line defined by data points crosses bottom boundary:
        if 0 <= -b/m < 1 && (yn < 0 || ym < 0)
            num_crossings += 1
            push!(xp_cur, -b*xspan/m + xmin)
            push!(yp_cur, ymin)
        end

        @label check_last
        if i == n - 1 && !outside(i + 1)
            # If the last datapoint falls within the axis, we add it to the current (and last)
            # datapoint segment.
            push!(xp_cur, xs[i + 1])
            push!(yp_cur, ys[i + 1])
        end
                
    end # iterate datapoints

    segments
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

    segments = crop_to_axis(line)

    [polyline_tag(x.(u.(xs)), y.(v.(ys)); line.properties...) for (xs, ys) in segments]
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
