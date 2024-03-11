using StableHashTraits
using Documenter

DocMeta.setdocmeta!(StableHashTraits, :DocTestSetup, :(using StableHashTraits))

readme_file = joinpath(pkgdir(StableHashTraits), "README.md")
readme = read(readme_file, String)
overview_txt = match(r"START_OVERVIEW-->(.*?)<!--END_OVERVIEW"s, readme).captures[1]
example_txt = match(r"START_EXAMPLE-->(.*?)<!--END_EXAMPLE"s, readme).captures[1]

index_str = read(joinpath(@__DIR__, "templates/index_template.md"), String)
index_str = replace(index_str, "{INSERT_OVERVIEW}" => overview_txt)
index_str = replace(index_str, "{INSERT_EXAMPLE}" => example_txt)

link_pattern = r"\[`(\S+)`\]\((https://beacon-biosignals\.github\.io/StableHashTraits\.jl/stable/\S+)\)"
index_str = replace(index_str, link_pattern => s"[`\1`](@ref)")
write(joinpath(@__DIR__, "src/index.md"), index_str)

pages = ["Manual" => "index.md",
         "API" => "api.md",
         "Deprecated" => "deprecated.md"]

makedocs(; modules=[StableHashTraits], sitename="StableHashTraits.jl",
         authors="Beacon Biosignals", pages)
rm("src/index.md")
deploydocs(; repo="github.com/beacon-biosignals/StableHashTraits.jl",
           push_preview=true,
           devbranch="main")
