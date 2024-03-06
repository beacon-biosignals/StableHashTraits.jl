struct TransformResult{T}
    value::T
    preserves_types::Bool
end
with_type_structure(val, ::Type{T}) where {T} = transform_structure(val, T, StructType(T))
with_type_structure(val, ::Type{T}, trait) where {T} = TransformResult(val, false)
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
        type_context = TypeHashContext(context)
        transform, traitfn = unwrap(hash_method(typeof(T), type_context))
        tT = transform(T)
        hash_type_state = similar_hash_state(hash_state)
        hash_type_state = stable_hash_helper(tT, hash_type_state, type_context, traitfn(tT))
        bytes = reinterpret(UInt8, asarray(compute_hash!(hash_type_state)))

        return bytes
    end
    return update_hash!(hash_state, bytes)
end

struct TypeHashContext{T}
    parent::T
end
TypeHashContext(x::TypeHashContext) = x
parent_context(x::TypeHashContext) = x.parent
hash_type!(hash_state, ::TypeHashContext, key::Type) = hash_state

asarray(x) = [x]
asarray(x::AbstractArray) = x
