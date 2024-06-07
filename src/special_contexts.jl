const WARN_UNSTABLE = """
!!! warn "Unstable"
    `parentmodule_nameof`'s return value can change with non-breaking changes
    if e.g. the module of a function or type is changed because it's considered
    an implementation detail of a package.
"""

macro checked_context(TypeName)
    quote
        Base.@__doc__ struct $(esc(TypeName)){T}
            parent::T
            function $(esc(TypeName))(parent)
                root_version(parent) < 4 &&
                    throw(ArgumentError("`WithTypeNames` does not support HashVersion 1 or 2"))
                return new{typeof(parent)}(parent)
            end
        end
        StableHashTraits.parent_context(x::$(TypeName)) = x.parent
    end
end

#####
##### HashTypeValues
#####

"""
    HashTypeValues

Hash all types as values, by returningn the value of `parentmodule_nameof`
for [`transform_type_value`](@ref)
"""

#####
##### HashFunctions
#####

"""
    HashFunctions

Hash functions by default, by returning the value of [`parentmodule_nameof`](@ref) for all
`Function` types in [`transform_type`](@ref).

$WARN_UNSTABLE
"""
@checked_context HashFunctions
transform_type(::Type{T}, ::HashFunctions) where {T<:Function} = parentmodule_nameof(T)

#####
##### HashNullTypes
#####

"""
    HashNullTypes

Hash function any type `T` where `StructType(T) isa StructTypes.NullType`
using [`parentmodule_nameof`](@ref).

$WARN_UNSTABLE
"""
@checked_context HashNullTypes
function transform_type(::Type{T}, c::HashNullTypes) where {T}
    if StructType(T) <: StructTypes.NullType
        return parentmodule_nameof(T)
    else
        return transform_type(T, parent(c))
    end
end

#####
##### HashNullTypes
#####

"""
    HashSingletonTypes

Hash function any type `T` where `StructType(T) isa StructTypes.SingletonType`
using [`parentmodule_nameof`](@ref).

$WARN_UNSTABLE
"""
@checked_context HashSingletonTypes
function transform_type(::Type{T}, c::HashSingletonTypes) where {T}
    if StructType(T) <: StructTypes.SingletonType
        return parentmodule_nameof(T)
    else
        return transform_type(T, parent(c))
    end
end

#####
##### WithTypeNames
#####

"""
    WithTypeNames(parent_context)

In this hash context, [`transform_type`](@ref) returns `parentmodule_nameof` for all types.
This makes functions and singleton types hashable, and it means the kind of array or
dictionary you use impacts the hash.

$WARN_UNSTABLE

"""
@checked_context WithTypeNames
transform_type(::Type{T}, c::WithTypeNames) where {T} = parentmodule_nameof(T)

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
struct TablesEq{T}
    parent::T
end
TablesEq() = TablesEq(HashVersion{1}())
parent_context(x::TablesEq) = x.parent
function hash_method(x::T, m::TablesEq) where {T}
    root_version(m) > 2 && return NotImplemented()
    if Tables.istable(T)
        # NOTE: using root_version let's us ensure that `TableEq` is unchanged when using
        # `HashVersion{1}` as a parent or ancestor, but make use of the updated, more
        # optimized API for `HashVersion{2}`
        return (root_version(m) > 1 ? @ConstantHash("Tables.istable") :
                PrivateConstantHash("Tables.istable"),
                FnHash(Tables.columns, StructHash(Tables.columnnames => Tables.getcolumn)))
    end
    return hash_method(x, parent_context(m))
end

function transform_type(::Type{T}, ::StructTypes.DataType, context::TablesEq) where {T}
    if Tables.istable(T)
        return "Tables.istable"
    else
        transform_type(T, parent_context(context))
    end
end

function transformer(::Type{T}, c::TablesEq) where {T}
    Tables.istable(T) && return Transformer(columntable)
    return transformer(T, parent_context(c))
end

#####
##### ViewsEq
#####

"""
    ViewsEq(parent_context)

Create a hash context where only the contents of an array or string determine its hash: that
is, the type of the array or string (e.g. `SubString` vs. `String`) does not impact the hash
value.

!!! warn "Deprecated"
    In HashVersion{4} this is already true, so there is no need for `ViewsEq`. This
    does not change the behavior of `HashVersion{4}` or later.
"""
struct ViewsEq{T}
    parent::T
    function ViewsEq(x::T) where {T}
        Base.depwarn("`ViewsEq` is no longer necessary, as only the deprecated hash " *
                     "versions hash array views to un-equal values with arrays.", :ViewsEq)
        return new{T}(x)
    end
end
ViewsEq() = ViewsEq(HashVersion{1}())
parent_context(x::ViewsEq) = x.parent
# NOTE: using root_version let's us ensure that `ViewsEq` is unchanged when using
# `HashVersion{1}` as a parent or ancestor, but make use of the updated, more optimized API
# for `HashVersion{2}`
function hash_method(::AbstractArray, c::ViewsEq)
    root_version(c) > 2 && return NotImplemented()
    return (root_version(c) > 1 ? @ConstantHash("Base.AbstractArray") :
            PrivateConstantHash("Base.AbstractArray"), FnHash(size), IterateHash())
end
function hash_method(::AbstractString, c::ViewsEq)
    root_version(c) > 2 && return NotImplemented()
    return (root_version(c) > 1 ? @ConstantHash("Base.AbstractString") :
            PrivateConstantHash("Base.AbstractString", WriteHash()), WriteHash())
end
# NOTE: Views are already equal in HashVersion 4+, so we don't need a `transform` method
# here
