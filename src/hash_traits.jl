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

#####
##### Type Hashes
#####

struct TypeType end
HashType(::Type, c::HashVersion{3}) = TypeType()
HashType(::Module, c::HashVersion{3}) = TypeType()
HashType(::Function, c::HashVersion{3}) = TypeType()
function transform(fn::Function, c::HashVersion{3})
    # functions can have fields if they are `struct MyFunctor <: Function` or if they are
    # closures
    fields = fieldnames(typeof(fn))
    return @hash64("Base.Function"), qualified_name(fn),
           NamedTuple{fields}(getfield.(fn, fields))
end

function stable_hash_helper(T, hash_state, context, ::TypeType)
    hash_state = stable_hash_helper(@hash64("TypeType"), hash_state, context,
                                    StructTypes.NumberType())
    return stable_hash_helper(qualified_name_(T), hash_state, context,
                              StructTypes.StringType())
end

function validate_name(str)
    if occursin("#", str)
        throw(ArgumentError("Anonymous types (those containing `#`) cannot be hashed to a reliable value: found type $str"))
    end
    return str
end

qname_(T, name) = validate_name(cleanup_name(string(parentmodule(T), '.', name(T))))
qualified_name_(fn::Function) = qname_(fn, nameof)
qualified_name_(x::T) where {T} = qname_(T <: DataType ? x : T, nameof)
function qualified_name_(x::T) where {T<:Type{<:Function}}
    if hasproperty(x, :instance)
        "typeof(" * qualified_name_(getproperty(x, :instance)) * ")"
    else
        qname_(T, nameof)
    end
end

#####
##### DataType
#####

function stable_hash_helper(x, hash_state, context, st::StructTypes.DataType)
    nested_hash_state = start_nested_hash!(hash_state)

    # hash components that depends only on the type of `x` and which denote the structure of
    # x
    # - tag indicating it's a `DataType` struct
    # - fieldnames
    # - fieldtypes

    # NOTE: fields are ordered or unordered according to the `StructType`
    # NOTE: in my benchmarking, this remains the most time consuming piece;
    # it increases time by a factor of about ~10
    # I wonder if we could conditionally use generated functions so it works
    # even when the generated part doesn't play out
    # ALSO: we don't really need this to depend on the context at all in the
    # generated function case
    # (would this improve in speed with a function barrier?)
    cache = context_cache(context, Tuple{hash_type(hash_state),NTuple{<:Any,Symbol}})
    type_structure_hash, ordered_fields = get!(cache, typeof(x)) do
        T = typeof(x)
        fields = fieldnames(T)
        ordered_fields = (st isa StructTypes.OrderedStruct) ? fields : sort_(fields)

        type_structure_hash = stable_hash_helper(@hash64("DataType"),
                                                 similar_hash_state(hash_state), context,
                                                 StructTypes.NumberType())
        type_structure_hash = stable_hash_helper(ordered_fields, type_structure_hash,
                                                 context, HashType(ordered_fields, context))
        for k in ordered_fields
            stable_hash_helper(fieldtype(T, k), type_structure_hash, context, TypeType())
        end

        return compute_hash!(type_structure_hash), ordered_fields
    end

    nested_hash_state = stable_hash_helper(type_structure_hash, nested_hash_state, context,
                                           StructTypes.NumberType())

    # hash the field values themselves
    for field in fieldnames(typeof(x)) # ordered_fields
        val = getfield(x, field)
        tval = transform(val, context)
        nested_hash_state = stable_hash_helper(tval, nested_hash_state, context,
                                               HashType(tval, context))
    end

    hash_state = end_nested_hash!(hash_state, nested_hash_state)
    return hash_state
end

#####
##### DictType
#####

dict_eltype(x) = eltype(x)
keytype(::Type{Pair{K,V}}) where {K,V} = K
keytype(::Type{T}) where {T} = T
valtype(::Type{Pair{K,V}}) where {K,V} = V
valtype(::Type{T}) where {T} = T

function stable_hash_helper(x, hash_state, context, ::StructTypes.DictType)
    pairs = StructTypes.keyvaluepairs(x)
    nested_hash_state = start_nested_hash!(hash_state)
    type_structure_hash = get!(context_cache(context, hash_type(hash_state)), typeof(x)) do
        type_structure_hash = similar_hash_state(hash_state)
        type_structure_hash = stable_hash_helper(@hash64("DictType"),
                                                 type_structure_hash, context,
                                                 StructTypes.NumberType())
        type_structure_hash = stable_hash_helper(eltype(pairs), type_structure_hash,
                                                 context, TypeType())

        return compute_hash!(type_structure_hash)
    end
    nested_hash_state = stable_hash_helper(type_structure_hash, nested_hash_state, context,
                                           StructTypes.NumberType())

    for (key, value) in StructTypes.keyvaluepairs(x)
        tkey = transform(key, context)
        tvalue = transform(value, context)
        nested_hash_state = stable_hash_helper(tkey, nested_hash_state, context,
                                               HashType(tkey, context))
        nested_hash_state = stable_hash_helper(tvalue, nested_hash_state, context,
                                               HashType(tvalue, context))
    end

    hash_state = end_nested_hash!(hash_state, nested_hash_state)
    return hash_state
