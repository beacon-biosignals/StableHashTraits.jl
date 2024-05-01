# extract contents of README so we can insert it into the some of the docstrings
function hash_method end

let
    readme_file = joinpath(pkgdir(StableHashTraits), "README.md")
    Base.include_dependency(readme_file)
    readme = read(readme_file, String)
    traits = match(r"START_HASH_TRAITS -->(.*)<!-- END_HASH_TRAITS"s, readme).captures[1]
    contexts = match(r"START_CONTEXTS -->(.*)<!-- END_CONTEXTS"s, readme).captures[1]
    # TODO: if we ever generate `Documenter.jl` docs we need to revise the
    # links to symbols here

    @doc """
        StableHashTraits.hash_method(x, [context])

    Retrieve the trait object that indicates how a type should be hashed using `stable_hash`.
    You should return one of the following values.

    $traits

    $contexts
    """ hash_method
end
