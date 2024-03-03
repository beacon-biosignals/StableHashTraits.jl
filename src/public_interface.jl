# NOTE: same code as old `StableHashTraits.jl`

"""
    HashVersion{V}()

The default `hash_context` used by `stable_hash`. There are currently two versions
(1 and 2). Version 2 is far more optimized than 1 and should generally be used in newly
written code. Version 1 is the default version, so as to avoid changing the hash computed
by existing code.

By explicitly passing this hash version in `stable_hash` you ensure that hash values for
these fallback methods will not change even if new fallbacks are defined.
"""
struct HashVersion{V}
    function HashVersion{V}() where {V}
        V < 3 &&
            Base.depwarn("HashVersion{T} for T < 3 are deprecated, favor `HashVersion{3}` in " *
                         "all cases where backwards compatible hash values are not " *
                         "required.", :HashVersion)
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
best to pass an explicit version, since `HashVersion{2}` is generally faster than
`HashVersion{1}`. If the fallback methods change in a future release, the hash you get
by passing an explicit `HashVersion{N}` should *not* change. (Note that the number in
`HashVersion` does not necessarily match the package version of `StableHashTraits`).

Instead of passing a context, you can instead pass a `version` keyword, that will
set the context to `HashVersion{version}()`.

To change the hash algorithm used, pass a different function to `alg`. It accepts any `sha`
related function from `SHA` or any function of the form `hash64(x::AbstractArray{UInt8},
[old_hash])`.

The `context` value gets passed as the second argument to [`hash_method`](@ref), and as the
third argument to [`StableHashTraits.write`](@ref)

"""
stable_hash(x; alg=sha256, version=1) = return stable_hash(x, HashVersion{version}(); alg)
function stable_hash(x, context; alg=sha256)
    if root_version(context) < 3
        return compute_hash!(stable_hash_helper(x, HashState(alg, context), context,
                                                hash_method(x, context)))
    else
        context = CachingContext(context)
        hash_state = HashState(alg, context)
        hash_state = stable_type_hash(typeof(x), hash_state, context, HashType(x))
        tx = transform(x, context)
        hash_state = stable_hash_helper(tx, hash_state, context, HashType(tx))
        return compute_hash!(hash_state)
    end
end

transform(x, context) = transform(x, parent_context(context))
transform(x, ::Nothing) = transform(x)
transform(x) = x
transform(::Type{T}) where {T} = transform_type(T, StructType(T))

function stable_hash_helper(x, hash_state, context, method)
    throw(ArgumentError("Unrecognized hash method of type `$(typeof(method))` when " *
                        "hashing object $x. The implementation of `hash_method` for this " *
                        "object is invalid."))
    return nothing
end
