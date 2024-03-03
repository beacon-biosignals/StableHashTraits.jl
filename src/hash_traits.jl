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

# the type hash context prevents an infinite recursion of types;
# without this, `stable_hash_helper would try to hash the type of the type`
struct TypeHashContext{T}
    parent::T
end
parent_context(x::TypeHashContext) = x.parent

asarray(x) = [x]
asarray(x::AbstractArray) = x

stable_type_hash(::Type{T}, hash_state, ::TypeHashContext) where {T} = hash_state
function stable_type_hash(::Type{T}, hash_state, context) where {T}
    bytes = get!(context, T) do
        type_hash_state = similar_hash_state(hash_state)
        tT = transform(T)
        type_hash_state = stable_hash_helper(tT, type_hash_state, TypeHashContext(context), StructType(tT))
        return reinterpret(UInt8, asarray(type_hash_state))
    end
    return update_hash!(hash_state, bytes, context)
end

transform_type(::Type{T}, ::S) where {T, S} = qualified_name_(S)

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

# hashing a type as a value (e.g. (Int,Int))
function stable_type_hash(::Type{<:DataType}, hash_state, context)
    return update_hash!(hash_state, @hash64("Base.DataType"), context)
end
function stable_hash_helper(::Type{T}, hash_state, context, ::StructTypes.NoStructType) where {T}
    return stable_type_hash(T, hash_state, context)
end

#####
##### Function Hashes
#####

function transform_type(::Type{T}, st) where {T<:Function}
    if hasproperty(T, :instance) && isdefined(T, :instances)
        name = qualified_name_(T.instance)
        if !isabstracttype(T)
            fields = T <: StructTypes.OrderedStruct ? sorted_field_names(T) : fieldnames(T)
            return name, fields, map(f -> fieldtype(T, f), fields)
        end
        return name
    else
        return qualified_name_(T)
    end
end

# TODO...

#####
##### DataType
#####

sorted_field_names(T::Type) = TupleTools.sort(fieldnames(T); by=string)
@generated function sorted_field_names(T)
    return TupleTools.sort(fieldnames(T); by=string)
end

function transform_type(::Type{T}, ::S) where {T,S<:StructTypes.DataType}
    name = qualified_name_(S)
    if !isabstracttype(T)
        fields = T <: StructTypes.OrderedStruct ? sorted_field_names(T) : fieldnames(T)
        return name, fields, map(f -> fieldtype(T, f), fields)
    else
        return name
    end
end

function is_concrete_type(x, k)
    return isdispatchtuple(Tuple{fieldtype(typeof(x), k)})
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
        if !is_concrete_type(x, field)
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

function transform(x::AbstractArray, c::HashVersion{3})
    return @hash64("Base.AbstractArray"), size(x), vec(x)
end
transform(x::AbstractVector, c::HashVersion{3}) = x
HashType(x::AbstractRange) = StructTypes.Struct()

function has_concrete_eltype(xs)
    return isdispatchtuple(Tuple{typeof(xs)})
end

function transform_type(::Type{T}, ::S) where {T,S<:StructTypes.ArrayType}
    name = qualified_name_(S)
    return name, eltype(T)
end

function stable_hash_helper(xs, hash_state, context, ::StructTypes.ArrayType)
    nested_hash_state = start_nested_hash!(hash_state)

    items = !isnothing(sort_items_by(xs)) ? sort(xs; by=sort_items_by(x)) : xs
    if has_concrete_eltype(items)
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

function transform_type(::Type{<::Tuple}, st::StructTypes.ArrayType)
    name = qualified_name_(st)
    if !isabstracttype(T)
        return name, fieldtypes(T)
    else
        return name
    end
end

function transform_type(::Type{T}, st::StructType.ArrayType) where {T<:NTuple}
    return qualified_name_(st), eltyep(T)
end

function stable_hash_helper(x::Tuple, hash_state, context, st::StructTypes.ArrayType)
    nested_hash_state = start_nested_hash!(hash_state)

    # hash the tuple field values themselves
    for field in fieldnames(typeof(x))
        val = getfield(x, field)
        # field types that are concrete have already been accounted for in the type hash of
        # `x` so we can skip them
        if !is_concrete_type(x, field)
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

# `string` ensures that the object can be ordered
# NOTE: really we could sort by the hash and that would be consistent in all cases
sort_items_by(x::AbstractDict) = string

keytype(::Type{<:Pair{K,T}}) where {K,T} = K
valtype(::Type{<:Pair{K,T}}) where {K,T} = T
keytype(::Type{<:T}) where {T} = T
valtype(::Type{<:T}) where {T} = T

function transform_type(::Type{T}, ::S) where {T,S<:StructTypes.DictType}
    name = qualified_name_(S)
    return name, keytype(eltype(T)), valtype(eltype(T))
end

function stable_hash_helper(x, hash_state, context, ::StructTypes.DictType)
    pairs = StructTypes.keyvaluepairs(x)
    nested_hash_state = start_nested_hash!(hash_state)

    pairs = isnothing(sort_items_by(x)) ? StructTypes.keyvaluepairs(x) :
            sort(StructTypes.keyvaluepairs(x); by=sort_items_by(x))
    if has_concrete_eltype(pairs)
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

function stable_hash_helper(x, hash_state, context, ::StructTypes.CustomStruct)
    lowered = StructTypes.lower(x)
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
