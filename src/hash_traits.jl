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
    return stable_hash_helper(x.val, hash_state, context, x.st)
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

transformer(::Type{<:DataType}, context) = Base.Fix2(transform_type, context)
function transform_type(::Type{T}, context) where {T}
    return qualified_name_(StructType(T)), type_structure(T, context)
end
type_structure(::Type{T}, context) where {T} = type_structure(T, StructType(T), context)
function type_structure(::Type{T}, trait, context) where {T}
    return type_structure(T, trait, parent_context(context))
end
type_structure(::Type{T}, trait, ::Nothing) where {T} = nothing
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
end
parent_context(x::TypeAsValueContext) = x.parent

function hash_type!(hash_state, context::CachingContext, ::Type{<:Type})
    return update_hash!(hash_state, @hash64("Base.Type"), context)
end

function transform_type(::Type{T}, context::TypeAsValueContext) where {T}
    return qualified_name_(T), type_structure(T, StructType(T), context)
end

hash_type!(hash_state, ::TypeAsValueContext, T) = hash_state
function stable_hash_helper(::Type{T}, hash_state, context, ::TypeAsValue) where {T}
    transform = transformer(typeof(T), context)
    type_context = TypeAsValueContext(context)
    tT = transform(T)
    return stable_hash_helper(tT, hash_type_state, type_context, HashType(tT))
end

#####
##### Function Hashes
#####

# remember: functions can have fields; in general StructTypes doesn't assume these are
# serialized but here we want that to happen by default
function transformer(::Type{<:Function}, context)
    return PreservesTypes(fn -> WithStructType(fn, StructTypes.UnorderedStruct()))
end

function transform_type(::Type{T}, context) where {T<:Function}
    if hasproperty(T, :instance) && isdefined(T, :instance)
        return "typeof($(qualified_name_(T.instance)))"
    else
        return qualified_name_(T)
    end
end

#####
##### DataType
#####

# NOTE: there are really just two patterns: eltype-like and fieldtype-like
# (dict is just an eltype-like of pairs)
# we can greatly reduce the amount of code below by taking advantage of that

sorted_field_names(T::Type) = TupleTools.sort(fieldnames(T); by=string)
@generated function sorted_field_names(T)
    return TupleTools.sort(fieldnames(T); by=string)
end

function type_structure(::Type{T}, ::StructTypes.DataType, context) where {T}
    if isconcretetype(T)
        fields = T <: StructTypes.OrderedStruct ? fieldnames(T) : sorted_field_names(T)
        return fields, map(field -> fieldtype(T, field), fields)
    else
        return nothing
    end
end

function stable_hash_helper(x, hash_state, context, parent_preserves_types,
                            st::StructTypes.DataType)
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
        transform, preserves_types, traitfn = unwrap(hash_method(typeof(val), context))
        if isconcretetype(fieldtype(typeof(x), field)) && preserves_types
            tval = transform(val)
            hash_state = stable_hash_helper(tval, hash_state, context,
                                            traitfn(tval))
        else
            # TODO: do we need to hash both pre and post transformed types?
            tval = transform(val)
            hash_state = hash_type!(typeof(tval), hash_state, context)
            hash_state = stable_hash_helper(tval, hash_state, context,
                                            traitfn(tval))
        end
    end
end

#####
##### ArrayType
#####

is_ordered(x) = true
is_ordered(::AbstractSet) = false
order_by(::Symbol) = String
order_by(x) = identity

function type_structure(::Type{T}, hash_state, context, ::StructTypes.ArrayType) where {T}
    return eltype(T)
end

# include ndims in type hash where possible
function transformer(::Type{<:AbstractArray}, ::HashVersion{3})
    return PreservesStructure(x -> size(x), SizedArray(x))
end
function transformer(::Type{<:SizedArray}, ::HashVersion{3})
    return PreservesStructure(x -> x.val)
end
function transformer(::Type{<:AbstractRange}, ::HashVersion{3})
    return PreservesStructure(x -> WithStructType(x, StructTypes.Struct()))
end

function stable_hash_helper(xs, hash_state, context, ::StructTypes.ArrayType)
    nested_hash_state = start_nested_hash!(hash_state)

    items = !is_ordered(xs) ? sort!(collect(xs); by=order_by) : xs
    nested_hash_state = hash_elements(items, nested_hash_state, context)

    hash_state = end_nested_hash!(hash_state, nested_hash_state)
    return hash_state
end

function hash_elements(items, hash_state, context)
    transform, preserves_types, traitfn = unwrap(hash_method(eltype(items), context))
    # can we optimize away the element type hash?
    if isconcretetype(eltype(items)) && preserves_types(transform)
        hash_state = type_hash!(eltype(items), hash_state, context)
        for x in items
            tx = transform(x)
            hash_state = stable_hash_helper(tx, hash_state, context, traitfn(tx))
        end
    else
        for x in items
            transform, _, traitfn = unwrap(hash_method(eltype(x), context))
            tx = transform(x)
            hash_state, = type_hash!(typeof(tx), hash_state, context)
            hash_state = stable_hash_helper(tx, hash_state, context, traitfn(tx))
        end
    end
    return hash_state
end

#####
##### Tuples
#####

function type_structure(::Type{T}, hash_state, context,
                        ::StructTypes.ArrayType) where {T<:Tuple}
    if isconcretetype(T)
        fields = T <: StructTypes.OrderedStruct ? fieldnames(T) : sorted_field_names(T)
        return fields, map(field -> fieldtype(T, field), fields)
    else
        return nothing
    end
end

function type_structure(::Type{T}, hash_state, context,
                        ::StructTypes.ArrayType) where {T<:NTuple}
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

# `string` aims to ensure that the object can be ordered (e.g. Symbols can't
# be sorted without this)
# NOTE: we could sort by the written bytes to hash to prevent `string` from messing us up
# but that would be a bit complicated to implement
is_ordered(x::AbstractDict) = false

keytype(::Type{<:Pair{K,T}}) where {K,T} = K
valtype(::Type{<:Pair{K,T}}) where {K,T} = T

function type_structure(::Type{T}, hash_state, context, ::StructTypes.DictType) where {T}
    return keytype(eltype(T)), valtype(eltype(T))
end

function stable_hash_helper(x, hash_state, context, ::StructTypes.DictType)
    pairs = StructTypes.keyvaluepairs(x)
    nested_hash_state = start_nested_hash!(hash_state)

    pairs = if is_ordered(x)
        StructTypes.keyvaluepairs(x)
    else
        sort!(collect(StructTypes.keyvaluepairs(x)); by=order_by(x))
    end
    hash_elements(pairs, nested_hash_state, context)

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
    hash_type!(hash_state, context, typeof(lowered))
    return stable_hash_helper(lowered, hash_state, context, HashType(lowered))
end

#####
##### Basic data types
#####

# the type 'structure' of a symbol is to differentiate it from a string
type_structure(::Type{<:Symbol}, ::StructTypes.StringType, context) = @hash64(":")
hash_method(::Type{<:Symbol}) = HashFn(String; preserves_types=true)

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

# null types are encoded purely by their type
function stable_hash_helper(_, hash_state, context, ::StructTypes.NullType)
    return hash_state
end
