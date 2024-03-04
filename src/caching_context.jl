# when transforming a type we often encode the eltype or the fieldtypes of a type in the
# `transformed` value. We need to be able to signal to downstream hashing machinery that
# this has been down, so that it can avoid hashing those types again
# we encode this information in a `Hashed` wrapper that wraps the output of
# `transform(T)` and the traits returned by `HashType`

@enum HashEncoding::Int begin
    hashes_eltype
    hashes_fieldtypes
end

struct TransformedType{T}
    value::T
    encodings::BitSet
end
function TransformedType(vals, flags::HashEncoding...)
    TransformedType(vals, BitSet((Int(flags),)))
end
function Base.:(*)(x::TransformedType, y::TransformedType)
    return TransformedType((x.value, y.value), union(x.encodings, y.encodings))
end
function Base.:(*)(x, y::TransformedType)
    return TransformedTYpe((x, y.value), union(x.encodings, y.encodings))
end
struct TransformedTypeIdentity end
Base.:(*)(x::TransformedType, y::TransformedTypeIdentity) = x
Base.:(*)(x, y::TransformedTypeIdentity) = TransformedType(x)

struct CachedTypeHash
    bytes::Vector{UInt8}
    flags::BitSet
end

struct CachingContext{T}
    parent::T
    type_caches::IdDict{Type,CachedTypeHash}
    function CachingContext(parent, dict=IdDict{Type,CachedTypeHash}())
        return new{typeof(parent)}(parent, dict)
    end
end
CachingContext(x::CachingContext) = x

# type_caches maps return-value types to individual dictionaries
# each dictionary maps some type with its associated hash value of the given return value
parent_context(x::CachingContext) = x.parent
hash_type!(fn, x, key) = hash_type!(fn, parent_context(x), key)
hash_type!(fn, ::Nothing, key) = throw(ArgumentError("`cache! is not supported"))
function hash_type!(hash_state, x::CachingContext, key::Type)
    bytes, encodings = return get!(x.type_caches, key) do
        hash_type_state = similar_hash_state(hash_state)
        type_context = TypeHashContext(context)
        tT = transform(T, type_context)::TransformedType
        hash_type_state = stable_hash_helper(tT.value, hash_type_state, type_context,
            BitSet(), HashType(tT))
        bytes = reinterpret(UInt8, asarray(compute_hash!(hash_type_state)))
        return bytes, tT.encodings
    end
    return update_hash!(hash_state, bytes), encodings
end

struct TypeHashContext{T}
    parent::T
    TypeHashContext(x::CachingContext) = new{typeof(x.parent)}(x.parent)
    TypeHashContext(x) = new{typeof(x)}(x)
end
parent_context(x::TypeHashContext) = x.parent
transform(::Type{T}, ::TypeHashContext) where {T} = qualified_name_(StructType(T))
hash_type!(fn, hash_state, key) = hash_state, BitSet()

asarray(x) = [x]
asarray(x::AbstractArray) = x
