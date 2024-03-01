struct CachingContext{T}
    parent::T
    type_caches::IdDict{Union{Type, Function},Vector{UInt8}}
    function CachingContext(parent, dict=IdDict{Type,IdDict}())
        return new{typeof(parent)}(parent, dict)
    end
end

# type_caches maps return-value types to individual dictionaries
# each dictionary maps some type with its associated hash value of the given return value
parent_context(x::CachingContext) = x.parent
Base.get!(fn, x::CachingContext, key) = get!(fn, x.type_caches, key)
