module StableHashTraits

const NAMED_TUPLES_PRETTY_PRINT_VERSION = v"1.10.0-DEV.885"

export stable_hash, WriteHash, IterateHash, StructHash, FnHash, ConstantHash, @ConstantHash,
       HashAndContext, HashVersion, qualified_name, qualified_type, TablesEq, ViewsEq,
       stable_typename_id, stable_type_id
using TupleTools, Tables, Compat
# we need this to parse and re-arrange type string outputs in Julia 1.10 and later.
@static if VERSION >= NAMED_TUPLES_PRETTY_PRINT_VERSION
    using PikaParser
end
using SHA: SHA, sha256

"""
    HashVersion{V}()

The default `hash_context` used by `stable_hash`. There are currently two versions
(1 and 2). Version 2 is far more optimized than 1 and should generally be used in newly
written code. Version 1 is the default version, so as to avoid changing the hash computed
by existing code.

By explicitly passing this hash version in `stable_hash` you ensure that hash values for
these fallback methods will not change even if new fallbacks are defined.
"""
struct HashVersion{V}
    function HashVersion{V}() where {V}
        V == 1 && Base.depwarn("HashVersion{1} is deprecated, favor `HashVersion{2}` in " *
                               "all cases where backwards compatible hash values are not " *
                               "required.", :HashVersion)
        return new{V}()
    end
end

"""
    stable_hash(x, context=HashVersion{1}(); alg=sha256)
    stable_hash(x; alg=sha256, version=1)

Create a stable hash of the given objects. As long as the context remains the same, this is
intended to remain unchanged across julia versions. How each object is hashed is determined
by [`hash_method`](@ref), which aims to have sensible fallbacks.

To ensure the greatest stability, you should explicitly pass the context object. It is also
best to pass an explicit version, since `HashVersion{2}` is generally faster than
`HashVersion{1}`. If the fallback methods change in a future release, the hash you get
by passing an explicit `HashVersion{N}` should *not* change. (Note that the number in
`HashVersion` does not necessarily match the package version of `StableHashTraits`).

Instead of passing a context, you can instead pass a `version` keyword, that will
set the context to `HashVersion{version}()`.

To change the hash algorithm used, pass a different function to `alg`. It accepts any `sha`
related function from `SHA` or any function of the form `hash(x::AbstractArray{UInt8},
[old_hash])`.

The `context` value gets passed as the second argument to [`hash_method`](@ref), and as the
third argument to [`StableHashTraits.write`](@ref)

"""
stable_hash(x; alg=sha256, version=1) = return stable_hash(x, HashVersion{version}(); alg)
function stable_hash(x, context; alg=sha256)
    return compute_hash!(stable_hash_helper(x, HashState(alg, context), context,
                                            hash_method(x, context)))
end

# extract contents of README so we can insert it into the some of the docstrings
let
    readme_file = joinpath(pkgdir(StableHashTraits), "README.md")
    Base.include_dependency(readme_file)
    readme = read(readme_file, String)
    traits = match(r"START_HASH_TRAITS -->(.*)<!-- END_HASH_TRAITS"s, readme).captures[1]
    contexts = match(r"START_CONTEXTS -->(.*)<!-- END_CONTEXTS"s, readme).captures[1]
    # TODO: if we ever generate `Documenter.jl` docs we need to revise the
    # links to symbols here

    @doc """
        StableHashTraits.hash_method(x, [context])

    Retrieve the trait object that indicates how a type should be hashed using `stable_hash`.
    You should return one of the following values.

    $traits

    $contexts
    """ hash_method
end

function hash_method end

# recurse up to the parent until a method is defined or we hit the root (with parent `nothing`)
hash_method(x, context) = hash_method(x, parent_context(context))
# if we hit the root context, we call the one-argument form, which could be extended by a
# user
hash_method(x, ::Nothing) = hash_method(x)
# we signal that a method specific to a type is not available using `NotImplemented`; we
# need this to avoid method ambiguities, see `hash_method(x::T, ::HashContext) where T
# below for details
struct NotImplemented end
hash_method(_) = NotImplemented()
is_implemented(::NotImplemented) = false
is_implemented(_) = true

