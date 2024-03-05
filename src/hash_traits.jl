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
#   1. when we are hashing the type of an object we're hashing (`TypeHashContext`)
#   2. when a value we're hashing is itself a type (`TypeAsValueContext`)
#
# These are handled as separate contexts as the kind of value we want to generate from the
# type may differ in these context. By default only the structure of types matters when hash
# an objects type, e.g. that it is a data type with fields of the given names and types.
# When a type is hashed as a value, its actual also name matters.

# type hash

transform(::Type{T}, context) where {T} = transform(::Type{T}, StructType(T), context)
transform(::Type{T}, trait, context) where {T} = qualified_name_(T)

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

struct TypeAsValueContext{T}
    parent::T
    TypeAsValueContext(x::CachingContext) = new{typeof(x.parent)}(x.parent)
    TypeAsValueContext(x) = new{typeof(x)}(x)
end
parent_context(x::TypeAsValueContext) = x.parent
transform(::Type{T}, ::TypeAsValueContext) where {T} = qualified_name_(T)
stable_type_hash(::Type{T}, hash_state, ::TypeAsValueContext) where {T} = hash_state

function stable_type_hash(::Type{<:DataType}, hash_state, context)
    return update_hash!(hash_state, @hash64("Base.DataType"), context)
end
function stable_hash_helper(::Type{T}, hash_state, context, ::TypeAsValue) where {T}
    type_context = TypeAsValueContext(context)
    tT = transform_type(T, StructType(T), type_context)
    return stable_hash_helper(tT, hash_state, type_context, HashType(tT))
end

#####
##### Function Hashes
#####

# remember: functions can have fields
transform(fn::Function) = WithStructType(fn, StructTypes.UnorderedStruct())
function transform(::Type{T}, ::TypeHashContext) where {T<:Function}
    if hasproperty(T, :instance) && isdefined(T, :instance)
        return qualified_name_(T.instance)
    else
        return qualified_name_(T)
    end
end

# hashing a function type as a value...
function transform(::Type{T}, context) where {T<:Function}
    if hasproperty(T, :instance) && isdefined(T, :instance)
        return "typeof($(qualified_name(T.instance)))"
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

function encode_fieldtypes(T, context)
    if isconcretetype(T)
        fields = T <: StructTypes.OrderedStruct ? fieldnames(T) : sorted_field_names(T)
        fieldtypes = map(fields) do field
            F = fieldtype(T, field)
            tt = transform(F, context)::TransformedType
            return tt.encoding
        end
        return TransformedType((fields, fieldtypes), hashes_fieldtypes)
    else
        return TransformedTypeIdentity()
    end
end

function transform(::Type{T}, ::S, context) where {T,S<:StructTypes.DataType}
    qualified_name_(T) * transform_fieldtypes(T, context)
end

function stable_hash_helper(x, hash_state, context, flags, st::StructTypes.DataType)
    nested_hash_state = start_nested_hash!(hash_state)

    # hash the field values
    fields = st isa StructTypes.UnorderedStruct ? sorted_field_names(x) :
             fieldnames(typeof(x))
    for field in fields
        val = getfield(x, field)
        # field types that are concrete have already been accounted for in the type hash of
        # `x` so we can skip them
        if !isconcretetype(fieldtype(typeof(x), field)) || Int(hashes_fieldtypes) ∉ flags
            hash_state, field_flags = hash_type!(typeof(val), hash_state, context)
        else
            # ... oh dear, this is where I need to know what the flags would be
            # if they were *were* run (and do so without running them)
            field_flags = forfield(flags, field) # can I even implement this???
            # what we need to know is if `transform` alters `field_flags`
            # or not
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

is_ordered(x) = true
is_ordered(::AbstractSet) = false
order_by(::Symbol) = String
order_by(x) = identity

# without `SizedArray` transform would fall into an infinite recurse
struct SizedArray{T}
    val::T
end
function transform(::Type{T}, ::TypeHashContext) where {T<:AbstractArray}
    if isconcretetype(T)
        return qualified_name_(StructType(T)), ndims(T)
    else
        return qualified_name_(StructType(T))
    end
end
function transform(::Type{T}, ::TypeAsValueContext) where {T<:AbstractArray}
    if isconcretetype(T)
        return qualified_name_(StructType(T)), ndims(T)
    else
        return qualified_name_(StructType(T))
    end
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

    items = !is_ordered(xs) ? sort!(collect(xs), by=order_by) : xs
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
is_ordered(x::AbstractDict) = false

keytype(::Type{<:Pair{K,T}}) where {K,T} = K
valtype(::Type{<:Pair{K,T}}) where {K,T} = T
# if the pre-transformed type isn't a dictionary, we need to encode the post-transformed
# types
keytype(::Type{T}) where {T} = Any
valtype(::Type{T}) where {T} = Any

function transform_type(::Type{T}, ::S, context) where {T,S<:StructTypes.DictType}
    @show tT = transform(T, context)
    @show K = keytype(eltype(T))
    @show V = valtype(eltype(T))
    return tT, transform_type(K, StructType(K), context), transform_type(V, StructType(V), context)
end

function stable_hash_helper(x, hash_state, context, ::StructTypes.DictType)
    pairs = StructTypes.keyvaluepairs(x)
    nested_hash_state = start_nested_hash!(hash_state)

    pairs = if is_ordered(x)
        StructTypes.keyvaluepairs(x)
    else
        sort!(collect(StructTypes.keyvaluepairs(x)); by=order_by(x))
    end
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
            stable_type_hash(typeof(key), nested_hash_state, context)
            stable_type_hash(typeof(val), nested_hash_state, context)
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
