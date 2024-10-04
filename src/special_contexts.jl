
#####
##### WithTypeNames
#####

"""
    WithTypeNames(parent_context)

In this hash context, [`StableHashTraits.transform_type`](@ref) returns [`module_nameof_string`](@ref) for
all types, in contrast to the default behavior (which mostly uses
`nameof_string(StructType(T))`).

!!! warn "Unstable"
    `module_nameof_string`'s return value can change with non-breaking
    changes if e.g. the module of a function or type is changed because it's considered an
    implementation detail of a package.

"""
@context WithTypeNames

transform_type(::Type{T}, c::WithTypeNames) where {T} = module_nameof_string(T)

# NOTE: from this point below, only the `transformer` and `type_identifier`-related code is
# new

#####
##### TablesEq
#####

"""
    TablesEq(parent_context)

In this hash context the type and structure of a table do not impact the hash that is
created, only the set of columns (as determined by `Tables.columns`), and the hash of the
individual columns matter.
"""
@context TablesEq

function transformer(::Type{T}, c::TablesEq) where {T}
    Tables.istable(T) && return Transformer(columntable)
    return transformer(T, parent_context(c))
end
