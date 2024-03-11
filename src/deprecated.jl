# NOTE: all of this code is copy pasted from the old `StableHashTraits.jl` modulo some
# changes to names
function hash_method end

struct NotImplemented end
is_implemented(::NotImplemented) = false
is_implemented(_) = true

# recurse up to the parent until a method is defined or we hit the root (with parent `nothing`)
hash_method(x, context) = hash_method(x, parent_context(context))
# if we hit the root context, we call the one-argument form, which could be extended by a
# user
hash_method(x, ::Nothing) = hash_method(x)
hash_method(_) = NotImplemented()

function deprecated_hash_helper(x, hash_state, context, method::NotImplemented)
    throw(ArgumentError("There is no appropriate `hash_method` defined for objects" *
                        " of type `$(typeof(x))` in context of type `$(typeof(context))`."))
    return
end

function deprecated_hash_helper(x, hash_state, context, method)
    throw(ArgumentError("Unrecognized hash method of type `$(typeof(method))` when " *
                        "hashing object $x. The implementation of `hash_method` for this " *
                        "object is invalid."))
    return
end

#####
##### ================ Deprecated Hash Traits ================
#####

#####
##### WriteHash
#####

struct WriteHash end

"""
    StableHashTraits.write(io, x, [context])

Writes contents of `x` to an `io` buffer to be hashed during a call to `stable_hash`.
Fall back methods are defined as follows:

    write(io, x, context) = write(io, x)
    write(io, x) = Base.write(io, x)

Users of `StableHashTraits` can overwrite either the 2 or 3 argument version for
their types to customize the behavior of `stable_hash`.

See also: [`StableHashTraits.hash_method`](@ref).
"""
write(io, x, context) = write(io, x)
write(io, x) = Base.write(io, x)

# TODO: add deprecations for StructHash etc...
function deprecated_hash_helper(x, hash_state, context, ::WriteHash)
    return update_hash!(hash_state, x, context)
end

#####
##### IterateHash
#####

struct IterateHash end
function deprecated_hash_helper(xs, hash_state, context, ::IterateHash)
    return hash_foreach(hash_state, context, xs) do x
        return x, hash_method(x, context)
    end
end

function hash_foreach(fn, hash_state, context, xs)
    root_version(context) > 1 && return hash_foreach_new(fn, hash_state, context, xs)
    return hash_foreach_old(fn, hash_state, context, xs)
end

function hash_foreach_old(fn, hash_state, context, xs)
    for x in xs
        f_x, method = fn(x)
        inner_state = start_nested_hash!(hash_state)
        inner_state = deprecated_hash_helper(f_x, inner_state, context, method)
        hash_state = end_nested_hash!(hash_state, inner_state)
    end
    return hash_state
end

function hash_foreach_new(fn, hash_state, context, xs)
    inner_state = start_nested_hash!(hash_state)
    for x in xs
        f_x, method = fn(x)
        inner_state = deprecated_hash_helper(f_x, inner_state, context, method)
    end
    hash_state = end_nested_hash!(hash_state, inner_state)
    return hash_state
end

#####
##### StructHash
#####

struct StructHash{P,S}
    fnpair::P
end
fieldnames_(::T) where {T} = fieldnames(T)
StructHash(sort::Symbol) = StructHash(fieldnames_ => getfield, sort)
function StructHash(fnpair::Pair=fieldnames_ => getfield, by::Symbol=:ByOrder)
    by ∈ (:ByName, :ByOrder) || error("Expected a valid sort order (:ByName or :ByOrder).")
    return StructHash{typeof(fnpair),by}(fnpair)
end
orderfields(::StructHash{<:Any,:ByOrder}, props) = props
orderfields(::StructHash{<:Any,:ByName}, props) = sort_(props)
sort_(x::Tuple) = TupleTools.sort(x; by=string)
sort_(x::AbstractSet) = sort!(collect(x); by=string)
sort_(x) = sort(x; by=string)

function deprecated_hash_helper(x, hash_state, context, use::StructHash{<:Any,S}) where {S}
    fieldsfn, getfieldfn = use.fnpair
    if root_version(context) > 1 && fieldsfn isa typeof(fieldnames_)
        # NOTE: hashes the field names at compile time if possible (~x10 speed up)
        hash_state = deprecated_hash_helper(stable_typefields_id(x), hash_state, context,
                                        WriteHash())
        # NOTE: sort fields at compile time if possible (~x1.33 speed up)
        fields = S == :ByName ? sorted_field_names(x) : fieldnames_(x)
        hash_state = hash_foreach(hash_state, context, fields) do k
            val = getfieldfn(x, k)
            return val, hash_method(val, context)
        end
    else
        return hash_foreach(hash_state, context, orderfields(use, fieldsfn(x))) do k
            pair = k => getfieldfn(x, k)
            return pair, hash_method(pair, context)
        end
    end
