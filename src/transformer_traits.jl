#####
##### Helper Functions
#####

hash_trait(x::Transformer, y) = x.result_method
hash_trait(::Transformer{<:Any,Nothing}, y) = hash_trait(y)
hash_trait(x) = StructType(x)

function check_hash_method(x, transform, context)
    # because of how `hash_method` uses `NotImplemented` we can leverage
    # this to check for deprecated API usage
    if is_implemented(hash_method(x, context)) && transform.fn === identity &&
       isnothing(transform.result_method)
        @warn """`hash_method` is implemented for type

           $(typeof(x))

           when in context of type

           $(typeof(context))

           No specialized `transformer` method is defined for this type. This object's
           StableHashTraits customization may be deprecated, and may not work properly for
           HashVersion{3}. If the default method for `transformer` is appropriate, you can
           prevent this warning from appearing by implementing a method similar to the
           following:

           function hash_method(::MyType, context::SomeContextType)
               StableHashTraits.root_version(context) > 2 && return StableHashTraits.NotImplemented()
               # implement `hash_method` for `MyType`
           end
           """ _id = Symbol(qualified_name_(typeof(x))) maxlog = 1
    end
end

# how we hash when we haven't hoisted the type hash out of a loop
function hash_type_and_value(x, hash_state, context)
    transform = transformer(typeof(x), context)::Transformer
    if transform.preserves_structure
        hash_state = hash_type!(hash_state, context, typeof(x))
    end
    tx = transform(x)
    check_hash_method(x, transform, context)
    if !transform.preserves_structure
        hash_state = hash_type!(hash_state, context, typeof(tx))
    end
    return stable_hash_helper(tx, hash_state, context, hash_trait(transform, tx))
end

# how we hash when the type hash can be hoisted out of a loop
function hash_value(x, hash_state, context, transform::Transformer)
    tx = transform(x)
    check_hash_method(x, transform, context)
    return stable_hash_helper(tx, hash_state, context, hash_trait(transform, tx))
end

# There are two cases where we want to hash types:
#
#   1. when we are hashing the type of an object we're hashing (`TypeHashContext`)
#   2. when a value we're hashing is itself a type (`TypeAsValueContext`)
#
# These are handled as separate contexts because the kind of value we want to generate from
# the type may differ. By default only the structure of types matters when hashing an
# objects type, e.g. when we hash a StructTypes.DataType we hash that it is a data type, the
# field names and we hash each individual element type (as per its rules) but we do not hash
# the name of the type. When a type is hashed as a value, its actual name also matters.

#####
##### Type Hashes
#####

"""
    hash_type!(hash_state, context, T)

Hash type `T` in the given context, updating `hash_state`.
"""
function hash_type!(hash_state, context, ::Type{T}) where {T}
    # TODO: cache type hashing in the final release (no this PR)
    type_context = TypeHashContext(context)
    transform = transformer(typeof(T), type_context)
    tT = transform(T)
    hash_type_state = similar_hash_state(hash_state)
    hash_type_state = stable_hash_helper(tT, hash_type_state, type_context,
                                         hash_trait(transform, tT))
    bytes = reinterpret(UInt8, asarray(compute_hash!(hash_type_state)))

    return update_hash!(hash_state, bytes, context)
end
asarray(x) = [x]
asarray(x::AbstractArray) = x

struct TypeHashContext{T}
    parent::T
end
TypeHashContext(x::TypeHashContext) = x
parent_context(x::TypeHashContext) = x.parent
hash_type!(hash_state, ::TypeHashContext, key::Type{<:Type}) = hash_state
hash_type!(hash_state, ::TypeHashContext, key::Type) = hash_state

function transformer(::Type{T}, context::TypeHashContext) where {T<:Type}
    return Transformer(T -> transform_type(T, StructType_(T), parent_context(context)),
                            internal_type_structure(T, StructType_(T)))

end
@inline StructType_(T) = StructType(T)
StructType_(::Type{Union{}}) = StructTypes.NoStructType()

