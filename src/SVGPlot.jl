module SVGPlot

struct ScreenCoords
    x::Float64
    y::Float64
end

mutable struct Tag{T <: Val}
    parameters::Dict{String,String}
    children::Vector{Tag}
    closing::Bool
end

function add_child!(root::Tag{T}, child::Tag{S}) where {S <: Val, T <: Val}
    push!(root.children, child);
end

"""Create an SVG tag."""
function svg(width_mm, height_mm)::Tag{Val{:svg}}
    pars = Dict(
        "width" => "$(width_mm)mm",
        "height" => "$(height_mm)mm",
        "viewBox" => "0 0 $(width_mm*100) $(height_mm*100)",
    )
    children = Tag[]
    Tag{Val{:svg}}(pars, children, true)
end

"""Create an circle tag."""
function circle(cx, cy, r)::Tag{Val{:circle}}
    pars = Dict(
        "cx" => "$cx",
        "cy" => "$cy",
        "r" => "$(r)mm",
    )
    children = Tag[]
    Tag{Val{:circle}}(pars, children, false)
end

"""Create an rect tag."""
function rect(x, y, width, height)::Tag{Val{:rect}}
    pars = Dict(
        "x" => "$x",
        "y" => "$y",
        "width" => "$(width)mm",
        "height" => "$(height)mm",
    )
    children = Tag[]
    Tag{Val{:rect}}(pars, children, false)
end

function with_background!(tag::Tag{Val{:svg}}, color::String)
    tag.parameters["style"] = "background-color:$(color)";
end

function with_background!(tag::Tag{T}, color::String) where T <: Union{Val{:rect}, Val{:circle}}
    tag.parameters["fill"] = color
    tag
end

function render(tag::Tag{Val{:svg}})
    buf = IOBuffer()
    render!(buf, tag)
end

function render!(buf::IOBuffer, tag::Tag{Val{T}}) where T
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

function scatter!(s::Tag{Val{:svg}}, xs, ys)
    for (x, y) in zip(xs, ys)
        c = circle(x, y, 100)
        with_background!(c, "blue")
        add_child!(s, c)
    end
end

function test()
    s = svg(297, 210)
    with_background!(s, "pink")
    c = circle(14800, 10500, 300)
    with_background!(c, "green")
    add_child!(s, c)
    scatter!(s, collect(0:1000:10000), rand(0:10000, 10))
    raw_svg = render(s) |> take! |> String
    open("tmp.svg", "w") do f
        write(f, raw_svg)
    end

end

end # module SVGPlot
