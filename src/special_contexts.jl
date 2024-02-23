# NOTE: same code as old `StableHashTraits.jl` excepting new `transform` implementation

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

function transform(x::T, context::TablesEq) where T
    if Tables.istable(T)
        cols = Tables.columns(x)
        keys = Tables.columnnames(cols)
        return (@hash64("Tables.istable"), collect(keys),
                [Tables.getcolumn(cols, c) for c in keys])
    else
        transform(x, parent_context(context))
    end
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
    function ViewsEq(x::T) where {T}
        Base.depwarn("`ViewsEq` is no longer necessary, as only the deprecated hash "*
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
    return (root_version(c) > 1 ? @ConstantHash("Base.AbstractArray") :
            PrivateConstantHash("Base.AbstractArray"), FnHash(size), IterateHash())
end
function hash_method(::AbstractString, c::ViewsEq)
    return (root_version(c) > 1 ? @ConstantHash("Base.AbstractString") :
            PrivateConstantHash("Base.AbstractString", WriteHash()), WriteHash())
end
# NOTE: Views are already equal in HashVersion 3+, so we don't need a `transform` method
# here
