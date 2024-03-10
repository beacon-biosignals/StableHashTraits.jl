struct TransformResult{T}
    value::T
    preserves_structure::Bool
end
with_type_structure(val, ::Type{T}) where {T} = transform_structure(val, T, StructType(T))
with_type_structure(val, ::Type{T}, trait) where {T} = TransformResult(val, false)
handle_transform(x::TransformResult) = x.value, x.preserves_structure
handle_transform(x) = x, false

struct CachingHashContext{T}
    parent::T
    type_cache::IdDict{Type,Vector{UInt8}}
    value_cache::IdDict{Any,Vector{UInt8}}
    function CachingHashContext(parent, types=IdDict{Type,Vector{UInt8}}(),
                                values=IdDict{Any,Vector{UInt8}}())
        return new{typeof(parent)}(parent, types, values)
    end
end
CachingHashContext(x::CachingHashContext) = x

function hash_value!(hash_state, context, x, trait)
    hash_value!(hash_state, parent_context(context), x, trait)
end

struct CacheShouldHash{T}
    val::T
end

# we have to somehow decide before seeing the full tree of objects which things we want to
# recurisvley hash and which we don't. Many repeated recurisve hashes are expensive,
# especially for SHA-based hashing, this is why we use the BufferedHashState. But it should
# be okay to recursively hash from time to time, so we just pick a somewhat arbitrary
# threshold for when to start recursively hashing.

const CACHE_OBJECT_THRESHOLD = 2^13

function hash_value!(hash_state, context::CachingHashContext, x::T, trait) where {T}
    if x isa CacheShouldHash || sizeof(x) >= CACHE_OBJECT_THRESHOLD
        bytes = get!(context.value_cache, x) do
            cache_state = similar_hash_state(hash_state)
            stable_hash_helper(x, cache_state, context, trait)
            return reinterpret(UInt8, asarray(compute_hash!(cache_state)))
        end
        return update_hash!(hash_state, bytes, context)
    else
        stable_hash_helper(x, hash_state, context, trait)
    end
end

parent_context(x::CachingHashContext) = x.parent
hash_type!(hash_state, x, key) = hash_type!(hash_state, parent_context(x), key)
function hash_type!(hash_state, ::Nothing, key)
    throw(ArgumentError("`hash_type! is not supported"))
end
function hash_type!(hash_state, context::CachingHashContext, ::Type{T}) where {T}
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