"""
   transform_type(::Type{T}, [context])

The value to hash for type `T` when hashing an object's type. Users of `StableHashTraits`
can implement a method that accepts one (`T`) or two arguments (`T` and `context`). If no
method is implemented, the fallback `transform_type` value uses `StructType(T)` to decide
how to hash `T`; this is documented under [What gets hashed? (hash version 3)](@ref).

Any types returned by `transform_type` has `transform_type` applied to it, so make sure that
you only return types when they are are some nested component of your type (do not return
`T`!!)

This method is used to add additional data to the hash of a type. Internally, the data
listed below is always added, outside of the call to `transform_type`:

- `fieldtypes(T)` of any `StructType.DataType` (e.g. StructType.Struct)
- `eltype(T)` of any `StructType.ArrayType` or `StructType.DictType` or `AbstractRange`
- `ndims(T)` of any `AbstractArray` that is an `StructType.ArrayTYpe` and that has a
  concrete dimension

These components of the type need not be returned by `transform_type` and you cannot prevent
them from being included in a type's hash, since otherwise the assumptions necessary for
efficient hash computation would be violated.

## Examples

### Singleton Types

You can opt in to hashing novel singleton types by overwriting `transform_type`:

```julia
struct MySingleton end
StructTypes.StructType(::MySingleton) = StructTypes.SingletonType()
function StableHashTraits.transform_type(::Type{<:MySingleton})
    return "MySingleton"
end
```
If you do not own the type you wish to customize, you can use a context:

```julia
using AnotherPackage: PackageSingleton
StableHashTriats.@context HashAnotherSingleton
function StableHashTraits.transform_type(::Type{<:PackageSingleton}, ::HashAnotherSingleton)
    return "AnotherPackage.PackageSingleton"
end
context = HashAnotherSingleton(HashVersion{3}())
stable_hash([PackageSingleton(), 1, 2], context) # will not error
```

### Functions

Overwriting `transform_type` can be used to opt-in to hashing functions.

```julia
f(x) = x+1
StableHashTraits.transform_type(::typeof(fn)) = "Main.fn"
```

### Type Parameters

To include additional type parameters in a type's hash, you can overwrite `transform_type`

```julia
struct MyStruct{T,K}
    wrapped::T
end

function StableHashTraits.transform_type(::Type{<:MyStruct{T,K}})
    return "MyStruct", K
end
```

By adding this method for `type_structure` both `K` and `T` will impact the hash, `T`
because it is included in `fieldtypes(<:MyStruct)` and `K` because it is included in
`type_structure(<:MyStruct)`.

If you do not own the type you want to customize, you can specialize `type_structure` using
a specific hash context.

```julia
using Intervals

StableHashTraits.@context IntervalEndpointsMatter

function HashTraits.type_structure(::Type{<:I}, ::IntervalEndpointsMatter) where {T, L, R, I<:Interval{T, L, R}}
    return (L, R)
end

context = IntervalEndpointsMatter(HashVersion{3}())
stable_hash(Interval{Closed, Open}(1, 2), context) !=
    stable_hash(Interval{Open, Closed}(1, 2), context) # true
```

## See Also

[`transformer`](@ref) [`@context`](@ref)
"""
function transform_type(::Type{T}, context) where {T}
    return transform_type(T, parent_context(context))
end
function transform_type(::Type{T}, ::HashVersion{3}) where {T}
    return transform_type_by_trait(T, StructType(T))
end
transform_type_by_trait(::Type, ::S) where {S<:StructTypes.StructType} = parentmodule_nameof(S)


# NOTE: `internal_type_structure` is like `type_structure` in form, but it implements mandatory
# elements of the type structure that are always included; this method should not be
# overwritten by users
internal_type_structure(T, trait) = nothing

#####
##### Hashing Types as Values
#####

struct TypeAsValue <: StructTypes.StructType end
hash_trait(::Type) = TypeAsValue()

struct TypeAsValueContext{T}
    parent::T
end
parent_context(x::TypeAsValueContext) = x.parent

function hash_type!(hash_state, context, ::Type{<:Type})
    return update_hash!(hash_state, "Base.Type", context)
end
function transformer(::Type{<:Type}, context::TypeAsValueContext)
    return Transformer(T -> (transform_type_value(T, context),
                             internal_type_structure(T, StructType_(T))))

end

"""
    transform_type_value(::Type{T}, [trait], [context]) where {T}

The value that is hashed for type `T` when hashing a type as a value (e.g.
`stable_hash(Int)`). Hashing types as values is an error by default, but you can use this
method to opt-in to hashing a type as a value. You can return types (e.g. type parameters of
`T`), but do not return `T` or you will get a stack overflow.

## Example

You can define a method of this function to opt in to hashing your type as a value.

```julia
struct MyType end
StableHashTraits.transform_type_value(::Type{T}) where {T<:MyType} = parentmodule_nameof(T)
stable_hash(MyType) # does not error
```

Likewise, you can opt in to this behavior for a type you don't own by defining a context.

```julia
StableHashTraits.@context HashNumberTypes
function StableHashTraits.type_value_identifier(::Type{T},
                                                ::HashNumberTypes) where {T <: Number}
    return parentmodule_nameof(T)
end
stable_hash(Int, HashNumberTypes(HashVersion{3}())) # does not error
```

## See Also

[`transformer`](@ref)
[`transform_type`](@ref)

"""
function transform_type_value(::Type{T}, context) where {T}
    return transform_type_value(T, parent_context(context))
