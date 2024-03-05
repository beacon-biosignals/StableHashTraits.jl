struct TransformResult{T}
    value::T
    preserves_structure::Bool
end
with_type_structure(val, ::Type{T}) = transform_structure(val, T, StructType(T))
with_type_structure(val, ::Type{T}, trait) = TransformResult(val, false)
handle_transform(x::TransformResult) = x.value, x.preserves_structure
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
hash_type!(fn, x, key) = hash_type!(fn, parent_context(x), key)
hash_type!(fn, ::Nothing, key) = throw(ArgumentError("`hash_type! is not supported"))
function hash_type!(hash_state, x::CachingContext, key::Type)
    bytes, preserves_structure = return get!(x.type_caches, key) do
        tT, preserves_structure = handle_transform(transform(T, context))

        hash_type_state = similar_hash_state(hash_state)
        type_context = TypeHashContext(context)
        hash_type_state = stable_hash_helper(tT, hash_type_state, type_context,
                                             BitSet(), HashType(tT))
        bytes = reinterpret(UInt8, asarray(compute_hash!(hash_type_state)))

        return bytes, preserves_structure
    end
    return update_hash!(hash_state, bytes), preserves_structure
end

struct TypeHashContext{T}
    parent::T
    TypeHashContext(x::CachingContext) = new{typeof(x.parent)}(x.parent)
    TypeHashContext(x) = new{typeof(x)}(x)
end
parent_context(x::TypeHashContext) = x.parent
transform(::Type{T}, ::TypeHashContext) where {T} = qualified_name_(StructType(T))
hash_type!(fn, hash_state, key) = hash_state, true

asarray(x) = [x]
asarray(x::AbstractArray) = x
