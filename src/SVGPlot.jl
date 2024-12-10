module SVGPlot

struct ScreenCoords
    x::Float64
    y::Float64
end

struct UVCoords
    u::Float64
    v::Float64
end

struct PlotCoordinates
    x::Float64
    y::Float64
end

abstract type Element end

abstract type AbstractAxis <: Element end # hack to create circular dependency in structs

struct Figure{T<:AbstractAxis} <: Element
    width::Int64
    height::Int64
    axes::Vector{T}
end

abstract type Plot <: Element end

struct Axis <: AbstractAxis
    fig::Figure{Axis}
    position::UVCoords
    width::Float64
    height::Float64
    limits::Tuple{Float64,Float64,Float64,Float64}
    elements::Vector{Element}
end

struct Text <: Element
    text::String
    position::UVCoords
    axis::Axis
    angle::Float64
    function Text(text, u, v, ax; angle=0.0)
        new(text, UVCoords(u, v), ax, angle)
    end
end

struct Tick{T<:Val} <: Element
    positions::Vector{Float64}
    color::String
    linewidth::Float64
    axis::Axis
end

struct LinePlot <: Plot
    xs::Vector{Float64}
    ys::Vector{Float64}
    axis::Axis
end

struct BarPlot <: Plot
    xs::Vector{Float64}
    ys::Vector{Float64}
    axis::Axis
    width::Float64
end

struct ScatterPlot <: Plot
    xs::Vector{Float64}
    ys::Vector{Float64}
    axis::Axis
end

function axis!(fig::Figure{Axis}, u::Float64, v::Float64, w::Float64, h::Float64)::Axis
    ax = Axis(fig, UVCoords(u, v), w, h, (0, 100, 0, 200), [])
    push!(fig.axes, ax)
    ax
end

mutable struct Tag{T<:Val}
    parameters::Dict{String,String}
    children::Vector{Union{Tag,String}}
    closing::Bool
end

const TagChild = Union{Tag,String}

function add_child!(root::Tag{T}, child::Tag{S}) where {S<:Val,T<:Val}
    push!(root.children, child)
end

"""Create an SVG tag."""
function svg_tag(width, height)::Tag{Val{:svg}}
    pars = Dict(
        "width" => "$(width)px",
        "height" => "$(height)px",
        "viewBox" => "0 0 $(width) $(height)",
    )
    children = TagChild[]
    Tag{Val{:svg}}(pars, children, true)
end

"""Create an circle tag."""
function circle(cx, cy, r)::Tag{Val{:circle}}
    pars = Dict(
        "cx" => "$cx",
        "cy" => "$cy",
        "r" => "$(r)mm",
    )
    children = TagChild[]
    Tag{Val{:circle}}(pars, children, false)
end

"""Create an rect tag."""
function rect(x, y, width, height)::Tag{Val{:rect}}
    pars = Dict(
        "x" => "$x",
        "y" => "$y",
        "width" => "$(width)",
        "height" => "$(height)",
    )
    children = TagChild[]
    Tag{Val{:rect}}(pars, children, false)
end

"""Create an text tag."""
function text_tag(x, y, text_tag::String; kw...)::Tag{Val{:text}}
    pars = Dict(
        "x" => "$x",
        "y" => "$y",
        "text-anchor" => "middle",
        Dict(String(k) => String(v) for (k, v) in kw)...
    )
    children = TagChild[text_tag]
    Tag{Val{:text}}(pars, children, true)
end

function line_tag(x1, x2, y1, y2, color::String, linewidth::Float64)::Tag{Val{:line}}
    pars = Dict(
        "x1" => "$x1",
        "x2" => "$x2",
        "y1" => "$y1",
        "y2" => "$y2",
        "stroke" => color,
        "width" => "$(linewidth)",

    )
    children = TagChild[]
    Tag{Val{:line}}(pars, children, false)
end

function polyline(xs, ys, color::String, linewidth::Float64)::Tag{Val{:polyline}}
    points = let
        buf = IOBuffer()
        for (x, y) in zip(xs, ys)
            write(buf, "$x,$y ")
        end
        String(take!(buf))
    end
    pars = Dict(
        "points" => "$(points)",
        "stroke" => color,
        "width" => "$(linewidth)",
        "fill" => "none",
    )
    children = TagChild[]
    Tag{Val{:polyline}}(pars, children, false)
end

function with_background!(tag::Tag{Val{:svg}}, color::String)
    tag.parameters["style"] = "background-color:$(color)"
end

function with_background!(tag::Tag{T}, color::String) where {T<:Union{Val{:rect},Val{:circle}}}
    tag.parameters["fill"] = color
    tag
end

function render(tag::Tag{Val{:svg}})
    buf = IOBuffer()
    render!(buf, tag)
end

function render!(buf::IOBuffer, tag::Tag{Val{T}}) where {T}
    write(buf, "<$T")
    for (k, v) in tag.parameters
        write(buf, " $k=\"$v\"")
    end
    if !tag.closing
        write(buf, " /")
    end
    write(buf, ">")
    for c in tag.children
        render!(buf, c)
    end
    if tag.closing
        write(buf, "</$T>")
    end
    buf
end

render!(buf, String) = write(buf, String)

