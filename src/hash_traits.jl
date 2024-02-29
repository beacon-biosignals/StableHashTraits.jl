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

sorted_field_names(x::Type) = TupleTools.sort(fieldnames(T); by=string)
@generated function sorted_field_names(T)
    return TupleTools.sort(fieldnames(T); by=string)
end

function stable_type_hash(T::Type, hash_state, context, st::StructTypes.DataType)
    bytes = get!(context, T) do
        type_context = HashVersion{3}()
        type_hash_state = similar_hash_state(hash_state)
        type_hash_state = stable_hash_helper(qualified_name_(T), type_hash_state,
                                             type_context,
                                             StructTypes.StringType())
        if T isa DataType
            for f in sorted_field_names(T)
                type_hash_state = stable_hash_helper(String(f), type_hash_state,
                                                     type_context,
                                                     StructTypes.StringType())
                type_hash_state = stable_type_hash(fieldtype(T, f), type_hash_state,
                                                   type_context,
                                                   StructType(T))
            end
        end
        return compute_hash!(type_hash_state)
    end
    return update_hash!(hash_state, bytes, context)
end

function is_concrete_type(x, k)
    return isdispatchtuple(Tuple{fieldtype(typeof(x), k)})
end

function stable_hash_helper(x, hash_state, context, st::StructTypes.DataType)
    nested_hash_state = start_nested_hash!(hash_state)

    # hash the field values themselves
    fields = st isa StructTypes.UnorderedStruct ? sorted_field_names(typeof(x)) :
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
            stable_type_hash(val, hash_state, context, HashType(val, st))
        end

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

sort_items_by(x) = nothing
# TODO: implement order_matters(::OrderedDict) = string ∘ first etc...

function stable_hash_helper(x, hash_state, context, ::StructTypes.DictType)
    pairs = StructTypes.keyvaluepairs(x)
    nested_hash_state = start_nested_hash!(hash_state)

    pairs = isnothing(sorted_items_by(x)) ? StructTypes.keyvaluepairs(x) :
            sort(StructTypes.keyvaluepairs(x); by=sort_items_by)
    for (key, value) in pairs
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

sort_items_by(x) = nothing
sort_items_by(::AbstractSet) = string

function transform(x::AbstractArray, c::HashVersion{3})
    return @hash64("Base.AbstractArray"), size(x), vec(x)
end
transform(x::AbstractVector, c::HashVersion{3}) = x
HashType(x::AbstractRange, c::HashVersion{3}) = StructTypes.Struct()

function has_concrete_eltype(xs)
    return isdispatchtuple(typeof(xs))
end

function stable_type_hash(T::Type, hash_state, context, ::StructTypes.ArrayType)
    bytes = get!(context, T) do
        type_context = HashVersion{3}()
        type_hash_state = similar_hash_state(hash_state)
        type_hash_state = stable_hash_helper(qualified_name_(T), type_hash_state, type_context,
                           StructTypes.StringType())
        type_hash_state = stable_type_hash(eltype(T), field_hash, type_context,
                                            StructType(T))
        return compute_hash!(type_hash_state)
    end
    return update_hash!(hash_state, bytes, context)
end

function stable_hash_helper(xs, hash_state, context, ::StructTypes.ArrayType)
    nested_hash_state = start_nested_hash!(hash_state)

    nested_hash_state = stable_hash_helper(tag, nested_hash_state, context,
                                           StructTypes.NumberType())

    items = order_matters(x) ? sort(xs; by=string) : xs
    if has_concrete_eltype(items)
        x1 = first(items)
        stable_type_hash(x1, nested_hash_state, context, HashType(x1, content))
        for x in items
            tx = transform(x, context)
            nested_hash_state = stable_hash_helper(tx, nested_hash_state, context,
                                                   HashType(tx, context))
        end
    else
        for x in items
            stable_type_hash(x, nested_hash_state, context, HashType(x, context))
            tx = transform(x, context)
            nested_hash_state = stable_hash_helper(tx, nested_hash_state, context,
                                                   HashType(tx, context))
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
        type_context = HashVersion{3}()
        type_hash_state = similar_hash_state(hash_state)
        type_hash_state = stable_hash_helper(qualified_name_(T), type_hash_state, type_context,
                           StructTypes.StringType())
        for f in fieldnames(T)
            type_hash_state = stable_type_hash(fieldtype(T, f), type_hash_state,
                                                type_context, StructType(T))
        end
        return compute_hash!(type_hash_state)
    end
    return update_hash!(hash_state, bytes, context)
end

function stable_hash_helper(x::Tuple{<:Tuple}, hash_state, context, st::StructTypes.ArrayType)
    nested_hash_state = start_nested_hash!(hash_state)

    # hash the tuple field values themselves
    for field in fieldnames(typeof(x))
        val = getfield(x, field)
        # field types that are concrete have already been accounted for in the type hash of
        # `x` so we can skip them
        if !is_concrete_type(x, field)
            # TODO: reference note about when we hash types
            stable_type_hash(val, hash_state, context, HashType(val, st))
        end

        tval = transform(val, context)
        nested_hash_state = stable_hash_helper(tval, nested_hash_state, context,
                                               HashType(tval, context))
    end

    hash_state = end_nested_hash!(hash_state, nested_hash_state)
    return hash_state
end


#####
##### CustomStruct
#####

function stable_type_hash(x, hash_state, context, ::StructTypes.CustomStruct)
    # well shoot... this doesn't work
end

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
    nested_hash_state = start_nested_hash!(hash_state)
    update_hash!(nested_hash_state, str isa AbstractString ? str : string(str), context)
    return end_nested_hash!(hash_state, nested_hash_state)
end

function stable_hash_helper(number::T, hash_state, context,
                            ::StructTypes.NumberType) where {T}
    U = StructTypes.numbertype(T)
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
