#####
##### Helper Functions
#####

hash_trait(x::Transformer, y) = x.result_method
hash_trait(::Transformer{<:Any,Nothing}, y) = hash_trait(y)
hash_trait(x) = StructType(x)

# how we hash when we haven't hoisted the type hash out of a loop
function hash_type_and_value(x, hash_state, context)
    transform = transformer(typeof(x), context)::Transformer
    if transform.preserves_structure
        hash_state = hash_type!(hash_state, context, typeof(x))
    end
    tx = transform(x)
    if !transform.preserves_structure
        hash_state = hash_type!(hash_state, context, typeof(tx))
    end
    return hash_value!(tx, hash_state, context, hash_trait(transform, tx))
end

# how we hash when the type hash can be hoisted out of a loop
function hash_value(x, hash_state, context, transform::Transformer)
    tx = transform(x)
    return hash_value!(tx, hash_state, context, hash_trait(transform, tx))
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

function transformer(::Type{T}, context::TypeHashContext) where {T<:Type}
    return Transformer(T -> (type_hash_name(T, StructType_(T), context),
                             type_structure(T, StructType_(T), context)))
end
@inline StructType_(T) = StructType(T)
StructType_(::Type{Union{}}) = StructTypes.NoStructType()

"""
    type_hash_name(::Type{T}, trait, [context])

The name that is hashed for type `T` when hashing the type of a given value. This defaults
to `stable_name(trait)`. Users of `StableHashTraits` can implement a method that accepts two
(`T` and `trait`) or three arguments (`T`, `trait`, `context`). The trait is one of the
`StructTypes` traits and `context` is the hash context (as per the second argument to
`stable_hash`)
"""
function type_hash_name(::Type{T}, trait, context) where {T}
    return type_hash_name(T, trait, parent_context(context))
end
type_hash_name(::Type{T}, trait, ::Nothing) where {T} = type_hash_name(T, trait)
type_hash_name(::Type{T}, trait) where {T} = qualified_name_(trait)

"""
    type_structure(::Type{T}, trait, [context])

Get the types and symbols that represent the structure of `T`. This should return the
relevant, contained types from `T` that should be hashed. The trait is one of the
`StructTypes` traits and `context` is the hash context (as per the second argument to
`stable_hash`). The second must be included as part of a method definition, but `context` is
optional.

For example, this is the definition for `ArrayType` objects.

```julia
function type_structure(::Type{T}, ::StructTypes.ArrayType) where {T}
    return eltype(T)
end
```

You need to override this method when a type parameter of `T` is important to the type's
hash but is not included in `fieldtypes(T)`. For example:

```julia
struct MyType{T,F}
    obj::T
end
StableHashTratis.type_structure(::Type{T}, ::StructTypes.DataType) where {F,T<:MyType{<:Any,F}}
    return fieldnames(T), fieldtypes(T), F
end
```

Without this definition `MyType{Int,:foo}(1)` would hash to the same value as
`MyType{Int,:bar}(2)`.

!!! warn "Hash all expected type structure!" Overloading `type_structure` improperly can
    cause the assumptions of type-hash-hoisting to be violated. You *must*: - return
    `fieldtypes` as part of `StructTypes.DataType` - return `eltype` as part of
    `StructType.ArrayType` - return `eltype` of `StructTypes.keyvaluepairs` of a
    `StructTypes.DictType` Or the hashes of your type may collied in unexpected ways.

"""
function type_structure(::Type{T}, trait, context) where {T}
    return type_structure(T, trait, parent_context(context))
end
function type_structure(::Type{T}, trait, ::HashVersion{3}) where {T}
    return type_structure(T, trait)
end
type_structure(T, trait) = nothing

qualified_name_(fn::Function) = qname_(fn, nameof)
qualified_name_(x::T) where {T} = qname_(T <: DataType ? x : T, nameof)
qname_(T, name) = validate_name(cleanup_name(string(parentmodule(T), '.', name(T))))

function validate_name(str)
    if occursin("#", str)
        throw(ArgumentError("Anonymous types (those containing `#`) cannot be hashed " *
                            "to a reliable value: found type $str"))
    end
    return str
end

#####
##### Hashing Types as Values
#####

struct TypeAsValue end
hash_trait(::Type) = TypeAsValue()

struct TypeAsValueContext{T}
    parent::T
end
parent_context(x::TypeAsValueContext) = x.parent

function hash_type!(hash_state, context::CachedHash, ::Type{<:Type})
    return update_hash!(hash_state, "Base.Type", context)
end
function transformer(::Type{<:Type}, context::TypeAsValueContext)
    return Transformer(T -> (type_value_name(T, context),
                             type_structure(T, StructType_(T), context)))
end

"""
    type_value_name(::Type{T}, trait, [context]) where {T}

The name that is hashed for type `T` when hashing a type as a value (e.g.
`stable_hash(Int)`). This defaults to `stable_name(trait)`. Users of `StableHashTraits` can
implement a method that accepts two (`T` and `trait`) or three arguments (`T`, `trait`,
`context`). The trait is one of the `StructTypes` traits and `context` is the hash context
(as per the second argument to `stable_hash`)
"""
function type_value_name(::Type{T}, trait, context) where {T}
    return type_value_name(T, trait, parent_context(context))
