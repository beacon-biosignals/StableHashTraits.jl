"""
    CachedHash(context)

Setup a hash context that includes a cache of hash results. It stores the result of hashing
types and large values. Calling the same cached hash context will re-use the this cache,
possibly improving performance. If you do not pass a `CachedHash` to `stalbe_hash` it sets
up its own internal cache to improve performance for repeated hashes of the same type or
large value.

## See Also

[`stable_hash`](@ref)
"""
struct CachedHash{T}
    parent::T
    type_cache::IdDict{Type,Vector{UInt8}}
    value_cache::IdDict{Any,Vector{UInt8}}
    function CachedHash(parent, types=IdDict{Type,Vector{UInt8}}(),
                        values=IdDict{Any,Vector{UInt8}}())
        return new{typeof(parent)}(parent, types, values)
    end
end
CachedHash(x::CachedHash) = x
parent_context(x::CachedHash) = x.parent

function hash_value!(x, hash_state, context, trait)
    return hash_value!(x, hash_state, parent_context(context), trait)
end

"""
    HashShouldCache(x)

Signals that `x` should be cached during a call to [`stable_hash`](@ref). Useful in calls
to [`transformer`](@ref).
"""
struct HashShouldCache{T}
    val::T
end
preserves_structure(::typeof(HashShouldCache)) = true
unwrap(x::HashShouldCache) = x.val
unwrap(x) = x

struct NonCachedHash{T}
    parent::T
end
parent_context(x::NonCachedHash) = x.parent

# we have to somehow decide before hand which things we want to recursively hash and which
# we don't. Many repeated recurisve hashes are expensive, especially for SHA-based hashing,
# this is why we use the BufferedHashState. But it should be okay to recursively hash from
# time to time; calls to `get!` are somewhere on the order of 20-50 times slower than a call
# to hash individual bytes, so as long as CACHE_OBJECT_THRESHOLD is well above this range of
# values, we should be fine (here it is 2^12 = 4096).
const CACHE_OBJECT_THRESHOLD = HASH_BUFFER_SIZE << 2

"""
    hash_value!(x, hash_state, context, trait)

Hash the value of object x to the hash_state for the given context and hash trait.
Caches larger values.
"""
function hash_value!(x::T, hash_state, context::CachedHash, trait) where {T}
    if x isa HashShouldCache || (!isbitstype(T) && sizeof(x) >= CACHE_OBJECT_THRESHOLD)
        bytes = get!(context.value_cache, x) do
            cache_state = similar_hash_state(hash_state)
            stable_hash_helper(unwrap(x), cache_state, NonCachedHash(context), trait)
            return reinterpret(UInt8, asarray(compute_hash!(cache_state)))
        end
        return update_hash!(hash_state, bytes, context)
    else
        stable_hash_helper(x, hash_state, context, trait)
    end
end
# when types are hashed as values, we don't hash them using `hash_value!`, since the methods
# implementing this fallback to calling `hash_type!`
function hash_value!(x::Type, hash_state, context::CachedHash, trait)
    return stable_hash_helper(x, hash_state, context, trait)
end

"""
    hash_type!(hash_state, context, T)

Hash type `T` in the given context to `hash_state`. The result is cached and future
calls to `hash_type!` will hash the cached result.
"""
hash_type!(hash_state, x, key) = hash_type!(hash_state, parent_context(x), key)
function hash_type!(hash_state, context::CachedHash, ::Type{T}) where {T}
    bytes = get!(context.type_cache, T) do
        type_context = TypeHashContext(context)
        transform = transformer(typeof(T), type_context)
        tT = transform(T)
        hash_type_state = similar_hash_state(hash_state)
        hash_type_state = stable_hash_helper(tT, hash_type_state, type_context,
                                             hash_trait(transform, tT))
        bytes = reinterpret(UInt8, asarray(compute_hash!(hash_type_state)))

        return bytes
    end
    return update_hash!(hash_state, bytes, context)
end

struct TypeHashContext{T}
    parent::T
end
TypeHashContext(x::TypeHashContext) = x
parent_context(x::TypeHashContext) = x.parent
hash_type!(hash_state, ::TypeHashContext, key::Type) = hash_state

asarray(x) = [x]
asarray(x::AbstractArray) = x
