# This code is a thin Julia wrapper to handle SVG tags
# and render the results to *.svg files.


# ----------------------------------------------------------------------------
#
#
# Julia representation of SVG tags.
#
#
# ----------------------------------------------------------------------------

mutable struct Tag{T<:Val}
    parameters::Dict{String,String}
    children::Vector{Union{Tag,String}}
    closing::Bool
end

const TagChild = Union{Tag,String}

function add_child!(parent::Tag{T}, child::Tag{S}) where {S<:Val,T<:Val}
    push!(parent.children, child)
end

function to_svg_properties(dict)::Dict{String,String}
    Dict(replace(String(k), "_" => "-") => "$v" for (k, v) in dict)
end

function svg_tag(width, height, kw...)::Tag{Val{:svg}}
    pars = Dict(
        "width" => "$(width)",
        "height" => "$(height)",
        "viewBox" => "0 0 $(width) $(height)",
        to_svg_properties(kw)...
    )
    children = TagChild[]
    Tag{Val{:svg}}(pars, children, true)
end

function circle_tag(cx, cy, r; kw...)::Tag{Val{:circle}}
    pars = Dict(
        "cx" => "$cx",
        "cy" => "$cy",
        "r" => "$r",
        to_svg_properties(kw)...
    )
    children = TagChild[]
    Tag{Val{:circle}}(pars, children, false)
end

function rect_tag(x, y, width, height; kw...)::Tag{Val{:rect}}
    pars = Dict(
        "x" => "$x",
        "y" => "$y",
        "width" => "$(width)",
        "height" => "$(height)",
        "fill" => "white",
        to_svg_properties(kw)...
    )
    children = TagChild[]
    Tag{Val{:rect}}(pars, children, false)
end

function text_tag(x, y, text_tag::String; kw...)::Tag{Val{:text}}
    pars = Dict(
        "x" => "$x",
        "y" => "$y",
        to_svg_properties(kw)...
    )
    children = TagChild[text_tag]
    Tag{Val{:text}}(pars, children, true)
end

function line_tag(x1, x2, y1, y2; kw...)::Tag{Val{:line}}
    pars = Dict(
        "x1" => "$x1",
        "x2" => "$x2",
        "y1" => "$y1",
        "y2" => "$y2",
        "stroke" => "black",
        to_svg_properties(kw)...
    )
    children = TagChild[]
    Tag{Val{:line}}(pars, children, false)
end

function polyline_tag(xs, ys; kw...)::Tag{Val{:polyline}}
    points = let
        buf = IOBuffer()
        for (x, y) in zip(xs, ys)
            write(buf, "$x,$y ")
        end
        String(take!(buf))
    end
    pars = Dict(
        "points" => points,
        "fill" => "none",
        to_svg_properties(kw)...
    )
    children = TagChild[]
    Tag{Val{:polyline}}(pars, children, false)
end

# ----------------------------------------------------------------------------
#
#
# Rendering of SVG tags
#
#
# ----------------------------------------------------------------------------


function render(tag::Tag{Val{:svg}})
    buf = IOBuffer()
    render!(buf, tag)
    buf |> take! |> String
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
end

render!(buf, String) = write(buf, String)