function stable_hash_helper(x, hash_state, context, method::NotImplemented)
    throw(ArgumentError("There is no appropriate `hash_method` defined for objects" *
                        " of type `$(typeof(x))` in context of type `$(typeof(context))`."))
    return nothing
end

function stable_hash_helper(x, hash_state, context, method)
    throw(ArgumentError("Unrecognized hash method of type `$(typeof(method))` when " *
                        "hashing object $x. The implementation of `hash_method` for this " *
                        "object is invalid."))
    return nothing
end

#####
##### ================ Hash Algorithms ================
#####
"""
    update_hash!(state::HashState, bytes)

Returns the updated hash state given a set of bytes (either a tuple or array of UInt8
values).

    update_hash!(state::HashState, obj, context)

Returns the updated hash, given an object and some context. The object will
be written to some bytes using `StableHashTraits.write(io, obj, context)`.
"""
function update_hash! end

# when a hasher has no internal buffer, we allocate one for each call to `update_hash!`
function update_hash!(hasher, x, context)
    io = IOBuffer()
    write(io, x, context)
    return update_hash!(hasher, take!(io))
end

"""
    HashState(alg, context)

Given a function that implements the hash algorithm to use and the current hash context,
setup the necessary state to track updates to hashing as we traverse an object's structure
and return it.
"""
abstract type HashState end

"""
    compute_hash!(state::HashState)

Return the final hash value to return for `state`
"""
function compute_hash! end

"""
    start_nested_hash!(state::HashState)

Return an updated state that delimits hashing of a nested structure; calls made to
`update_hash!` after start_nested_hash! will be handled as nested elements up until
`end_nested_hash!` is called.
"""
function start_nested_hash! end

"""
    end_nested_hash!(state::HashState)

Return an updated state that delimints the end of a nested structure.
"""
function end_nested_hash! end

"""
    similar_hash_state(state::HashState)

Akin to `similar` for arrays, this constructs a new object of the same concrete type
as `state`
"""
function similar_hash_state end

#####
##### SHA Hashing: support use of `sha256` and related hash functions
#####

for fn in filter(startswith("sha") ∘ string, names(SHA))
    CTX = Symbol(uppercase(string(fn)), :_CTX)
    if CTX in names(SHA)
        # we cheat a little here, technically `SHA_CTX` and friends are not `HashState`
        # but we make them satisfy the same interface below
        @eval function HashState(::typeof(SHA.$(fn)), context)
            root_version(context) < 2 && return SHA.$(CTX)()
            return BufferedHashState(SHA.$(CTX)())
        end
    end
end

# NOTE: while BufferedHashState is a faster implementation of `start/end_nested_hash!`
# we still need a recursive hash implementation to implement `HashVersion{1}()`
start_nested_hash!(ctx::SHA.SHA_CTX) = typeof(ctx)()
function update_hash!(sha::SHA.SHA_CTX, bytes::AbstractVector{UInt8})
    SHA.update!(sha, bytes)
    return sha
end
function end_nested_hash!(hash_state::SHA.SHA_CTX, nested_hash_state)
    SHA.update!(hash_state, SHA.digest!(nested_hash_state))
    return hash_state
end
compute_hash!(sha::SHA.SHA_CTX) = SHA.digest!(sha)
HashState(x::SHA.SHA_CTX, ctx) = x
similar_hash_state(::T) where {T<:SHA.SHA_CTX} = T()

#####
##### RecursiveHashState: handles a function of the form hash(bytes, [old_hash])
#####

function HashState(fn::Function, context)
    root_version(context) < 2 && return RecursiveHashState(fn)
    return BufferedHashState(RecursiveHashState(fn))
end

struct RecursiveHashState{F,T} <: HashState
    fn::F
    val::T
    init::T
end
function RecursiveHashState(fn)
    hash = fn(UInt8[])
    return RecursiveHashState(fn, hash, hash)