end

#####
##### Stable values for types
#####

qualified_type_(fn::Function) = qname_(fn, string)
qualified_type_(x::T) where {T} = qname_(T <: DataType ? x : T, string)
qualified_(T, ::Val{:name}) = qualified_name_(T)
qualified_(T, ::Val{:type}) = qualified_type_(T)
# we need `Type{Val}` methods below because the generated functions that call `qualified_`
# only have access to the type of a value
qualified_(T, ::Type{Val{:name}}) = qualified_name_(T)
qualified_(T, ::Type{Val{:type}}) = qualified_type_(T)

# deprecate external use of `qualified_name/type`
function qualified_name(x)
    Base.depwarn("`qualified_name` is deprecated, favor `stable_typename_id` in all cases " *
                 "where backwards compatible hash values are not required.",
                 :qualified_name)
    return qualified_name_(x)
end
function qualified_type(x)
    Base.depwarn("`qualified_type` is deprecated, favor `stable_type_id` in all cases " *
                 "where backwards compatible hash values are not required.",
                 :qualified_type)
    return qualified_type_(x)
end

bytes_of_val(f) = reinterpret(UInt8, [f;])
bytes_of_val(f::Symbol) = codeunits(String(f))
bytes_of_val(f::String) = codeunits(f)

function hash64(x)
    bytes = sha256(bytes_of_val(x))
    # take the first 64 bytes of `bytes`
    return first(reinterpret(UInt64, bytes))
end

function hash64(values::Tuple)
    sha = SHA.SHA2_256_CTX()
    for val in values
        SHA.update!(sha, bytes_of_val(val))
    end
    bytes = SHA.digest!(sha)
    # take the first 64 bytes of our hash
    return first(reinterpret(UInt64, bytes))
end

macro hash64(constant)
    if constant isa Symbol || constant isa String || constant isa Number
        return hash64(constant)
    else
        return :(throw(ArgumentError(string("Unexpected expression: ", $(string(constant))))))
    end
end

# NOTE: using stable_{typename|type}_id increases speed by ~x10-20 vs. `qualified_name`

"""
    stable_typename_id(x)

Returns a 64 bit hash that is the same for a given type so long as the name and the module
of the type doesn't change.

## Example

```jldoctest
julia> stable_typename_id([1, 2, 3])
0x56c6b9ca080a0aa4

julia> stable_typename_id(["a", "b"])
0x56c6b9ca080a0aa4
```

!!! note
    If the module of a type is `Core` it is renamed to `Base` before hashing because the
    location of some types changes between `Core` to `Base` across julia versions.
    Likewise, the type names of AbstractArray types are made uniform
    as their printing changes from Julia 1.6 -> 1.7.
"""
stable_typename_id(x) = stable_id_helper(x, Val(:name))
stable_id_helper(::Type{T}, of::Val) where {T} = hash64(qualified_(T, of))
@generated function stable_id_helper(x, of)
    T = x <: Function ? x.instance : x
    str = qualified_(T, of)
    number = hash64(str)
    :(return $number)
end

"""
    stable_type_id(x)`

Returns a 64 bit hash that is the same for a given type so long as the module, and string
representation of a type is the same (invariant to comma spacing).

## Example

```jldoctest
julia> stable_type_id([1, 2, 3])
0xfd5878e59e259648

julia> stable_type_id(["a", "b"])
0xe191f67c4c8e3370
```

!!! note
    If the module of a type is `Core` it is renamed to `Base` before hashing because the
    location of some types changes between `Core` to `Base` across julia versions.
    Likewise, the type names of AbstractArray types are made uniform
    as their printing changes from Julia 1.6 -> 1.7.
"""
stable_type_id(x) = stable_id_helper(x, Val(:type))

"""
    stable_typefields_id(x)

Returns a 64 bit hash that is the same for a given type so long as the set of field names
remains unchanged.
"""
stable_typefields_id(::Type{T}) where {T} = hash64(sort_(fieldnames(T)))
@generated function stable_typefields_id(x)
    number = hash64(sort_(fieldnames(x)))
    return :(return $number)
end

#####
##### FnHash
#####

struct FnHash{F,H}
    fn::F
    result_method::H # if non-nothing, apply to result of `fn`
end
FnHash(fn) = FnHash{typeof(fn),Nothing}(fn, nothing)
get_value_(x, method::FnHash) = method.fn(x)

struct PrivateConstantHash{T,H}
    constant::T
    result_method::H # if non-nothing, apply to value `constant`
end
PrivateConstantHash(val) = PrivateConstantHash{typeof(val),Nothing}(val, nothing)
get_value_(x, method::PrivateConstantHash) = method.constant

