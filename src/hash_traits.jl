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
HashType(x) = StructType(x)
HashType(::Type) = TypeType()
HashType(::Module) = TypeType()
HashType(::Function) = TypeType()

function stable_type_hash(T, hash_state, context, ::TypeType)
    return update_hash!(hash_state, @hash64("TypeType"), context)
end

function stable_hash_helper(T, hash_state, context, ::TypeType)
    return stable_type_hash(T, hash_state, context, StructTypes.UnorderedStruct())
end

function stable_type_hash(::Type{T}, hash_state, context, ::StructTypes.NoStructType) where {T<:Function}
    if hasproperty(T, :instance) && isdefined(T, :instance)
        return stable_type_hash(T.instance, hash_state, context, StructTypes.UnorderedStruct())
    else
        return stable_type_hash(T, hash_state, context, StructTypes.UnorderedStruct())
    end
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

sorted_field_names(T::Type) = TupleTools.sort(fieldnames(T); by=string)
@generated function sorted_field_names(T)
    return TupleTools.sort(fieldnames(T); by=string)
end

function stable_type_hash(T::Union{Type, Function}, hash_state, context, st::StructTypes.DataType)
    bytes = get!(context, T) do
        type_hash_state = similar_hash_state(hash_state)
        type_hash_state = stable_hash_helper(qualified_name_(T), type_hash_state,
                                             context, StructTypes.StringType())
        # NOTE: functions sometimes have fields (e.g. a closure or a struct <: Function) and
        # can be hashed as such; in any case `fieldnames` safely returns an empty tuple for
        # functions that do not have fields
        if (T isa DataType || T isa Function) && !isabstracttype(T)
            for f in sorted_field_names(T)
                type_hash_state = stable_hash_helper(String(f), type_hash_state,
                                                     context, StructTypes.StringType())
                T_ = T isa Function ? typeof(T) : T
                type_hash_state = stable_type_hash(fieldtype(T_, f), type_hash_state,
                                                   context, StructType(fieldtype(T_, f)))
            end
        end
        return reinterpret(UInt8, asarray(compute_hash!(type_hash_state)))
    end
    return update_hash!(hash_state, bytes, context)
end

function is_concrete_type(x, k)
    return isdispatchtuple(Tuple{fieldtype(typeof(x), k)})
end

function stable_hash_helper(x, hash_state, context, st::StructTypes.DataType)
    nested_hash_state = start_nested_hash!(hash_state)

    # hash the field values themselves
    fields = st isa StructTypes.UnorderedStruct ? sorted_field_names(x) :
             fieldnames(typeof(x))
    for field in fields
        val = getfield(x, field)
        # field types that are concrete have already been accounted for in the type hash of
        # `x` so we can skip them
        if !is_concrete_type(x, field)
            # YES: we do hash the type *before* transformation; if `transform` is type
            # stable we can generally think of the type hash before or after transform as
            # equivalent. If it isn't, the type before hashing may still be disambguiate the
            # hashed transform content so long as all unique byte sequences hashed hashed
            # due to the `transform` uniquely map to a single type. In practice, for sane
            # uses of transform, this will be the case. If we were to hash the type *after*
            # transformation we would then need to *require* `transform` to be type stable,
            # since otherwise the type hash would vary depending on the value passed to
            # `transform`. Thus, by doing this operation before means we the assumptions
            # placed on `transform` are weaker. To avoid these assumptions entirely, we'd
            # have to always hash the type for every value, which reduces performance by
            # ~10-100x fold in the benchmarks.
            stable_type_hash(typeof(val), hash_state, context, HashType(val))
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

asarray(x) = [x]
asarray(x::AbstractArray) = x
function stable_type_hash(T::Type, hash_state, context, ::StructTypes.ArrayType)
    bytes = get!(context, T) do
        type_hash_state = similar_hash_state(hash_state)
        type_hash_state = stable_hash_helper(qualified_name_(T), type_hash_state,
                                             context, StructTypes.StringType())
        type_hash_state = stable_type_hash(eltype(T), type_hash_state, context,
                                           StructType(eltype(T)))
        return reinterpret(UInt8, asarray(compute_hash!(type_hash_state)))
    end
    return update_hash!(hash_state, bytes, context)
end

function stable_hash_helper(xs, hash_state, context, ::StructTypes.ArrayType)
    nested_hash_state = start_nested_hash!(hash_state)

    items = !isnothing(sort_items_by(xs)) ? sort(xs; by=sort_items_by(x)) : xs
    if has_concrete_eltype(items)
        x1 = first(items)
        stable_type_hash(typeof(x1), nested_hash_state, context, HashType(x1))
        for x in items
            tx = transform(x, context)
            nested_hash_state = stable_hash_helper(tx, nested_hash_state, context,
                                                   HashType(tx))
        end
    else
        for x in items
            stable_type_hash(typeof(x), nested_hash_state, context, HashType(x))
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

function stable_type_hash(T::Type{<:Tuple}, hash_state, context, ::StructTypes.ArrayType)
    bytes = get!(context, T) do
        type_hash_state = similar_hash_state(hash_state)
        type_hash_state = stable_hash_helper(qualified_name_(T), type_hash_state,
                                             context, StructTypes.StringType())

        if !isabstracttype(T)
            for f in fieldnames(T)
                type_hash_state = stable_type_hash(fieldtype(T, f), type_hash_state,
                                                context, StructType(T))
            end
        end
        return reinterpret(UInt8, asarray(compute_hash!(type_hash_state)))
    end
    return update_hash!(hash_state, bytes, context)
