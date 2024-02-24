#####
##### Helper Functions
#####

bytes_of_val(f) = reinterpret(UInt8, [f;])
bytes_of_val(f::Symbol) = codeunits(String(f))
bytes_of_val(f::String) = codeunits(f)
n_to_type = Dict(1 => UInt8, 2 => UInt16, 4 => UInt32, 8 => UInt64)
function hash(x, n=8)
    bytes = sha256(bytes_of_val(x))
    if !haskey(n_to_type, n)
        throw(ArgumentError("$n bytes is not a supported value"))
    end
    # take the first n bytes of `bytes`
    return first(reinterpret(n_to_type[n], bytes))
end
"""
    @hash(x, n=8)

Compute a hash of the given literal string, symbol, or numeric value as a UInt of the
given number of bytes at compile time. This is a useful optimization to generate
unique tags based on some more verbose string and can be used inside, e.g.
[`transform`](@ref). Internally this calls `sha256` and returns the first n bytes.
"""
macro hash(constant, n=8)
    if constant isa Symbol || constant isa String || constant isa Number
        return hash(constant, n)
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
    return @hash("Base.Function"), qualified_name(fn),
           NamedTuple{fields}(getfield.(fn, fields))
end

function stable_hash_helper(T, hash_state, context, ::TypeType)
    hash_state = stable_hash_helper(@hash("TypeType"), hash_state, context,
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
    nested_hash_state = stable_hash_helper(@hash("DataType"),
                                           nested_hash_state, context,
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

function stable_hash_helper(x, hash_state, context, ::StructTypes.DictType)
    pairs = StructTypes.keyvaluepairs(x)
    nested_hash_state = start_nested_hash!(hash_state)
    nested_hash_state = stable_hash_helper(@hash("DictType"),
                                           nested_hash_state, context,
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
    return @hash("Base.AbstractArray"), size(x), vec(x)
end
transform(x::AbstractVector, c::HashVersion{3}) = x
HashType(x::AbstractRange, c::HashVersion{3}) = StructTypes.Struct()

function stable_hash_helper(xs, hash_state, context, ::StructTypes.ArrayType)
    nested_hash_state = start_nested_hash!(hash_state)

    tag = xs isa Tuple ? @hash("Base.Tuple") : @hash("ArrayType")
    nested_hash_state = stable_hash_helper(tag, nested_hash_state, context,
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

transform(x::Symbol) = @hash(":"), String(x)

function stable_hash_helper(str, hash_state, context,
                            ::StructTypes.StringType)
    hash_state = update_hash!(hash_state, @hash("StringType"), context)
    return update_hash!(hash_state, str isa AbstractString ? str : string(str), context)
end

function stable_hash_helper(number::T, hash_state, context,
                            ::StructTypes.NumberType) where {T}
    U = StructTypes.numbertype(T)
    # for small sized numbers we want to hash no more than double `sizeof(U)` bytes
    tag = if sizeof(U) == 1
        @hash("NumberType", 1)
    elseif sizeof(U) == 2
        @hash("NumberType", 2)
    elseif sizeof(U) == 4
        @hash("NumberType", 4)
    else
        @hash("NumberType", 8)
    end
    hash_state = update_hash!(hash_state, tag, context)
    return update_hash!(hash_state, U(number), context)
end

function stable_hash_helper(bool, hash_state, context, ::StructTypes.BoolType)
    hash_state = update_hash!(hash_state, @hash("BoolType"), context)
    return update_hash!(hash_state, Bool(bool), context)
end

function stable_hash_helper(::T, hash_state, context, ::StructTypes.NullType) where {T}
    hash_state = update_hash!(hash_state, @hash("NullType"), context)
    stable_hash_helper(T, hash_state, context, TypeType())
    return hash_state
end
