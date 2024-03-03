#####
##### Helper Functions
#####

bytes_of_val(f) = reinterpret(UInt8, [f;])
bytes_of_val(f::Symbol) = codeunits(String(f))
bytes_of_val(f::String) = codeunits(f)
function hash64(x)
    bytes = sha256(bytes_of_val(x))
    # take the first 64 bytes of `bytes`
    return first(reinterpret(UInt64, bytes))
end
"""
    @hash64(x)

Compute a hash of the given string, symbol or numeric literal as an Int64 at compile time.
This is a useful optimization to generate unique tags based on some more verbose string and
can be used inside, e.g. [`transform`](@ref). Internally this calls `sha256` and returns the
first 64 bytes.
"""
macro hash64(constant)
    if constant isa Symbol || constant isa String || constant isa Number
        return hash64(constant)
    else
        return :(throw(ArgumentError(string("Unexpected expression: ", $(string(constant))))))
    end
end

# internally we always call StructType on the value when we want its struct type; if we see
# a type it means we are trying to hash a type as a value (e.g. stable_hash((Int, Int)))
HashType(x) = StructType(x)

#####
##### WithStructType
#####

struct WithStructType{T,S}
    val::T
    st::S
end
HashType(x::WithStructType) = x

function stable_hash_helper(x::WithStructType, hash_state, context, ::WithStructType)
    stable_hash_helper(x.val, hash_state, context, x.st)
end

#####
##### Type Hashes
#####

# There are two cases where we want to hash types:
#
#   1. when we are hashing the type of an object we're hashing (the type hash)
#   2. when a value we're hashing is itself a type (type as value hash)
#
# These are handled as separate contexts, with the former being the `TypeHashContext` and
# the latter being the default context. By default, in the `TypeHashContext` we only has the
# "structure" of types; names of structures don't matter only the recursive hash of the
# contained types and the `StructType(T)` of the type.
#
# Users can override how types are hashed in the context by overloading
# `transform(::Type{<:MyType}, ::TypeHashContext{<:MyContext})``

# type hash

struct TypeHashContext{T}
    parent::T
    TypeHashContext(x::CachingContext) = new{typeof(x.parent)}(x.parent)
    TypeHashContext(x) = new{typeof(x)}(x)
end
parent_context(x::TypeHashContext) = x.parent
transform(::Type{T}, ::TypeHashContext) where {T} = qualified_name_(StructType(T))

asarray(x) = [x]
asarray(x::AbstractArray) = x

# without this no-op method, stable_hash would try to hash the types of any values returned
# by `transform(T)`, which would lead to an infinite recursion
stable_type_hash(::Type{T}, hash_state, ::TypeHashContext) where {T} = hash_state
function stable_type_hash(::Type{T}, hash_state, context) where {T}
    bytes = get!(context, T) do
        type_hash_state = similar_hash_state(hash_state)
        type_context = TypeHashContext(context)
        tT = transform_type(T, StructType(T), type_context)
        type_hash_state = stable_hash_helper(tT, type_hash_state, type_context, HashType(tT))
        return reinterpret(UInt8, asarray(compute_hash!(type_hash_state)))
    end
    return update_hash!(hash_state, bytes, context)
end

transform_type(::Type{T}, _, context) where {T} = transform(T, context)
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

# types as values

struct TypeAsValue end
HashType(::Type) = TypeAsValue()

function stable_type_hash(::Type{<:DataType}, hash_state, context)
    return update_hash!(hash_state, @hash64("Base.DataType"), context)
end
function stable_hash_helper(::Type{T}, hash_state, context, ::TypeAsValue) where {T}
    tT = transform_type(T, StructType(T), context)
    return stable_hash_helper(tT, type_hash_state, context, HashType(tT))
end

#####
##### Function Hashes
#####

function transform_type(::Type{T}, st, context) where {T<:Function}
    if hasproperty(T, :instance) && isdefined(T, :instance)
        tT = transform(T.instance, context)
        if isconcretetype(T)
            fields = T <: StructTypes.OrderedStruct ? sorted_field_names(T) : fieldnames(T)
            return tT, fields, map(f -> fieldtype(T, f), fields)
        end
        return tT
    else
        return transform(T, context)
    end
