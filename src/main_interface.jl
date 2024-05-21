"""
    HashVersion{V}()

The default `hash_context` used by `stable_hash`. There are currently three versions (1-3).
Version 3 is the recommended version. Version 1 is the default version, so as to avoid
changing the hash computed by existing code.

By explicitly passing this hash version in `stable_hash` you ensure that hash values for
these fallback methods will not change even if new fallbacks are defined.

!!! danger
    Hash version 1 and 2 have been found to depend on the module in which they are first
    executed (cf [#64](https://github.com/beacon-biosignals/StableHashTraits.jl/pull/64));
    to avoid hash instability, use version 3.
"""
struct HashVersion{V}
    function HashVersion{V}() where {V}
        if !(V == 3)
            Base.depwarn("HashVersion{V} for V < 3 is deprecated, favor " *
                         "`HashVersion{3}` in all cases where backwards compatible " *
                         "hash values are not required. Versions 1 and 2 have been found to depend on " *
                         "the module in which they were first executed (cf [#64](https://github.com" *
                         "/beacon-biosignals/StableHashTraits.jl/pull/64))", :HashVersion)
        end
        return new{V}()
    end
end

"""
    stable_hash(x, context=HashVersion{1}(); alg=sha256)
    stable_hash(x; alg=sha256, version=1)

Create a stable hash of the given objects. As long as the context remains the same, this is
intended to remain unchanged across julia versions. How each object is hashed is determined
by [`hash_method`](@ref), which aims to have sensible fallbacks.

To ensure the greatest stability, you should explicitly pass the context object. It is also
best to pass an explicit version, since `HashVersion{3}` is recommended over the earlier
versions. If the fallback methods change in a future release, the hash you get by passing an
explicit `HashVersion{N}` should *not* change. (Note that the number in `HashVersion` does
not necessarily match the package version of `StableHashTraits`).

Instead of passing a context, you can instead pass a `version` keyword, that will set the
context to `HashVersion{version}()`.

To change the hash algorithm used, pass a different function to `alg`. It accepts any `sha`
related function from `SHA` or any function of the form `hash(x::AbstractArray{UInt8},
[old_hash])`.

The `context` value gets passed as the second argument to [`hash_method`](@ref), and as the
third argument to [`StableHashTraits.write`](@ref)

!!! danger
    Hash version 1 and 2 have been found to depend on the module in which they are first
    executed (cf [#64](https://github.com/beacon-biosignals/StableHashTraits.jl/pull/64));
    to avoid hash instability, use version 3.
"""
stable_hash(x; alg=sha256, version=1) = return stable_hash(x, HashVersion{version}(); alg)
function stable_hash(x, context; alg=sha256)
    return compute_hash!(stable_hash_helper(x, HashState(alg, context), context,
                                            hash_method(x, context)))
end