end
start_nested_hash!(x::RecursiveHashState) = RecursiveHashState(x.fn, x.init, x.init)
function update_hash!(hasher::RecursiveHashState, bytes::AbstractVector{UInt8})
    return RecursiveHashState(hasher.fn, hasher.fn(bytes, hasher.val), hasher.init)
end
function end_nested_hash!(fn::RecursiveHashState, nested::RecursiveHashState)
    return update_hash!(fn, reinterpret(UInt8, [nested.val;]))
end
compute_hash!(x::RecursiveHashState) = x.val
HashState(x::RecursiveHashState) = x
similar_hash_state(x::RecursiveHashState) = RecursiveHashState(x.fn, x.init, x.init)

#####
##### BufferedHashState: wrapper that buffers bytes before passing them to the hash algorithm
#####

mutable struct BufferedHashState{T} <: HashState
    content_hash_state::T
    delimiter_hash_state::T
    total_bytes_hashed::Int
    bytes::Vector{UInt8} # the bytes that back `io`
    delimiters::Vector{Int} # delimits the start of nested structures (for `start_nested_hash!`), positive is start, negative is stop
    limit::Int # the preferred limit on the size of `io`'s buffer
    io::IOBuffer
end
const HASH_BUFFER_SIZE = 2^14
function BufferedHashState(state, size=HASH_BUFFER_SIZE)
    bytes = Vector{UInt8}(undef, size)
    delimiters = sizehint!(Vector{Int}(), 2size)
    io = IOBuffer(bytes; write=true, read=false)
    return BufferedHashState(state, similar_hash_state(state), 0, bytes, delimiters, size,
                             io)
end

# flush bytes that are stored internally to the underlying hasher
function flush_bytes!(x::BufferedHashState, limit=x.limit - (x.limit >> 2))
    # the default `limit` tries to flush before the allocated buffer increases in size
    if position(x.io) ≥ limit
        x.content_hash_state = update_hash!(x.content_hash_state,
                                            @view x.bytes[1:position(x.io)])
        # we copy reinterpreted because, e.g. `crc32c` will not accept a reinterpreted array
        # (and copying here does not noticeably worsen the benchmarks)
        x.delimiter_hash_state = update_hash!(x.delimiter_hash_state,
                                              copy(reinterpret(UInt8, x.delimiters)))

        empty!(x.delimiters)
        x.total_bytes_hashed += position(x.io) # tack total number of bytes that have been hashed
        seek(x.io, 0)
    end
    return x
end

function start_nested_hash!(x::BufferedHashState)
    push!(x.delimiters, position(x.io) + x.total_bytes_hashed + 1) # position can be zero
    return x
end

function end_nested_hash!(root::BufferedHashState, x::BufferedHashState)
    push!(x.delimiters, -(position(x.io) + x.total_bytes_hashed + 1))
    return x
end

function update_hash!(hasher::BufferedHashState, obj, context)
    write(hasher.io, obj, context)
    flush_bytes!(hasher)
    return hasher
end

function compute_hash!(x::BufferedHashState)
    flush_bytes!(x, 0)
    # recursively hash the delimiter hash state into the content hash
    delimiter_hash = compute_hash!(x.delimiter_hash_state)
    # we copy reinterpreted because, e.g. `crc32c` will not accept a reinterpreted array
    # (and copying here does not noticeably worsen the benchmarks)
    state = update_hash!(x.content_hash_state, copy(reinterpret(UInt8, [delimiter_hash;])))

    return compute_hash!(state)
end
HashState(x::BufferedHashState, ctx) = x
function similar_hash_state(x::BufferedHashState)
    return BufferedHashState(similar_hash_state(x.content_hash_state), x.limit)
end

#####
##### ================ Hash Traits ================
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

function stable_hash_helper(x, hash_state, context, ::WriteHash)
    return update_hash!(hash_state, x, context)
end

#####
##### IterateHash
#####