end
type_value_name(::Type{T}, trait, ::Nothing) where {T} = type_value_name(T, trait)
type_value_name(::Type{T}, trait) where {T} = type_value_name(T)
type_value_name(::Type{T}) where {T} = qualified_name_(T)
type_value_name(::Type{Union{}}) = "Base.Union{}"

hash_type!(hash_state, ::TypeAsValueContext, T) = hash_state
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
# serialized but here we want that to happen by default
function transformer(::Type{<:Function}, ::HashVersion{3})
    return Transformer(identity, StructTypes.UnorderedStruct())
end

type_hash_name(::Type{T}, ::StructTypes.NoStructType) where {T<:Function} = function_type_name(T)
type_value_name(::Type{T}, ::StructTypes.NoStructType) where {T<:Function} = function_type_name(T)

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

sorted_field_names(T::Type) = TupleTools.sort(fieldnames(T); by=string)
@generated function sorted_field_names(T)
    return TupleTools.sort(fieldnames(T); by=string)
end

function type_structure(::Type{T}, trait::StructTypes.DataType) where {T}
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
            # the fieldtype has been hashed as part of the type of the caller
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

is_ordered(x) = true
is_ordered(::AbstractSet) = false
order_by(x::Symbol) = String(x)
order_by(x::Char) = string(x)
order_by(x) = x

function type_structure(::Type{T}, ::StructTypes.ArrayType) where {T}
    return eltype(T)
end

# include ndims in type hash when we can
function type_structure(::Type{T}, ::StructTypes.ArrayType) where {T<:AbstractArray}
    return eltype(T), ndims_(T)
end
ndims_(::Type{<:AbstractArray{<:Any,N}}) where {N} = N
ndims_(::Type{<:AbstractArray}) = nothing

function transformer(::Type{<:AbstractArray}, ::HashVersion{3})
    return Transformer(x -> (size(x), TransformIdentity(x)); preserves_structure=true)
end
function transformer(::Type{<:AbstractRange}, ::HashVersion{3})
    return Transformer(identity, StructTypes.Struct(); preserves_structure=true)
end

# handle the simplest and most common cases of union splitting
# arrays of null-type and another type
function split_union(array::AbstractArray{Union{N, M}}) where {N, M}
    isM_array = isa.(array, M)
    return isM_array, array[isM_array]
end

function transformer(::Type{<:AbstractArray{Union{N,<:Any}}}, ::HashVersion{3}) where {N}
    if StructType(N) isa StructTypes.NullType
        return Transformer(x -> (size(x), split_union(x)); preserves_structure=true)
    else
        return Transformer(x -> (size(x), TransformIdentity(x)); preserves_structure=true)
    end
end

function stable_hash_helper(xs, hash_state, context, ::StructTypes.ArrayType)
    nested_hash_state = start_nested_hash!(hash_state)

    items = !is_ordered(xs) ? sort!(collect(xs); by=order_by) : xs
    transform = transformer(eltype(items), context)::Transformer
    nested_hash_state = hash_elements(items, nested_hash_state, context, transform)

    hash_state = end_nested_hash!(hash_state, nested_hash_state)
    return hash_state
end

function hash_elements(items, hash_state, context, transform)
    # can we optimize away the element type hash?
    if isconcretetype(eltype(items)) && transform.preserves_structure
        # the eltype has already been hashed as part of the type structure of
        # the caller
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
##### Tuples
#####

function type_structure(::Type{T}, ::StructTypes.ArrayType) where {T<:Tuple}
    if isconcretetype(T)
        fields = T <: StructTypes.OrderedStruct ? fieldnames(T) : sorted_field_names(T)
        return fields, map(field -> fieldtype(T, field), fields)
    else
        return nothing
    end
end

function type_structure(::Type{T}, ::StructTypes.ArrayType) where {T<:NTuple}
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

keytype(::Type{<:Pair{K,T}}) where {K,T} = K
valtype(::Type{<:Pair{K,T}}) where {K,T} = T

function type_structure(::Type{T}, ::StructTypes.DictType) where {T}
    return eltype(T)
end

function transformer(::Type{<:Pair}, ::HashVersion{3})
    Transformer(((a, b),) -> (a, b); preserves_structure=true)
end

function stable_hash_helper(x, hash_state, context, ::StructTypes.DictType)
    pairs = StructTypes.keyvaluepairs(x)
    nested_hash_state = start_nested_hash!(hash_state)

    pairs = if is_ordered(x)
        StructTypes.keyvaluepairs(x)
    else
        sort!(collect(StructTypes.keyvaluepairs(x)); by=order_by ∘ first)
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

type_hash_name(::Type{Symbol}, ::StructTypes.StringType) = "Base.Symbol"
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
type_hash_name(::Type{T}, ::StructTypes.NullType) where {T} = qualified_name_(T)
stable_hash_helper(_, hash_state, context, ::StructTypes.NullType) = hash_state

# singleton types are encoded purely by their type hash
type_hash_name(::Type{T}, ::StructTypes.SingletonType) where {T} = qualified_name_(T)
stable_hash_helper(_, hash_state, context, ::StructTypes.SingletonType) = hash_state
