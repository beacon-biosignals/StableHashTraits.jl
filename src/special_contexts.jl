#####
##### TablesEq
#####

"""
    TablesEq(parent_context)

In this hash context the order of columns, and the type of the table do not impact the hash
that is created, only the set of columns (as determined by `Tables.columns`), and the hash
of the individual columns matter.
"""
struct TablesEq{T}
    parent::T
end
TablesEq() = TablesEq(HashVersion{1}())
parent_context(x::TablesEq) = x.parent
function hash_method(x::T, m::TablesEq) where {T}
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

#####
##### ViewsEq
#####

"""
    ViewsEq(parent_context)

Create a hash context where only the contents of an array or string determine its hash: that
is, the type of the array or string (e.g. `SubString` vs. `String`) does not impact the hash
value.
"""
struct ViewsEq{T}
    parent::T
end
ViewsEq() = ViewsEq(HashVersion{1}())
parent_context(x::ViewsEq) = x.parent
# NOTE: using root_version let's us ensure that `ViewsEq` is unchanged when using
# `HashVersion{1}` as a parent or ancestor, but make use of the updated, more optimized API
# for `HashVersion{2}`
function hash_method(::AbstractArray, c::ViewsEq)
    return (root_version(c) > 1 ? @ConstantHash("Base.AbstractArray") :
            PrivateConstantHash("Base.AbstractArray"), FnHash(size), IterateHash())
end
function hash_method(::AbstractString, c::ViewsEq)
    return (root_version(c) > 1 ? @ConstantHash("Base.AbstractString") :
            PrivateConstantHash("Base.AbstractString", WriteHash()), WriteHash())
end
