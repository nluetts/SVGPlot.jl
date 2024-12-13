module SVGPlot

include("svg.jl")
include("plotting.jl")

function test()
    fig = Figure(640, 480, Axis[], Element[])

    # data
    n = 10000
    xs = collect(0:n)
    ys = randn(length(xs)) .* 30 .+ 100

    # first axis
    ax = axis!(fig, (0.2, 0.1, 0.75, 0.35), (-n*0.01, n*1.01, -10, 220); fill="#dedede")
    # title
    push!(ax.elements, Text("Data sampled from a normal distribution", 0.5, 1.1, ax; text_anchor="middle", font_size="20pt"))

    ticks!(ax, [0, floor(n/2), n], [0, 50, 100, 150, 200.0])
    push!(ax.elements, Text("sample", 0.5, -0.2, ax; text_anchor="middle"))
    push!(ax.elements, Text("value", -0.15, 0.5, ax; angle=270.0, text_anchor="middle"))
    push!(ax.elements, LinePlot(xs, ys, ax; stroke="blue"))
    # push!(ax.elements, ScatterPlot(xs, ys, ax; r="4px", fill="red"))

    # second axis
    ax = axis!(fig, (0.2, 0.55, 0.75, 0.35), (20, 180, 0, 0.1); fill="#dedede")
    ticks!(ax, 25:25:200, 0:50:200)
    push!(ax.elements, Text("value", 0.5, -0.2, ax; text_anchor="middle"))
    push!(ax.elements, Text("frequency", -0.15, 0.5, ax; angle=270.0, text_anchor="middle"))
    # push!(ax.elements, BarPlot(xs, ys, ax, 5; fill="blue"))
    push!(ax.elements, histogram(ys, 20, 180, 1, ax; fill="magenta", width=2))

    open("/tmp/tmp.html", "w") do f
        write(f, "<html>")
        write(f, render(fig))
        write(f, "</html>")
    end
end

end # module SVGPlot