struct IterateHash end
function stable_hash_helper(xs, hash_state, context, ::IterateHash)
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
        inner_state = stable_hash_helper(f_x, inner_state, context, method)
        hash_state = end_nested_hash!(hash_state, inner_state)
    end
    return hash_state
end

function hash_foreach_new(fn, hash_state, context, xs)
    inner_state = start_nested_hash!(hash_state)
    for x in xs
        f_x, method = fn(x)
        inner_state = stable_hash_helper(f_x, inner_state, context, method)
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
@generated function sorted_field_names(T)
    return sort_(fieldnames(T))
end

function stable_hash_helper(x, hash_state, context, use::StructHash{<:Any,S}) where {S}
    fieldsfn, getfieldfn = use.fnpair
    if root_version(context) > 1 && fieldsfn isa typeof(fieldnames_)
        # NOTE: hashes the field names at compile time if possible (~x10 speed up)
        hash_state = stable_hash_helper(stable_typefields_id(x), hash_state, context,
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

include("cleanup_name.jl")

function validate_name(str)
    if occursin("#", str)
        throw(ArgumentError("Anonymous types (those containing `#`) cannot be hashed to a reliable value: found type $str"))
    end
    return str
end

qname_(T, name) = validate_name(cleanup_name(string(parentmodule(T), '.', name(T))))
qualified_name_(fn::Function) = qname_(fn, nameof)
qualified_type_(fn::Function) = qname_(fn, string)
qualified_name_(x::T) where {T} = qname_(T <: DataType ? x : T, nameof)
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
    Base.depwarn("`ConstantHash` has been deprecated, favor `@ConstantHash`.",
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

function stable_hash_helper(x, hash_state, context,
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

    return stable_hash_helper(y, hash_state, context, new_method)
end

#####
##### Tuples
#####

function stable_hash_helper(x, hash_state, context, methods::Tuple)
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
function stable_hash_helper(x, hash_state, context, method::HashAndContext)
    return stable_hash_helper(x, hash_state, method.contextfn(context), method.parent)
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

#####
##### TablesEq
#####

"""
    TablesEq(parent_context)

In this hash context the order of columns, and the type of the table do not impact the hash
that is created, only the set of columns (as determined by `Tables.columns`), and the hash
of the individual columns matter.
"""
struct TablesEq{T}
    parent::T
end
TablesEq() = TablesEq(HashVersion{1}())
parent_context(x::TablesEq) = x.parent
function hash_method(x::T, m::TablesEq) where {T}
    if Tables.istable(T)
        # NOTE: using root_version let's us ensure that `TableEq` is unchanged when using
        # `HashVersion{1}` as a parent or ancestor, but make use of the updated, more
        # optimized API for `HashVersion{2}`
        return (root_version(m) > 1 ? @ConstantHash("Tables.istable") :
                PrivateConstantHash("Tables.istable"),
                FnHash(Tables.columns, StructHash(Tables.columnnames => Tables.getcolumn)))
    end
    return hash_method(x, parent_context(m))
end

#####
##### ViewsEq
#####

"""
    ViewsEq(parent_context)

Create a hash context where only the contents of an array or string determine its hash: that
is, the type of the array or string (e.g. `SubString` vs. `String`) does not impact the hash
value.
"""
struct ViewsEq{T}
    parent::T
end
ViewsEq() = ViewsEq(HashVersion{1}())
parent_context(x::ViewsEq) = x.parent
# NOTE: using root_version let's us ensure that `ViewsEq` is unchanged when using
# `HashVersion{1}` as a parent or ancestor, but make use of the updated, more optimized API
# for `HashVersion{2}`
function hash_method(::AbstractArray, c::ViewsEq)
    return (root_version(c) > 1 ? @ConstantHash("Base.AbstractArray") :
            PrivateConstantHash("Base.AbstractArray"), FnHash(size), IterateHash())
end
function hash_method(::AbstractString, c::ViewsEq)
    return (root_version(c) > 1 ? @ConstantHash("Base.AbstractString") :
            PrivateConstantHash("Base.AbstractString", WriteHash()), WriteHash())
end

end