function ConstantHash(constant, method=nothing)
    Base.depwarn("`ConstantHash` has been deprecated, favor ` ConstantHash`.",
                 :ConstantHash)
    return PrivateConstantHash(constant, method)
end

macro ConstantHash(constant)
    if constant isa Symbol || constant isa String || constant isa Number
        return :(PrivateConstantHash($(hash64(constant)), WriteHash()))
    else
        return :(throw(ArgumentError(string("Unexpected expression: ", $(string(constant))))))
    end
end

function deprecated_hash_helper(x, hash_state, context,
                            method::Union{FnHash,PrivateConstantHash})
    y = get_value_(x, method)
    new_method = @something(method.result_method, hash_method(y, context))
    if typeof(x) == typeof(y) && method == new_method
        methodstr = nameof(typeof(method))
        msg = """`$methodstr` is incorrectly called inside
              `hash_method(::$(typeof(x)), ::$(typeof(context))). Applying
              it would lead to infinite recursion. This can usually be
              fixed by passing a second argument to `$methodstr`."""
        throw(ArgumentError(replace(msg, r"\s+" => " ")))
    end

    return deprecated_hash_helper(y, hash_state, context, new_method)
end

#####
##### Tuples
#####

function deprecated_hash_helper(x, hash_state, context, methods::Tuple)
    return hash_foreach(hash_state, context, methods) do method
        return x, method
    end
end

#####
##### HashAndContext
#####

"""

    HashAndContext(method, old_context -> new_context)

A special hash method that changes the context when hashing the contents of an object. The
`method` defines how the object itself should be hashed and the second argument is a
callable which transforms the old context to the new.

For example, here is how we can make sure the arrays in a specific object have a hash that
is invariant to endianness without having to copy the array.

```julia
struct EndianInvariant{P}
    parent_context::P
end
StableHashTraits.parent_context(x::EndianInvariant) = x.parent_context

struct CrossPlatformData
    data::Vector{Int}
end

StableHashTraits.hash_method(::Number, ::EndianInvariant) = FnHash(htol, WriteHash())
StableHashTraits.hash_method(::CrossPlatformData) = HashAndContext(IterateHash(), EndianInvariant)
```

Note that we could accomplish this same behavior using `FnHash(x -> htol.(x.data))`, but it
would require copying that data to do so.
"""
struct HashAndContext{F,M}
    parent::M
    contextfn::F
end
function deprecated_hash_helper(x, hash_state, context, method::HashAndContext)
    return deprecated_hash_helper(x, hash_state, method.contextfn(context), method.parent)
end

#####
##### Deprecations
#####

# deprecations
@deprecate UseWrite() WriteHash()
@deprecate UseIterate() IterateHash()
@deprecate UseProperties(order) StructHash(propertynames => getproperty, order)
@deprecate UseProperties() StructHash(propertynames => getproperty)
@deprecate UseQualifiedName(method) (FnHash(qualified_name, WriteHash()), method)
@deprecate UseQualifiedName() FnHash(qualified_name, WriteHash())
@deprecate UseSize(method) (FnHash(size), method)
@deprecate UseTable() FnHash(Tables.columns,
                             StructHash(Tables.columnnames => Tables.getcolumn))
#####
##### ================ Hash Contexts ================
#####

"""
    StableHashTraits.parent_context(context)

Return the parent context of the given context object. (See [`hash_method`](@ref) for
details of using context). The default method falls back to returning `HashVersion{1}`, but
this is flagged as a deprecation warning; in the future it is expected that all contexts
define this method.

This is normally all that you need to know to implement a new context. However, if your
context is expected to be the root context—one that does not fallback to any parent (akin to
`HashVersion`)—then there may be a bit more work involved. In this case, `parent_context`
should return `nothing` so that the single argument fallback for `hash_method` can be
called. You will also need to define [`StableHashTraits.root_version`](@ref).

Furthermore, if you implement a root context you will probably have to manually manage the
fallback to single-argument `hash_method` methods to avoid method ambiguities.

```julia
# generic fallback method
function hash_method(x::T, ::MyRootContext) where T
    default_method = hash_method(x)
    StableHashTraits.is_implemented(default_method) && return default_method

    # return generic fallback hash trait here
end
```

This works because `hash_method(::Any)` returns a sentinel value
(`StableHashTraits.NotImplemented()`) that indicates that there is no more specific method
available. This pattern is necessary to avoid the method ambiguities that would arise
between `hash_method(x::MyType, ::Any)` and `hash_method(x::Any, ::MyRootContext)`.
Generally if a type implements hash_method for itself, but absent a context, we want the
`hash_method` that does not accept a context argument to be used.
"""
function parent_context(x::Any)
    Base.depwarn("You should explicitly define a `parent_context` method for context " *
                 "`$x`. See details in the docstring of `hash_method`.", :parent_context)
    return HashVersion{1}()
