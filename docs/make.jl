using StableHashTraits
using Documenter

readme_file = joinpath(pkgdir(StableHashTraits), "README.md")
readme = read(readme_file, String)
overview_txt = match(r"START_OVERVIEW-->(.*?)<!--END_OVERVIEW"s, readme).captures[1]
example_txt = match(r"START_EXAMPLE-->(.*?)<!--END_EXAMPLE"s, readme).captures[1]

index_str = read(joinpath(@__DIR__, "templates/index_template.md"), String)
index_str = replace(index_str, "{INSERT_OVERVIEW}" => overview_txt)
index_str = replace(index_str, "{INSERT_EXAMPLE}" => example_txt)
# revise admonition syntax
overview_txt = replace(overview_txt, r"^> \[!\w+\](^> .*$)+"m => str -> begin
    heading = match(r"^ (\w+)").capture[1]
    str = replace(str, r"^> (\w)+" => "!!! "*lowercase(heading))
    str = replace(str, r"^>(.*)$"m => s"    \1")
    return str
end)

link_pattern = r"\[`(\S+)`\]\((https://beacon-biosignals\.github\.io/StableHashTraits\.jl/stable/\S+)\)"
index_str = replace(index_str, link_pattern => s"[`\1`](@ref)")
write(joinpath(@__DIR__, "src", "index.md"), index_str)

pages = ["Manual" => "index.md",
         "API" => "api.md",
         "Deprecated" => "deprecated.md",
         "Internal Functions" => "internal.md"]

source_files = readdir(joinpath(@__DIR__, "src"))

DocMeta.setdocmeta!(StableHashTraits, :DocTestSetup, :(using StableHashTraits))
makedocs(; modules=[StableHashTraits], sitename="StableHashTraits.jl",
         authors="Beacon Biosignals", pages)
rm(joinpath(@__DIR__, "src", "index.md"))
deploydocs(; repo="github.com/beacon-biosignals/StableHashTraits.jl",
           push_preview=true,
           devbranch="main")
