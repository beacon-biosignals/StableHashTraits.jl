struct TransformResult{T}
    value::T
    preserves_types::Bool
end
with_type_structure(val, ::Type{T}) = transform_structure(val, T, StructType(T))
with_type_structure(val, ::Type{T}, trait) = TransformResult(val, false)
handle_transform(x::TransformResult) = x.value, x.preserves_types
handle_transform(x) = x, false

struct CachingContext{T}
    parent::T
    type_caches::IdDict{Type,Tuple{Vector{UInt8},Bool}}
    function CachingContext(parent, dict=IdDict{Type,Tuple{Vector{UInt8},Bool}}())
        return new{typeof(parent)}(parent, dict)
    end
end
CachingContext(x::CachingContext) = x

parent_context(x::CachingContext) = x.parent
hash_type!(hash_state, x, key) = hash_type!(hash_state, parent_context(x), key)
hash_type!(hash_state, ::Nothing, key) = throw(ArgumentError("`hash_type! is not supported"))
function hash_type!(hash_state, x::CachingContext, ::Type{T}) where T
    bytes = return get!(x.type_caches, T) do
        transform = transformer(typeof(T), context)
        tT = transform(T, context)
        hash_type_state = similar_hash_state(hash_state)
        type_context = TypeHashContext(context)
        hash_type_state = stable_hash_helper(tT, hash_type_state, type_context, HashType(tT))
        bytes = reinterpret(UInt8, asarray(compute_hash!(hash_type_state)))

        return bytes
    end
    return update_hash!(hash_state, bytes)
end
function stable_hash_helper(::Type{T}, hash_state, context::TypeHashContext, ::TypeAsValue) where {T}
    return hash_type!(hash_state, context, T)
end

struct TypeHashContext{T}
    parent::T
    TypeHashContext(x::CachingContext) = new{typeof(x.parent)}(x.parent)
    TypeHashContext(x) = new{typeof(x)}(x)
end
parent_context(x::TypeHashContext) = x.parent
hash_type!(hash_state, ::TypeHashContext, key::Type) = hash_state

asarray(x) = [x]
asarray(x::AbstractArray) = x