end

function stable_hash_helper(fn::Function, hash_state, context, ::StructTypes.NoStructType)
    if isconcretetype(typeof(fn))
        # remember: functions can have fields
        return stable_hash_helper(fn, hash_state, context, StructTypes.Struct())
    else
        return hash_state
    end
end

#####
##### DataType
#####

sorted_field_names(T::Type) = TupleTools.sort(fieldnames(T); by=string)
@generated function sorted_field_names(T)
    return TupleTools.sort(fieldnames(T); by=string)
end

function transform_type(::Type{T}, ::S, context) where {T,S<:StructTypes.DataType}
    tT = transform(T, context)
    if isconcretetype(T)
        fields = T <: StructTypes.OrderedStruct ? sorted_field_names(T) : fieldnames(T)
        return tT, fields, map(fields) do field
            F = fieldtype(T, field)
            return transform_type(F, StructType(F), context)
        end
    else
        return tT
    end
end

function stable_hash_helper(x, hash_state, context, st::StructTypes.DataType)
    nested_hash_state = start_nested_hash!(hash_state)

    # hash the field values
    fields = st isa StructTypes.UnorderedStruct ? sorted_field_names(x) :
             fieldnames(typeof(x))
    for field in fields
        val = getfield(x, field)
        # field types that are concrete have already been accounted for in the type hash of
        # `x` so we can skip them
        if !isconcretetype(fieldtype(typeof(x), field))
            stable_type_hash(typeof(val), hash_state, context)
        end

        tval = transform(val, context)
        nested_hash_state = stable_hash_helper(tval, nested_hash_state, context,
                                               HashType(tval))
    end

    hash_state = end_nested_hash!(hash_state, nested_hash_state)
    return hash_state
end

#####
##### ArrayType
#####

sort_items_by(x) = nothing
sort_items_by(::AbstractSet) = string

# without `SizedArray` transform would fall into an infinite recurse
struct SizedArray{T}
    val::T
end
transform(x::AbstractArray, ::HashVersion{3}) = size(x), SizedArray(x)
transform(x::SizedArray, ::HashVersion{3}) = x.val
transform(x::AbstractRange, ::HashVersion{3}) = WithStructType(x, StructTypes.Struct())

function transform_type(::Type{T}, ::StructTypes.ArrayType, context) where {T}
    tT = transform(T, context)
    E = eltype(T)
    return tT, transform_type(E, StructType(E), context)
end

function stable_hash_helper(xs, hash_state, context, ::StructTypes.ArrayType)
    nested_hash_state = start_nested_hash!(hash_state)

    items = !isnothing(sort_items_by(xs)) ? sort(xs; by=sort_items_by(x)) : xs
    if isconcretetype(eltype(items))
        x1 = first(items)
        stable_type_hash(typeof(x1), nested_hash_state, context)
        for x in items
            tx = transform(x, context)
            nested_hash_state = stable_hash_helper(tx, nested_hash_state, context,
                                                   HashType(tx))
        end
    else
        for x in items
            stable_type_hash(typeof(x), nested_hash_state, context)
            tx = transform(x, context)
            nested_hash_state = stable_hash_helper(tx, nested_hash_state, context,
                                                   HashType(tx))
        end
    end

    hash_state = end_nested_hash!(hash_state, nested_hash_state)
    return hash_state
end

#####
##### Tuples
#####

function transform_type(::Type{T}, ::StructTypes.ArrayType, context) where {T<:Tuple}
    tT = transform(T, context)
    if isconcretetype(T)
        return tT, map(fieldtypes(T)) do field
            F = fieldtype(T, field)
            return transform_type(F, StructType(F), context)
        end
    else
        return tT
    end
end

function transform_type(::Type{T}, ::StructTypes.ArrayType, context) where {T<:NTuple}
    E = eltype(T)
    return transform(T, context), transform_type(E, StructType(E), context)
