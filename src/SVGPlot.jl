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
    elements::Vector{Element}
end

struct Text <: Element
    text::String
    position::UVCoords
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

parent_figure(ax::Axis)::Figure = ax.fig
parent_axis(plot::LinePlot)::Axis = plot.axis
parent_axis(plot::ScatterPlot)::Axis = plot.axis
parent_axis(plot::BarPlot)::Axis = plot.axis

function axis!(fig::Figure{Axis}, u::Float64, v::Float64, w::Float64, h::Float64)::Axis
    ax = Axis(fig, UVCoords(u, v), w, h, [])
    push!(fig.axes, ax)
    ax
end

mutable struct Tag{T<:Val}
    parameters::Dict{String,String}
    children::Vector{Union{Tag, String}}
    closing::Bool
end

const TagChild = Union{Tag, String}

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
function text(x, y, text::String)::Tag{Val{:text}}
    pars = Dict(
        "x" => "$x",
        "y" => "$y",
        "text-anchor" => "middle",
    )
    children = TagChild[text]
    Tag{Val{:text}}(pars, children, true)
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

function scatter!(s::Tag{Val{:svg}}, xs, ys)
    for (x, y) in zip(xs, ys)
        c = circle(x, y, 100)
        with_background!(c, "blue")
        add_child!(s, c)
    end
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
    with_background!(ax_rect, "green")
    local tags = []
    push!(tags, ax_rect)
    push!(tags, [to_tags(e) for e in ax.elements]...)
    tags
end

function to_tags(txt::Text)::Tag{Val{:text}}
    fw, fh = txt.axis.fig.width, txt.axis.fig.height
    au, av, aw, ah = txt.axis.position.u, txt.axis.position.v, txt.axis.width, txt.axis.height
    x = fw * (au + txt.position.u * aw)
    y = fh * (av + txt.position.v * ah)
    text(x, y, txt.text)
end


function test()
    fig = Figure(800, 600, Axis[])
    ax = axis!(fig, 0.1, 0.1, 0.25, 0.25)
    push!(ax.elements, Text("Hello", UVCoords(0.5, 0.5), ax))
    ax = axis!(fig, 0.4, 0.1, 0.25, 0.25)
    push!(ax.elements, Text(",", UVCoords(0.5, 0.5), ax))
    ax = axis!(fig, 0.1, 0.4, 0.25, 0.25)
    push!(ax.elements, Text("World", UVCoords(0.5, 0.5), ax))
    ax = axis!(fig, 0.4, 0.4, 0.25, 0.25)
    push!(ax.elements, Text("!", UVCoords(0.5, 0.5), ax))

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