end
function transform_type_value(::Type{T}, c::HashVersion{3}) where {T}
    if !contains(nameof(T), "#")
        msg = """
        There is not a specific method of `transform_type_value` for type `$T

        If you wish to opt in to hashing of this type as a value, you can implement that as
        follows:

            StableHashTraits.transform_type_value(::$(nameof(T))) = $(parentmodule_nameof(T))

        You are responsible for ensuring this return value is stable following any non-breaking
        updates to the type.

        If you don't own the type, consider using `StableHashTraits.@context`.
        """

        @error msg
    end
    return throw(MethodError(transform_type_value, T))
end

hash_type!(hash_state, ::TypeAsValueContext, ::Type{<:Type}) = hash_state
function stable_hash_helper(::Type{T}, hash_state, context, ::TypeAsValue) where {T}
    type_context = TypeAsValueContext(context)
    transform = transformer(typeof(T), type_context)::Transformer
    tT = transform(T)
    return stable_hash_helper(tT, hash_state, type_context, hash_trait(transform, tT))
end

function stable_hash_helper(::Type{T}, hash_state, context::TypeHashContext,
                            ::TypeAsValue) where {T}
    return hash_type!(hash_state, context, T)
end

#####
##### Function Hashes
#####

# remember: functions can have fields; in general StructTypes doesn't assume these are
# serialized but here we want that to happen by default, so e.g. ==(2) will properly hash
# both the name of `==` and `2`.
hash_trait(x::Function) = StructTypes.UnorderedStruct()

function transform_type(::Type{T}, c::HashVersion{3}) where {T<:Function}
    if !contains(nameof(T), "#")
        msg = """
        There is not a specific method of `transform_type` for `$(function_type_name(T))`.

        If you wish to opt in to hashing of this function, you might implement that as follows:

            StableHashTraits.transform_type(::$(function_type_name(T))) = "$(function_type_name(T))"

        You are responsible for ensuring this return value is stable following any non-breaking
        updates to the type.

        If you don't own this function, consider using `StableHashTraits.@context`.
        """

        @error msg
    end
    return throw(MethodError(transform_type, T))
end

function function_type_name(::Type{T}) where {T}
    if hasproperty(T, :instance) && isdefined(T, :instance)
        return "typeof($(qualified_name_(T.instance)))"
    else
        return qualified_name_(T)
    end
end

#####
##### DataType
#####

transform_type_by_trait(::Type{T}, ::StructType.DataType) where {T} = string(nameof(T))

sorted_field_names(T::Type) = TupleTools.sort(fieldnames(T); by=string)
@generated function sorted_field_names(T)
    return TupleTools.sort(fieldnames(T); by=string)
end

function internal_type_structure(::Type{T}, trait::StructTypes.DataType) where {T}
    if isconcretetype(T)
        fields = trait isa StructTypes.OrderedStruct ? fieldnames(T) : sorted_field_names(T)
        return fields, map(field -> fieldtype(T, field), fields)
    else
        return nothing
    end
end

function stable_hash_helper(x, hash_state, context, st::StructTypes.DataType)
    nested_hash_state = start_nested_hash!(hash_state)

    # hash the field values
    fields = st isa StructTypes.UnorderedStruct ? sorted_field_names(x) :
             fieldnames(typeof(x))
    nested_hash_state = hash_fields(x, fields, nested_hash_state, context)
    hash_state = end_nested_hash!(hash_state, nested_hash_state)
    return hash_state
end

function hash_fields(x, fields, hash_state, context)
    for field in fields
        val = getfield(x, field)
        # can we optimize away the field's type_hash?
        transform = transformer(typeof(val), context)
        if isconcretetype(fieldtype(typeof(x), field)) && transform.preserves_structure
            # the fieldtype has been hashed as part of the type of the container
            hash_value(val, hash_state, context, transform)
        else
            hash_type_and_value(val, hash_state, context)
        end
    end
    return hash_state