function ticks!(ax::Axis, xticks::Vector{Float64}, yticks::Vector{Float64})
    push!(ax.elements, Tick{Val{:x}}(xticks, "black", 1.0, ax))
    push!(ax.elements, Tick{Val{:y}}(yticks, "black", 1.0, ax))
end

function render(fig::Figure)::String
    root = svg_tag(fig.width, fig.height)
    for ax in fig.axes
        ax_tags = to_tags(ax)
        add_child!.(Ref(root), ax_tags)
    end
    render(root) |> take! |> String
end

function to_tags(ax::Axis)
    w, h = ax.fig.width, ax.fig.height
    ax_rect = rect(w * ax.position.u, h * ax.position.v, ax.width * w, ax.height * h)
    with_background!(ax_rect, "yellow")
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

function to_tags(txt::Text)::Tag{Val{:text}}
    fw, fh = txt.axis.fig.width, txt.axis.fig.height
    au, av, aw, ah = txt.axis.position.u, txt.axis.position.v, txt.axis.width, txt.axis.height
    x = fw * (au + txt.position.u * aw)
    y = fh * (av + (1 - txt.position.v) * ah)
    if txt.angle != 0
        θ = txt.angle
        x, y = [x  y]*[cosd(θ) -sind(θ); sind(θ) cosd(θ)]
        text_tag(x, y, txt.text; transform="rotate($(txt.angle),0,0)")
    else
        text_tag(x, y, txt.text)
    end
end

function to_tags(line::LinePlot)
    fw, fh = line.axis.fig.width, line.axis.fig.height
    au, av, aw, ah = line.axis.position.u, line.axis.position.v, line.axis.width, line.axis.height
    xmin, xmax, ymin, ymax = line.axis.limits

    x(u) = fw * (au + u * aw)
    y(v) = fh * (av + v * ah)
    u(x) = (x - xmin) / (xmax - xmin)
    v(y) = (y - ymin) / (ymax - ymin)

    xs = [x(u(xi)) for xi in line.xs]
    ys = [y(1 - v(yi)) for yi in line.ys]

    polyline(xs, ys, "red", 1.0)
end

function to_tags(tk::Tick{Val{:x}})
    fw, fh = tk.axis.fig.width, tk.axis.fig.height
    au, av, aw, ah = tk.axis.position.u, tk.axis.position.v, tk.axis.width, tk.axis.height
    xmin, xmax, ymin, ymax = tk.axis.limits

    x(u) = fw * (au + u * aw)
    y(v) = fh * (av + v * ah)
    u(x) = (x - xmin) / (xmax - xmin)
    v(y) = (y - ymin) / (ymax - ymin)

    [line_tag(x(u(xi)), x(u(xi)), y(1-0.01), y(1+0.01), "black", 1.0) for xi in tk.positions]
end

function to_tags(tk::Tick{Val{:y}})
    fw, fh = tk.axis.fig.width, tk.axis.fig.height
    au, av, aw, ah = tk.axis.position.u, tk.axis.position.v, tk.axis.width, tk.axis.height
    xmin, xmax, ymin, ymax = tk.axis.limits

    x(u) = fw * (au + u * aw)
    y(v) = fh * (av + v * ah)
    u(x) = (x - xmin) / (xmax - xmin)
    v(y) = (y - ymin) / (ymax - ymin)

    [line_tag(x(-0.005), x(0.005), y(u(yi)), y(u(yi)), "black", 1.0) for yi in tk.positions]
end

function test()
    fig = Figure(1280, 960, Axis[])
    # ax = axis!(fig, 0.1, 0.1, 0.25, 0.25)
    # push!(ax.elements, Text("Hello", UVCoords(0.5, 0.5), ax))
    # ax = axis!(fig, 0.4, 0.1, 0.25, 0.25)
    # push!(ax.elements, Text(",", UVCoords(0.5, 0.5), ax))
    # ax = axis!(fig, 0.1, 0.4, 0.25, 0.25)
    # push!(ax.elements, Text("World", UVCoords(0.5, 0.5), ax))
    ax = axis!(fig, 0.1, 0.1, 0.4, 0.4)
    ticks!(ax, [0, 25, 50, 75, 100.], [0, 50, 100.])
    push!(ax.elements, Text("x-label / unit", 0.5, -0.05, ax))
    push!(ax.elements, Text("y-label / unit", -0.05, 0.5, ax; angle=270.0))
    push!(ax.elements, LinePlot(collect(0:100), rand(101)*200, ax))
    ax = axis!(fig, 0.4, 0.4, 0.4, 0.4)
    ticks!(ax, [0, 25, 50, 75, 100.], [0, 50, 100.])
    push!(ax.elements, Text("x-label / unit", 0.5, -0.05, ax))
    push!(ax.elements, Text("y-label / unit", -0.05, 0.5, ax; angle=270.0))
    push!(ax.elements, LinePlot(collect(0:100), rand(101)*200, ax))

    render(fig)


    # s = svg(297, 210)
    # with_background!(s, "pink")
    # c = circle(14800, 10500, 300)
    # with_background!(c, "green")
    # add_child!(s, c)
    # scatter!(s, collect(0:1000:10000), rand(0:10000, 10))
    # raw_svg = render(s) |> take! |> String
    # open("tmp.svg", "w") do f
    #     write(f, raw_svg)
    # end
end

open("tmp.html", "w") do f
    write(f, "<html>")
    write(f, test())
    write(f, "</html>")
end

end # module SVGPlot
