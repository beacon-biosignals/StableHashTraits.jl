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

function stable_content_hash(T, hash_state, context, ::TypeType)
    hash_state = stable_content_hash(@hash64("TypeType"), hash_state, context,
                                    StructTypes.NumberType())
    return stable_content_hash(qualified_name_(T), hash_state, context,
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

function stable_type_hash(x, hash_state, context, st::StructTypes.DataType)
    nested_hash_state = start_nested_hash!(hash_state)
    T = typeof(x)
    type_hash = get!(context, typeof(x)) do
        fields = st isa StructTypes.UnorderedStruct ? fieldnames(T) :
            sorted_field_names(T)
        # we hash the fields and... their types???
    end
    hash_state = end_nested_hash!(hash_state, nested_hash_state)
    return hash_state
end

@generated function sorted_field_names(T)
    return TupleTools.sort(fieldnames(T); by=string)
end

function stable_content_hash(x, hash_state, context, st::StructTypes.DataType)
    nested_hash_state = start_nested_hash!(hash_state)
    nested_hash_state = stable_content_hash(@hash64("DataType"),
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
    fields = st isa StructTypes.UnorderedStruct ? sorted_field_names(typeof(x)) :
        fieldnames(typeof(x))
    for field in fields
        val = getfield(x, field)
        tval = transform(val, context)
        nested_hash_state = stable_content_hash(tval, nested_hash_state, context,
                                               HashType(tval, context))
    end

    hash_state = end_nested_hash!(hash_state, nested_hash_state)
    return hash_state
end

#####
##### DictType
#####

sort_items_by(x) = nothing
# TODO: implement order_matters(::OrderedDict) = string ∘ first etc...

function stable_content_hash(x, hash_state, context, ::StructTypes.DictType)
    pairs = StructTypes.keyvaluepairs(x)
    nested_hash_state = start_nested_hash!(hash_state)
    nested_hash_state = stable_content_hash(@hash64("DictType"),
                                           nested_hash_state, context,
                                           StructTypes.NumberType())

    pairs = isnothing(sorted_items_by(x)) ? StructTypes.keyvaluepairs(x) :
        sort(StructTypes.keyvaluepairs(x); by=sort_items_by)
    for (key, value) in pairs
        tkey = transform(key, context)
        tvalue = transform(value, context)
        nested_hash_state = stable_content_hash(tkey, nested_hash_state, context,
                                               HashType(tkey, context))
        nested_hash_state = stable_content_hash(tvalue, nested_hash_state, context,
                                               HashType(tvalue, context))
    end

    hash_state = end_nested_hash!(hash_state, nested_hash_state)
    return hash_state
end

#####
##### ArrayType
#####

sort_items_by(x) = nothing
sort_items_by(::AbstractSet) = string

function transform(x::AbstractArray, c::HashVersion{3})
    return @hash64("Base.AbstractArray"), size(x), vec(x)
end
transform(x::AbstractVector, c::HashVersion{3}) = x
HashType(x::AbstractRange, c::HashVersion{3}) = StructTypes.Struct()

function stable_content_hash(xs, hash_state, context, ::StructTypes.ArrayType)
    nested_hash_state = start_nested_hash!(hash_state)

    tag = xs isa Tuple ? @hash64("Base.Tuple") : @hash64("ArrayType")
    nested_hash_state = stable_content_hash(tag, nested_hash_state, context,
                                           StructTypes.NumberType())

    items = order_matters(x) ? sort(xs; by=string) : xs
    for x in xs
        tx = transform(x, context)
        nested_hash_state = stable_content_hash(tx, nested_hash_state, context,
                                               HashType(tx, context))
    end

    hash_state = end_nested_hash!(hash_state, nested_hash_state)
    return hash_state
end

#####
##### CustomStruct
#####

function stable_content_hash(x, hash_state, context, ::StructTypes.CustomStruct)
    lowered = StructTypes.lower(x)
    return stable_content_hash(lowered, hash_state, context, HashType(lowered, context))
end

#####
##### Basic data types
#####

transform(x::Symbol) = @hash64(":"), String(x)

function stable_content_hash(str, hash_state, context,
                            ::StructTypes.StringType)
    hash_state = update_hash!(hash_state, @hash64("StringType"), context)
    return update_hash!(hash_state, str isa AbstractString ? str : string(str), context)
end

function stable_content_hash(number::T, hash_state, context,
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

function stable_content_hash(bool, hash_state, context, ::StructTypes.BoolType)
    hash_state = update_hash!(hash_state, @hash64("BoolType"), context)
    return update_hash!(hash_state, Bool(bool), context)
end

function stable_content_hash(::T, hash_state, context, ::StructTypes.NullType) where {T}
    hash_state = update_hash!(hash_state, @hash64("NullType"), context)
    stable_content_hash(T, hash_state, context, TypeType())
    return hash_state
end