end

#####
##### ArrayType
#####

"""
    is_ordered(x)

Indicates whether the order of the elements of object `x` are important to its hashed value.
If false, `x`'s elements will first be `collect`ed and `sort`'ed before hashing them. When
calling `sort`, [`hash_sort_by`](@ref) is passed as the `by` keyword argument.
If `x` is a `DictType`, the elements are sorted by their keys rather than their elements.
"""
is_ordered(x) = true
is_ordered(::AbstractSet) = false

"""
    `hash_sort_by(x)`

Defines how the elements of a hashed container `x` are `sort`ed if [`is_ordered`](@ref) of
`x` returns `false`. The return value of this function is passed to `sort` as the `by`
keyword.
"""
hash_sort_by(x::Symbol) = String(x)
hash_sort_by(x::Char) = string(x)
hash_sort_by(x) = x

function internal_type_structure(::Type{T}, ::StructTypes.ArrayType) where {T}
    return eltype(T)
end

# include ndims in type hash when we can
function transform_type(::Type{T}) where {T<:AbstractArray}
    return transform_type_by_trait(T, StructTypes(T)), ndims_(T)
end
ndims_(::Type{<:AbstractArray{<:Any,N}}) where {N} = N
ndims_(::Type{<:AbstractArray}) = nothing

function transformer(::Type{<:AbstractArray}, ::HashVersion{3})
    return Transformer(x -> (size(x), split_union(x)); preserves_structure=true)
end

split_union(array) = TransformIdentity(array)
# NOTE: this method actually properly handles union splitting for as many splits as julia
# will allow to match to this method, not just two; in the case where the eltype is
# Union{Int, UInt, Char} for instance, M will match to Union{UInt, Char} and the `else`
# branch will properly split out the first type. The returned M_array will then be split
# again, when the `transformer` method above is applied to it.
function split_union(array::AbstractArray{Union{N,M}}) where {N,M}
    # NOTE: when an abstract array is e.g. AbstractArray{Int}, N becomes
    # Int and M is left as undefined, we just need to hash this array
    !@isdefined(M) && return TransformIdentity(array)
    # special case null and singleton-types, since we don't need to hash their content at
    # all
    if StructType(N) isa StructTypes.NullType ||
       StructType(N) isa StructTypes.SingletonType
        isM_array = isa.(array, M)
        return isM_array, convert(AbstractArray{M}, array[isM_array])
    elseif StructType(M) isa StructTypes.NullType ||
           StructType(M) isa StructTypes.SingletonType
        # I'm not actually sure if its possible to hit this `elseif` branch since "smaller"
        # types seem to occur first in the `Union`, but its here since I don't know that
        # this pattern is documented behavior or an implementation detail of the current
        # version of julia, nor do I know if all singleton-types count as smaller than
        # non-singleton types
        isN_array = isa.(array, N)
        return isN_array, convert(AbstractArray{N}, array[isN_array])
    else
        isN_array = isa.(array, N)
        N_array = convert(AbstractArray{N}, array[isN_array])
        M_array = convert(AbstractArray{M}, array[.!isN_array])
        return isN_array, N_array, M_array
    end
end

function stable_hash_helper(xs, hash_state, context, ::StructTypes.ArrayType)
    nested_hash_state = start_nested_hash!(hash_state)

    items = !is_ordered(xs) ? sort!(collect(xs); by=hash_sort_by) : xs
    transform = transformer(eltype(items), context)::Transformer
    nested_hash_state = hash_elements(items, nested_hash_state, context, transform)

    hash_state = end_nested_hash!(hash_state, nested_hash_state)
    return hash_state
end

function hash_elements(items, hash_state, context, transform)
    # can we optimize away the element type hash?
    if isconcretetype(eltype(items)) && transform.preserves_structure
        # the eltype has already been hashed as part of the type structure of
        # the container
        for x in items
            hash_value(x, hash_state, context, transform)
        end
    else
        for x in items
            hash_type_and_value(x, hash_state, context)
        end
    end
    return hash_state
end

#####
##### AbstractRange
#####

transform_type(::Type{<:AbstractRange}) = "Base.AbstractRange"
function transformer(::Type{<:AbstractRange}, ::HashVersion{3})
    Transformer(x -> (first(x), step(x), last(x)); preserves_structure=true)
end

#####
##### Tuples
#####

