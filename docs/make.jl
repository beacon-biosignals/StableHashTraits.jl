using StableHashTraits
using Documenter

readme_file = joinpath(pkgdir(StableHashTraits), "README.md")
readme = read(readme_file, String)
overview_txt = match(r"START_OVERVIEW-->(.*)<!--END_OVERVIEW"s, readme).captures[1]
example_txt = match(r"START_EXAMPLE-->(.*)<!--END_EXAMPLE"s, readme).captures[1]

manual_str = read("src/manual_template.md", String)
manual_str = replace(manual_str, "{INSERT_OVERVIEW}" => overview_txt)
manual_str = replace(manual_str, "{INSERT_EXAMPLE}" => overview_txt)
write("src/manual.md", manual_str)

pages = ["Manual" => "manual.md",
         "API" => "api.md"]

makedocs(; modules=[StableHashTraits], sitename="StableHashTraits.jl", authors="Beacon Biosignals", pages,
            doctestfilters)
deploydocs(; repo="github.com/beacon-biosignals/StableHashTraits.jl",
            push_preview=true,
            devbranch="main")
