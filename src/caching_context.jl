# we have to somehow decide before hand which things we want to recursively hash and which
# we don't. Many repeated recurisve hashes are expensive, especially for SHA-based hashing,
# this is why we use the BufferedHashState. But it should be okay to recursively hash from
# time to time; calls to `get!` are somewhere on the order of 20-50 times slower than a call
# to hash individual bytes, so as long as CACHE_OBJECT_THRESHOLD is well above this range of
# values, we should be fine
const CACHE_OBJECT_THRESHOLD = 2^12

"""
    CachedHash(context)

Setup a hash context that includes a cache of hash results. By default, it stores the result
of hashing types and large values. Calling the same cached hash context will re-use this
cache, possibly improving performance. If you do not pass a `CachedHash` to `stable_hash` it
sets up its own internal cache to improve performance for repeated hashes of the same type
or large values seen *within* the call to `stable_hash`.

For an object to be cached you must either signal that it should be, using
[`UseCache`](@ref) or it must be:

- large enough: this is to ensure that calls to retrieve a cached result do not exceed the
  time it takes to simply re-hash the individual bytes of an object. You can refer to the
  constant `CACHE_OBJECT_THRESHOLD` though it is not considered part of the public API and
  may change with future hash versions. (The threshold will not change for a given hash
  version, since changing it can change an object's hashed value).
- mutable: immutable objects are not supported by WeakKeyIdDict. This means that caching
  immutable objects can lead to memory leaks if you don't clean up the cache regularly,
  since they are stored in an IdDict. Note that in practice the large amounts of data are
  usually stored in mutable structures like `Array` and `String`; though immutable
  objects may contain these mutable values.

## See Also

[`stable_hash`](@ref)
"""
struct CachedHash{T}
    parent::T
    # Types have arbitrarily long lifetimes and do not get `finalize`ed; we use a normal
    # id dict with them
    type_cache::IdDict{Type,Vector{UInt8}}
    # we cache `ismutable` values automatically, since they can have finalizers, and so we
    # can use weak keys and avoid memory leaks
    mutable_value_cache::WeakKeyIdDict{Any,Vector{UInt8}}
    # we cache immutable values when the user requests a particular object to be cached via
    # `UseCache`. Such objects cannot be released until the `CacheHash` goes out of
    # scope
    immutable_value_cache::IdDict{Any,Vector{UInt8}}
    # we have a private flag to signal that the cached hash was internally created, or
    # defined by the user
    user_defined::Bool
    function CachedHash(parent, types=IdDict{Type,Vector{UInt8}}(),
                        mutable_values=WeakKeyIdDict{Any,Vector{UInt8}}(),
                        immutable_values=IdDict{Any,Vector{UInt8}}(),
                        user_defined=false)
        return new{typeof(parent)}(parent, types, mutable_values, immutable_values,
                                   user_defined)
    end
end
CachedHash(x::CachedHash) = x
parent_context(x::CachedHash) = x.parent

function hash_value!(x, hash_state, context, trait)
    return hash_value!(x, hash_state, parent_context(context), trait)
end

"""
    StableHashTraits.UseCache(x)

Signal that the hash of `x` should be stored in the cache.

!!! warning "Immutable objects can leak memory"
    If `x` is immutable, caching it will cause the object `x` to be held in memory until the
    cache is garbage collected. `WeakKeyIdDicts` do not support immutable objects. If there is
    no user defined cache, the cache will be garbage collected inside the call to
    [`stable_hash`](@ref). With a user defined hash you will need to make sure your cache
    goes out of scope in a timely fashion to avoid memory leaks.

## See Also

[`transformer`](@ref)

"""
struct UseCache{T}
    val::T
end
preserves_structure(::Type{<:UseCache}) = true
unwrap(x) = x
unwrap(x::UseCache) = x.val

"""
    cache_hash_value!(x, hash_state, context, trait)

Hash the value of object x to the hash_state for the given context and hash trait.
Caches types, larger values and those objects manually flagged to be cached.
"""
function cache_hash_value!(x::T, hash_state, context, trait) where {T}
    return stable_hash_helper(x, hash_state, context, trait)
end
function cache_hash_value!(x::T, hash_state, context::HashVersion{4}, trait) where {T}
    stable_hash_helper(x, hash_state, context, trait)
end
function cache_hash_value!(x::T, hash_state, context::CachedHash, trait) where {T}
    if x isa UseCache || (!(x isa Type) && ismutable(x) && sizeof(unwrap(x)) >= CACHE_OBJECT_THRESHOLD)
        cache = ismutable(x) ? context.mutable_value_cache : context.immutable_value_cache
        bytes = get!(cache, unwrap(x)) do
            cache_state = similar_hash_state(hash_state)
            stable_hash_helper(unwrap(x), cache_state, context, trait)
            return reinterpret(UInt8, asarray(compute_hash!(cache_state)))
        end
        return update_hash!(hash_state, bytes, context)
    else
        stable_hash_helper(x, hash_state, context, trait)
    end
end
# # when types are hashed as values, we don't hash them using `hash_value!`, since the methods
# # implementing this fallback to calling `hash_type`
# function cache_hash_value!(x::Type, hash_state, context::CachedHash, trait)
#     return stable_hash_helper(x, hash_state, context, trait)
# end

"""
    cache_hash_type!(hash_state, context, T)

Hash type `T` in the given context to `hash_state`. The result is cached and future
calls to `cache_hash_type!` will hash the cached result.
"""
function cache_hash_type!(hash_state, context::CachedHash, ::Type{T}) where {T}
    bytes = get!(context.type_cache, T) do
        return hash_type(hash_state, context, T)
    end
    return update_hash!(hash_state, bytes, context)
end
cache_hash_type!(hash_state, x, key) = cache_hash_type!(hash_state, parent_context(x), key)
@inline cache_hash_type!(hash_state, c::TypeHashContext, T::Type) = hash_state
@inline cache_hash_type!(hash_state, c::TypeAsValueContext, T::Type) = hash_state
cache_hash_type!(hash_state, ::HashVersion{4}, key) = hash_type(hash_state, context, key)

asarray(x) = [x]
asarray(x::AbstractArray) = x