end

"""
    StableHashTraits.root_version(context)

Return the version of the root context: an integer in the range (1, 2). The default
fallback method value returns 1.

In almost all cases, a root hash context should return 2. The optimizations used in
HashVersion{2} include a number of changes to the hash-trait implementations that do not
alter the documented behavior but do change the actual hash value returned because of how
and when elements get hashed.

"""
root_version(x::Nothing) = 1
root_version(x) = root_version(parent_context(x))

#####
##### HashVersion{V} (root contexts)
#####

parent_context(::HashVersion) = nothing
root_version(::HashVersion{V}) where {V} = V

# NOTE: below, using root_version lets us leave `HashVersion{1}` return values unchanged, only
# using the newer (more efficeint) hash_method return-values for `HashVersion{2}`.

function hash_method(x::T, c::HashVersion{V}) where {T,V}
    # we need to find `default_method` here because `hash_method(x::MyType, ::Any)` is less
    # specific than the current method, but if we have something defined for a specific type
    # as the first argument, we want that to be used, rather than this fallback (as if it
    # were defined as `hash_method(::Any)`). Note that changing this method to be x::Any,
    # and using T = typeof(x) would just lead to method ambiguities when trying to decide
    # between `hash_method(::Any, ::HashVersion{V})` vs. `hash_method(::MyType, ::Any)`.
    # Furthermore, this would would require the user to define `hash_method` with two
    # arguments.
    default_method = hash_method(x, parent_context(c)) # we call `parent_context` to exercise all fallbacks
    is_implemented(default_method) && return default_method
    Base.isprimitivetype(T) && return WriteHash()
    # merely reordering a struct's fields should be considered an implementation detail, and
    # should not change the hash
    return (TypeHash(c), StructHash(:ByName))
end
TypeHash(::HashVersion{1}) = FnHash(qualified_type_)
TypeHash(::HashVersion) = FnHash(stable_type_id, WriteHash())
TypeNameHash(::HashVersion{1}) = FnHash(qualified_name)
# we can use a more conservative id here, we used a shorter one before to avoid hashing long strings
TypeNameHash(::HashVersion) = FnHash(stable_type_id, WriteHash())

hash_method(::NamedTuple, c::HashVersion) = (TypeNameHash(c), StructHash())
function hash_method(::AbstractRange, c::HashVersion)
    return (TypeNameHash(c), StructHash(:ByName))
end
function hash_method(::AbstractArray, c::HashVersion)
    return (TypeNameHash(c), FnHash(size), IterateHash())
end
function hash_method(::AbstractString, c::HashVersion{V}) where {V}
    return (FnHash(V > 1 ? stable_type_id : qualified_name, WriteHash()),
            WriteHash())
end
hash_method(::Symbol, ::HashVersion{1}) = (PrivateConstantHash(":"), WriteHash())
hash_method(::Symbol, ::HashVersion) = (@ConstantHash(":"), WriteHash())
function hash_method(::AbstractDict, c::HashVersion{V}) where {V}
    return (V < 2 ? FnHash(qualified_name_) :
            FnHash(stable_typename_id, WriteHash()), StructHash(keys => getindex, :ByName))
end
hash_method(::Tuple, c::HashVersion) = (TypeNameHash(c), IterateHash())
hash_method(::Pair, c::HashVersion) = (TypeNameHash(c), IterateHash())
function hash_method(::Type, c::HashVersion{1})
    return (PrivateConstantHash("Base.DataType"), FnHash(qualified_type_))
end
function hash_method(::Type, c::HashVersion)
    return (@ConstantHash("Base.DataType"), TypeHash(c))
end
function hash_method(::Function, c::HashVersion{1})
    return (PrivateConstantHash("Base.Function"), FnHash(qualified_name_))
end
function hash_method(::Function, c::HashVersion)
    return (@ConstantHash("Base.Function"), TypeHash(c))
end
function hash_method(::AbstractSet, c::HashVersion)
    return (TypeNameHash(c), FnHash(sort! ∘ collect))
end
function hash_method(fn::Base.Fix1, c::HashVersion{1})
    return invoke(hash_method, Tuple{Function,typeof(c)}, fn, c)
end
function hash_method(fn::Base.Fix2, c::HashVersion{1})
    return invoke(hash_method, Tuple{Function,typeof(c)}, fn, c)
end
hash_method(fn::Base.Fix1, c::HashVersion) = (@ConstantHash("Base.Fix1"), StructHash())
hash_method(fn::Base.Fix2, c::HashVersion) = (@ConstantHash("Base.Fix2"), StructHash())
