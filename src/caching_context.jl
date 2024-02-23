struct CachingContext{T}
    parent::T
    type_caches::IdDict{Type,IdDict}
end

function CachingContext(parent, dict=IdDict{Type,IdDict}())
    return CachingContext(parent, dict)
end

# type_caches maps return-value types to individual dictionaries
# each dictionary maps some type with its associated hash value of the given return value
parent_context(x::CachingContext) = x.parent
function context_cache(x::CachingContext, ::Type{T}) where {T}
    return get!(x.type_caches, T, IdDict{Type,T}())::IdDict{Type,T}
end
