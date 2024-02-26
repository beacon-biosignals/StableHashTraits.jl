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
        throw(ArgumentError("Anonymous types (those containing `#`) cannot be hashed " *
                            "to a reliable value: found type $str"))
    end
    return str
end

qname_(T, name) = validate_name(cleanup_name(string(parentmodule(T), '.', name(T))))
qualified_name_(fn::Function) = qname_(fn, nameof)
qualified_name_(x::T) where {T} = qname_(T <: DataType ? x : T, nameof)
function qualified_name_(x::T) where {T<:Type{<:Function}}
    if hasproperty(x, :instance) && isdefined(x, :instance)
        "typeof(" * qualified_name_(getproperty(x, :instance)) * ")"
    else
        qname_(T, nameof)
    end
end

#####
##### DataType
#####

function stable_hash_helper(x, hash_state, context, ::StructTypes.DataType)
    nested_hash_state = start_nested_hash!(hash_state)
    nested_hash_state = stable_hash_helper(@hash64("DataType"),
                                           nested_hash_state, context,
                                           StructTypes.NumberType())

    # TODO: sort the fields if we have an UnorderedStruct
    # (caching the result??)
    # TODO: make a hash of the fieldnames
    # NOTE: do we do the simplest thing and do it in a generated function OR
    # do we avoid generated functions and some how hoist the computation
    # to the container?
    # At the moment it feels to me that the latter would be harder to maintain
    # since the PR that implemented this for the earlier hash versions was
    # pretty complicated
    # maybe one way to keep it simple would be to separate out
    # the hash of the type and the has of the content into two separate code
    # paths
    # NOTE: a final alternative would be to accept the less than stellar performance
    # of caching

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
    nested_hash_state = stable_hash_helper(@hash64("DictType"),
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
    return @hash64("Base.AbstractArray"), size(x), vec(x)
end
transform(x::AbstractVector, c::HashVersion{3}) = x
HashType(x::AbstractRange, c::HashVersion{3}) = StructTypes.Struct()

function stable_hash_helper(xs, hash_state, context, ::StructTypes.ArrayType)
    nested_hash_state = start_nested_hash!(hash_state)

    tag = xs isa Tuple ? @hash64("Base.Tuple") : @hash64("ArrayType")
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

transform(x::Symbol) = @hash64(":"), String(x)

function stable_hash_helper(str, hash_state, context,
                            ::StructTypes.StringType)
    hash_state = update_hash!(hash_state, @hash64("StringType"), context)
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
    hash_state = update_hash!(hash_state, @hash64("BoolType"), context)
    return update_hash!(hash_state, Bool(bool), context)
end

function stable_hash_helper(::T, hash_state, context, ::StructTypes.NullType) where {T}
    hash_state = update_hash!(hash_state, @hash64("NullType"), context)
    stable_hash_helper(T, hash_state, context, TypeType())
    return hash_state
end