end

function stable_type_hash(T::Type{<:NTuple}, hash_state, context, ::StructTypes.ArrayType)
    bytes = get!(context, T) do
        type_hash_state = similar_hash_state(hash_state)
        type_hash_state = stable_hash_helper(qualified_name_(T), type_hash_state,
                                             context, StructTypes.StringType())
        type_hash_state = stable_type_hash(eltype(T), type_hash_state, context,
                                           StructType(eltype(T)))
        return reinterpret(UInt8, asarray(compute_hash!(type_hash_state)))
    end
    return update_hash!(hash_state, bytes, context)
end

# TODO: how to handle varargs...

function stable_hash_helper(x::Tuple, hash_state, context,
                            st::StructTypes.ArrayType)
    nested_hash_state = start_nested_hash!(hash_state)

    # hash the tuple field values themselves
    for field in fieldnames(typeof(x))
        val = getfield(x, field)
        # field types that are concrete have already been accounted for in the type hash of
        # `x` so we can skip them
        if !is_concrete_type(x, field)
            # TODO: reference note about when we hash types
            stable_type_hash(typeof(val), hash_state, context, HashType(val))
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
sort_items_by(x::AbstractDict) = string ∘ first

keytype(::Pair{K,T}) where {K,T} = K
valtype(::Pair{K,T}) where {K,T} = T
keytype(::T) where {T} = T
valtype(::T) where {T} = T

function stable_type_hash(T::Type, hash_state, context, ::StructTypes.DictType)
    bytes = get!(context, T) do
        type_hash_state = similar_hash_state(hash_state)
        type_hash_state = stable_hash_helper(qualified_name_(T), type_hash_state,
                                             context, StructTypes.StringType())
        K = keytype(eltype(T))
        type_hash_state = stable_type_hash(K, type_hash_state, context, StructType(K))
        V = valtype(eltype(T))
        type_hash_state = stable_type_hash(V, type_hash_state, context, StructType(V))
        return reinterpret(UInt8, asarray(compute_hash!(type_hash_state)))
    end
    return update_hash!(hash_state, bytes, context)
end

function stable_hash_helper(x, hash_state, context, ::StructTypes.DictType)
    pairs = StructTypes.keyvaluepairs(x)
    nested_hash_state = start_nested_hash!(hash_state)

    pairs = isnothing(sorted_items_by(x)) ? StructTypes.keyvaluepairs(x) :
            sort(StructTypes.keyvaluepairs(x); by=sort_items_by(x))
    if has_concrete_eltype(pairs)
        (key1, val1) = first(pairs)
        stable_type_hash(typeof(key1), nested_hash_state, context, HashType(key1))
        stable_type_hash(typeof(val1), nested_hash_state, context, HashType(val1))
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
            stable_type_hash(typeof(key1), nested_hash_state, context,
                             HashType(key1))
            stable_type_hash(typeof(val1), nested_hash_state, context,
                             HashType(val1))
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

function stable_type_hash(x, hash_state, context, ::StructTypes.CustomStruct)
    # we can't know what types will show up after a call to `lower` so in this case we just
    # give up and always hash the type during the call to `stale_hash_helper` below
    return hash_state
end

function stable_hash_helper(x, hash_state, context, ::StructTypes.CustomStruct)
    lowered = StructTypes.lower(x)
    trait = HashType(lowered)
    stable_type_hash(typeof(x), hash_state, context, trait)
    return stable_hash_helper(lowered, hash_state, context, trait)
end

#####
##### Basic data types
#####

transform(x::Symbol) = @hash64(":"), String(x)

function stable_type_hash(T, hash_state, context, ::StructTypes.StringType)
    return update_hash!(hash_state, @hash64("StringType"), context)
end

function stable_hash_helper(str, hash_state, context,
                            ::StructTypes.StringType)
    nested_hash_state = start_nested_hash!(hash_state)
    update_hash!(nested_hash_state, str isa AbstractString ? str : string(str), context)
    return end_nested_hash!(hash_state, nested_hash_state)
end

function stable_type_hash(T, hash_state, context, ::StructTypes.NumberType)
    U = StructTypes.numbertype(T)
    bytes = get!(context, U) do
        type_hash_state = similar_hash_state(hash_state)
        type_hash_state = stable_hash_helper(qualified_name_(U), type_hash_state, context,
                                             StructTypes.StringType())
        return reinterpret(UInt8, asarray(compute_hash!(type_hash_state)))
    end
    return update_hash!(hash_state, bytes, context)
end

function stable_hash_helper(number::T, hash_state, context,
                            ::StructTypes.NumberType) where {T}
    U = StructTypes.numbertype(T)
    return update_hash!(hash_state, U(number), context)
end

function stable_type_hash(_, hash_state, context, ::StructTypes.BoolType)
    return update_hash!(hash_state, @hash64("BoolType"), context)
end

function stable_hash_helper(bool, hash_state, context, ::StructTypes.BoolType)
    return update_hash!(hash_state, Bool(bool), context)
end

function stable_type_hash(_, hash_state, context, ::StructTypes.NullType)
    return update_hash!(hash_state, @hash64("NullType"), context)
end

function stable_hash_helper(_, hash_state, context, ::StructTypes.NullType)
    return hash_state
end