end

#####
##### ArrayType
#####

function transform(x::AbstractArray, c::HashVersion{3})
    return @hash64("Base.AbstractArray"), size(x), vec(x)
end
transform(x::AbstractVector, c::HashVersion{3}) = x
HashType(x::AbstractRange, c::HashVersion{3}) = StructTypes.Struct()

function stable_hash_helper(xs, hash_state, context, ::StructTypes.ArrayType)
    nested_hash_state = start_nested_hash!(hash_state)

    type_structure_hash = get!(context_cache(context, hash_type(hash_state)), typeof(xs)) do
        T = typeof(xs)
        type_structure_hash = similar_hash_state(hash_state)
        type_structure_hash = stable_hash_helper(@hash64("ArrayType"),
                                                 type_structure_hash, context,
                                                 StructTypes.NumberType())
        type_structure_hash = stable_hash_helper(eltype(T), type_structure_hash, context,
                                                 TypeType())
        return compute_hash!(type_structure_hash)
    end
    nested_hash_state = stable_hash_helper(type_structure_hash, nested_hash_state, context,
                                           StructTypes.NumberType())

    for x in xs
        tx = transform(x, context)
        nested_hash_state = stable_hash_helper(tx, nested_hash_state, context,
                                               HashType(tx, context))
    end

    hash_state = end_nested_hash!(hash_state, nested_hash_state)
    return hash_state
end

#####
##### Tuples
#####

function stable_hash_helper(xs::Tuple, hash_state, context, ::StructTypes.ArrayType)
    nested_hash_state = start_nested_hash!(hash_state)
    type_structure_hash = get!(context_cache(context, hash_type(hash_state)), typeof(xs)) do
        T = typeof(xs)
        type_structure_hash = similar_hash_state(hash_state)
        type_structure_hash = stable_hash_helper(@hash64("Tuple.DataType"),
                                                 type_structure_hash, context,
                                                 StructTypes.NumberType())
        for f in fieldnames(T)
            type_structure_hash = stable_hash_helper(fieldtype(T, f), type_structure_hash,
                                                     context, TypeType())
        end
        return compute_hash!(type_structure_hash)
    end
    nested_hash_state = stable_hash_helper(type_structure_hash, nested_hash_state, context,
                                           StructTypes.NumberType())

    for x in xs
        tx = transform(x, context)
        nested_hash_state = stable_hash_helper(tx, nested_hash_state, context,
                                               HashType(tx, context))
    end

    hash_state = end_nested_hash!(hash_state, nested_hash_state)
    return hash_state
end

#####
##### CustomStruct
#####

function stable_hash_helper(x, hash_state, context, ::StructTypes.CustomStruct)
    lowered = StructTypes.lower(x)
    return stable_hash_helper(lowered, hash_state, context, HashType(lowered, context))
end

#####
##### Basic data types
#####

transform(x::Symbol) = @hash64(":"), String(x)

function stable_hash_helper(str::AbstractString, hash_state, context,
                            ::StructTypes.StringType)
    hash_state = update_hash!(hash_state, @hash64("Base.AbstractString"), context)
    return update_hash!(hash_state, str, context)
end

function stable_hash_helper(str, hash_state, context, ::StructTypes.StringType)
    hash_state = update_hash!(hash_state, @hash64("Base.AbstractString"), context)
    return update_hash!(hash_state, string(str), context)
end

function stable_hash_helper(number::T, hash_state, context,
                            ::StructTypes.NumberType) where {T}
    U = StructTypes.numbertype(T)
    return update_hash!(hash_state, U(number), context)
end

# there are some cases where we have a raw bit array (e.g. when recursively hashing
# `sha256`); in this situation we don't want to add any sort of header about the array of
# numbers, just write the bytes to the hash buffer
function stable_hash_helper(numbers::AbstractVector{T}, hash_state, context,
                            ::StructTypes.NumberType) where {T}
    return update_hash!(hash_state, reinterpret(UInt8, numbers), context)
end

function stable_hash_helper(bool, hash_state, context, ::StructTypes.BoolType)
    return update_hash!(hash_state, Bool(bool), context)
end

function stable_hash_helper(::T, hash_state, context, ::StructTypes.NullType) where {T}
    stable_hash_helper(T, hash_state, context, TypeType())
    return hash_state
end
