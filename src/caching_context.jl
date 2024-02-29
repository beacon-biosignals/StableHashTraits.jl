struct CachingContext{T}
    parent::T
    type_caches::IdDict{Type,Vector{UInt8}}
end

function CachingContext(parent, dict=IdDict{Type,IdDict}())
    return CachingContext(parent, dict)
end

# type_caches maps return-value types to individual dictionaries
# each dictionary maps some type with its associated hash value of the given return value
parent_context(x::CachingContext) = x.parent
get!(fn, x::CachingContext, key) = get!(fn, x.type_caches, key)
