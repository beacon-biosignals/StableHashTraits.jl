# Copy-pasted from BeaconPkgTemplates.jl
# run this script in the `docs` project to fix the doctests if they are out of date
# carefully review the changes before committing!

# TODO: there are as of yet, no doctests. This is because we would still need to setup
# documentation examples to properly work with S3, and setup any hidden boilerplate

# One needs to be careful because `fix=true` will edit the source to fix
# the doctests, and it's good to separate those changes so you can check
# they are correct (and be easily revertable if they do something wrong).

using Documenter, Nabu

DocMeta.setdocmeta!(Nabu, :DocTestSetup, :(using Nabu);
                    recursive=true)

if get(ENV, "CI", "false") == "true" || success(`git diff --quiet`)
    # Uncommment if a special aws configuration is required to run tests (as additionally set in CI)
    # if ismissing(get(ENV, "AWS_PROFILE", missing))
    #     @warn """You may need to set `ENV["AWS_PROFILE"] = nabu-ci` in order to successfully run the doctests"""
    # end
    doctest(Nabu; fix=true)
else
    error("Git repo dirty; commit changes before fixing doctests.")
end
