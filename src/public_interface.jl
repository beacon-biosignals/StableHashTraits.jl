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

To ensure the greatest stability, you should explicitly pass the context object. It is also
best to pass an explicit version, since `HashVersion{3}` is the only non-deprecated version;
it is much faster than 1 and more stable than 2. Furthermore, a new hash version is provided
in a future release, the hash you get by passing an explicit `HashVersion{N}` should *not*
change. (Note that the number in `HashVersion` does not necessarily match the package
version of `StableHashTraits`).

In hash version 3, you customize how hashes are computed using [`transformer`](@ref), and in
versions 1-2 using [`hash_method`](@ref).

Instead of passing a context, you can instead pass a `version` keyword that will set the
context to `HashVersion{version}()`.

To change the hash algorithm used, pass a different function to `alg`. It accepts any `sha`
related function from `SHA` or any function of the form `hash64(x::AbstractArray{UInt8},
[old_hash])`.

The `context` value gets passed as the second argument to [`hash_method`](@ref), and as the
third argument to [`StableHashTraits.write`](@ref)

## See Also

[`transformer`](@ref)
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
    StableHashTraits.parent_context(context)

Return the parent context of the given context object. (See [`hash_method`](@ref) for
details of using context). The default method falls back to returning `HashVersion{1}`, but
this is flagged as a deprecation warning; in the future it is expected that all contexts
define this method.

This is normally all that you need to know to implement a new context. However, if your
context is expected to be the root context—one that does not fallback to any parent (akin to
`HashVersion`)—then there may be a bit more work involved. In this case, `parent_context`
should return `nothing`. You will also need to define
[`StableHashTraits.root_version`](@ref).
"""
function parent_context(x::Any)
    Base.depwarn("You should explicitly define a `parent_context` method for context " *
                 "`$x`. See details in the docstring of `hash_method`.", :parent_context)
    return HashVersion{1}()
end

"""
    StableHashTraits.Transformer(fn=identity, result_method=nothing;
                                 preserves_structure=StableHashTraits.preserves_structure(fn))

Wraps the function used to transform values before they are hashed. The function is applied
(`fn(x)`), and then its result is hashed according to the trait `@something result_method
StructType(fn(x))`.

The flag `preserves_structure` indicates if it is safe to hoist type hashes outside of
loops; this is always the case when `fn` is type stable. See the manual for details about
other cases when it is safe to set this flag to true.

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

Returns true if it is known that `fn` preservess structure ala [`Transformer`](@ref). This
is false by default for all functions but `identity`. You can define a method of this
function for your own fn's to signal that they their results can be safely optimized via
hoisting the type hash outside of loops during hashing.
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

"""
    stable_type_name(::Type{T})
    stable_type_name(T::Module)
    stable_type_name(::T) where {T}

Get a stable name of `T`. The stable name includes the name of the module that `T` was
defined in. Any uses of `Core` are replaced with `Base` to keep the name stable across
versions of julia. Anonymous names (e.g. `stable_type_name(x -> x+1)`) throw an error, as no
stable name is possible in this case.
"""
stable_type_name(x) = qualified_name_(x)

"""
    StableHashTraits.TransformIdentity(x)

Signal that the type `x` should not be transformed in the usual way, but by hashing `x`
directly. This is useful when you want to hash both `x` the way it would normally be hashed
without a specialized method of [`transformer`](@ref) along with some metadata. Without this
wrapper, returning `(metadata(x), x)` from the transforming function would cause an infinite
regress (adding `metadata(x)` upon each call).

## Example

```julia
struct MyArray <: AbstractVector{Int}
    data::Vector{Int}
    meta::Dict{String, String}
end
# other array methods go here...
StableHashTraits.transformer(::Type{<:MyArray}) = Transformer(x -> (x.meta, TransformIdentity(x)))
```

In this example we hash both some metadata about a custom array, and each of the elements of
`x`
"""
struct TransformIdentity{T}
    val::T
end
function transformer(::Type{<:TransformIdentity}, ::HashVersion{3})
    return Transformer(x -> x.val; preserves_structure=true)
end

function stable_hash_helper(x, hash_state, context, trait)
    throw(ArgumentError("Unrecognized trait of type `$(typeof(trait))` when " *
                        "hashing object $x. The implementation of `transformer` for this " *
                        "object provides an invalid second argument."))
    return
end