end

transform_type(::Type{Tuple{}}, ::StructTypes.ArrayType, context) = transform(Tuple{}, context)

function stable_hash_helper(x::Tuple, hash_state, context, ::StructTypes.ArrayType)
    nested_hash_state = start_nested_hash!(hash_state)

    # hash the tuple field values themselves
    for field in fieldnames(typeof(x))
        val = getfield(x, field)
        # field types that are concrete have already been accounted for in the type hash of
        # `x` so we can skip them
        if !isconcretetype(fieldtype(typeof(x), field))
            stable_type_hash(typeof(val), hash_state, context)
        end

        tval = transform(val, context)
        nested_hash_state = stable_hash_helper(tval, nested_hash_state, context,
                                               HashType(tval))
    end

    hash_state = end_nested_hash!(hash_state, nested_hash_state)
    return hash_state
end

#####
##### DictType
#####

# `string` aims to ensure that the object can be ordered (e.g. Symbols can't
# be sorted without this)
# NOTE: we could sort by the written bytes to hash to prevent `string` from messing us up
# but that would be a bit complicated to implement
sort_items_by(x::AbstractDict) = string

keytype(::Type{<:Pair{K,T}}) where {K,T} = K
valtype(::Type{<:Pair{K,T}}) where {K,T} = T
keytype(::Type{<:T}) where {T} = T
valtype(::Type{<:T}) where {T} = T

function transform_type(::Type{T}, ::S, context) where {T,S<:StructTypes.DictType}
    tT = transform(T, context)
    K = keytype(eltype(T))
    V = valtype(eltype(T))
    return tT, transform_type(K, StructType(K), context), transform_type(V, StructType(V), context)
end

function stable_hash_helper(x, hash_state, context, ::StructTypes.DictType)
    pairs = StructTypes.keyvaluepairs(x)
    nested_hash_state = start_nested_hash!(hash_state)

    pairs = isnothing(sort_items_by(x)) ? StructTypes.keyvaluepairs(x) :
            sort(StructTypes.keyvaluepairs(x); by=sort_items_by(x))
    if isconcretetype(eltype(pairs))
        (key1, val1) = first(pairs)
        stable_type_hash(typeof(key1), nested_hash_state, context)
        stable_type_hash(typeof(val1), nested_hash_state, context)
        for (key, value) in pairs
            tkey = transform(key, context)
            tvalue = transform(value, context)
            nested_hash_state = stable_hash_helper(tkey, nested_hash_state, context,
                                                   HashType(tkey))
            nested_hash_state = stable_hash_helper(tvalue, nested_hash_state, context,
                                                   HashType(tvalue))
        end
    else
        for (key, value) in pairs
            tkey = transform(key, context)
            tvalue = transform(value, context)
            stable_type_hash(typeof(key1), nested_hash_state, context)
            stable_type_hash(typeof(val1), nested_hash_state, context)
            nested_hash_state = stable_hash_helper(tkey, nested_hash_state, context,
                                                   HashType(tkey))
            nested_hash_state = stable_hash_helper(tvalue, nested_hash_state, context,
                                                   HashType(tvalue))
        end
    end

    hash_state = end_nested_hash!(hash_state, nested_hash_state)
    return hash_state
end

#####
##### CustomStruct
#####

# unforuntately there's not much we can do to avoid hashing the type for every instance when
# we have a CustomStruct; `lowered` could be anything
function stable_hash_helper(x, hash_state, context, ::StructTypes.CustomStruct)
    lowered = StructTypes.lower(x)
    stable_type_hash(typeof(lowered), hash_state, context)
    return stable_hash_helper(lowered, hash_state, context, HashType(lowered))
end

#####
##### Basic data types
#####

transform(x::Symbol) = @hash64(":"), String(x)

function stable_hash_helper(str, hash_state, context,
                            ::StructTypes.StringType)
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

function stable_hash_helper(_, hash_state, context, ::StructTypes.NullType)
    return hash_state
end