function internal_type_structure(::Type{T}, ::StructTypes.ArrayType) where {T<:Tuple}
    if isconcretetype(T)
        fields = T <: StructTypes.OrderedStruct ? fieldnames(T) : sorted_field_names(T)
        return fields, map(field -> fieldtype(T, field), fields)
    else
        return nothing
    end
end

function internal_type_structure(::Type{T}, ::StructTypes.ArrayType) where {T<:NTuple}
    return eltype(T)
end

function stable_hash_helper(x::Tuple, hash_state, context, ::StructTypes.ArrayType)
    nested_hash_state = start_nested_hash!(hash_state)
    nested_hash_state = hash_fields(x, fieldnames(typeof(x)), nested_hash_state, context)
    hash_state = end_nested_hash!(hash_state, nested_hash_state)
    return hash_state
end

#####
##### DictType
#####

is_ordered(x::AbstractDict) = false

function internal_type_structure(::Type{T}, ::StructTypes.DictType) where {T}
    return eltype(T)
end

function transformer(::Type{<:Pair}, ::HashVersion{3})
    return Transformer(((a, b),) -> (a, b); preserves_structure=true)
end

function stable_hash_helper(x, hash_state, context, ::StructTypes.DictType)
    pairs = StructTypes.keyvaluepairs(x)
    nested_hash_state = start_nested_hash!(hash_state)

    pairs = if is_ordered(x)
        StructTypes.keyvaluepairs(x)
    else
        sort!(collect(StructTypes.keyvaluepairs(x)); by=hash_sort_by ∘ first)
    end
    transform = transformer(eltype(x), context)::Transformer
    hash_elements(pairs, nested_hash_state, context, transform)

    hash_state = end_nested_hash!(hash_state, nested_hash_state)
    return hash_state
end

#####
##### CustomStruct
#####

# we need to hash the type for every instance when we have a CustomStruct; `lowered` could
# be anything
function stable_hash_helper(x, hash_state, context, ::StructTypes.CustomStruct)
    return hash_type_and_value(StructTypes.lower(x), hash_state, context)
end

#####
##### Basic data types
#####

transform_type(::Type{Symbol}) = "Base.Symbol"
function transformer(::Type{<:Symbol}, ::HashVersion{3})
    return Transformer(String; preserves_structure=true)
end

function stable_hash_helper(str, hash_state, context, ::StructTypes.StringType)
    nested_hash_state = start_nested_hash!(hash_state)
    update_hash!(nested_hash_state, str isa AbstractString ? str : string(str), context)
    return end_nested_hash!(hash_state, nested_hash_state)
end

function stable_hash_helper(number::T, hash_state, context,
                            ::StructTypes.NumberType) where {T}
    U = StructTypes.numbertype(T)
    return update_hash!(hash_state, U(number), context)
end

function stable_hash_helper(bool, hash_state, context, ::StructTypes.BoolType)
    return update_hash!(hash_state, Bool(bool), context)
end

# null types are encoded purely by their type hash
transform_type(::Type{Missing}) where {T} = "Base.Missing"
transform_type(::Type{Nothing}) where {T} = "Base.Nothing"
function transform_type_by_trait(::Type{T}, ::StructTypes.NullType)
    if !contains(nameof(T), "#")
        msg = """
        There is not a specific method of `transform_type` for null-type `$T

        If you wish to opt in to hashing of this type as a value, you can implement that as
        follows:

            StableHashTraits.transform_type(::$(nameof(T))) = $(parentmodule_nameof(T))

        You are responsible for ensuring this return value is stable following any non-breaking
        updates to the type.

        If you don't own the type, consider using `StableHashTraits.@context`.
        """

        @error msg
    end
    return throw(MethodError(transform_type, T))
end
stable_hash_helper(_, hash_state, context, ::StructTypes.NullType) = hash_state

# singleton types are encoded purely by their type hash
function transform_type_by_trait(::Type{T}, ::StructTypes.NullType)
    if !contains(nameof(T), "#")
        msg = """
        There is not a specific method of `transform_type` for singleton-type `$T

        If you wish to opt in to hashing of this type as a value, you can implement that as
        follows:

            StableHashTraits.transform_type(::$(nameof(T))) = $(parentmodule_nameof(T))

        You are responsible for ensuring this return value is stable following any non-breaking
        updates to the type.

        If you don't own the type, consider using `StableHashTraits.@context`.
        """

        @error msg
    end
    return throw(MethodError(transform_type, T))
end
stable_hash_helper(_, hash_state, context, ::StructTypes.SingletonType) = hash_state
