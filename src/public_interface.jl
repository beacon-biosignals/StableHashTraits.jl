# NOTE: same code as old `StableHashTraits.jl`

"""
    HashVersion{V}()

The default `hash_context` used by `stable_hash`. There are currently three versions (1-3).
Version 3 should be favored when at all possible. Version 1 is the default version, so as to
avoid changing the hash computed by existing code.

By explicitly passing this hash version in `stable_hash` you ensure that hash values for
these fallback methods will not change even if new hash versions are developed.
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
intended to remain unchanged across julia versions.

Behavior with hash version 1 or 2 is deprecated. Favor version 3 in all cases where possible.

To ensure the greatest stability, you should explicitly pass the context object. It is also
best to pass an explicit version, since `HashVersion{3}` is generally faster than
`HashVersion{1}`. If the fallback methods change in a future release, the hash you get by
passing an explicit `HashVersion{N}` should *not* change. (Note that the number in
`HashVersion` does not necessarily match the package version of `StableHashTraits`).

Instead of passing a context, you can instead pass a `version` keyword, that will set the
context to `HashVersion{version}()`.

To change the hash algorithm used, pass a different function to `alg`. It accepts any `sha`
related function from `SHA` or any function of the form `hash64(x::AbstractArray{UInt8},
[old_hash])`.

The `context` value gets passed as the second argument to [`hash_method`](@ref), and as the
third argument to [`StableHashTraits.write`](@ref)

"""
stable_hash(x; alg=sha256, version=1) = return stable_hash(x, HashVersion{version}(); alg)
function stable_hash(x, context; alg=sha256)
    if root_version(context) < 3
        return compute_hash!(deprecated_hash_helper(x, HashState(alg, context), context,
                                                    hash_method(x, context)))
    else
        hash_state = hash_type_and_value(x, HashState(alg, context),
                                         CachedHash(context))
        return compute_hash!(hash_state)
    end
end

"""
    StableHashTraits.Transformer(fn=identity, result_method=nothing;
                                 preserves_structure=StableHashTraits.preserves_structure(fn))

Wraps the function used to transform values before they are hashed.
The function is applied (`fn(x)`), and then its result is hashed according to
the trait `@something result_method StructType(fn(x))`.

The flag `preserves_structure` indicates if it is safe to hoist type hashes
outside of loops, such as when `fn` is type stable. See the documentation
manual for more details.

## See Also

[`transformer`](@ref)
"""
struct Transformer{F,H}
    fn::F
    result_method::H # if non-nothing, apply to result of `fn`
    preserves_structure::Bool
    function Transformer(fn::Base.Callable=identity, result_method=nothing;
                         preserves_structure=StableHashTraits.preserves_structure(fn))
        return new{typeof(fn),typeof(result_method)}(fn, result_method, preserves_structure)
    end
end

"""
    StableHashTraits.preserves_structure(fn)

Returns true if it is known that `fn` preservess structure ala [`Transformer`](@ref)
This is false by default for all functions but `identity`. You can define a method of this
function for your own fn's to signal that they their results can be safely optimized
during hashing.
"""
preserves_structure(::typeof(identity)) = true
preserves_structure(::Function) = false
(tr::Transformer)(x) = tr.fn(x)

"""
    StableHashTraits.transformer(::Type{T}, [context]) where {T}

Return [`Transformer`](@ref) indicating how to modify an object of type `T` before
hashing it. Methods without a `context` are called if no method for that type
exists for any specific `context` object.
"""
transformer(::Type{T}, context) where {T} = transformer(T, parent_context(context))
transformer(::Type{T}, ::HashVersion{3}) where {T} = transformer(T)
transformer(x) = Transformer()

struct TransformIdentity{T}
    val::T
end
HashType(x::TransformIdentity) = StructTypes.StructType(x.val)
function transformer(::Type{<:TransformIdentity}, ::HashVersion{3})
    Transformer(x -> x.val; preserves_structure=true)
end

function stable_hash_helper(x, hash_state, context, trait)
    throw(ArgumentError("Unrecognized trait of type `$(typeof(trait))` when " *
                        "hashing object $x. The implementation of `transformer` for this " *
                        "object provides an invalid second argument."))
    return
end
