module StableHashTraits

export stable_hash, WriteHash, IterateHash, StructHash, FnHash, ConstantHash,
       HashAndContext, HashVersion, qualified_name, qualified_type, 
       stable_type_id, stable_typename_id, TablesEq, ViewsEq, fnv, fnv32, fnv64, fnv128
using TupleTools, Tables, Compat
using SHA: SHA, sha256

"""
    HashVersion{V}()

The default `hash_context` used by `stable_hash`. There are currently two versions
(1 and 2). Version 2 is far more optimized than 1 and should generally be used in newly 
written code. Version 1 is the default version, so as to changing the hash computed
by existing code.

By explicitly passing this hash version in `stable_hash` you ensure that hash values for 
these fallback methods will not change even if new fallbacks are defined. 
"""
struct HashVersion{V}
    function HashVersion{V}() where V
        V == 1 && 
            Base.depwarn("HashVersion{1} is deprecated, favor `HashVersion{2}` in "*
                         "all cases where backwards compatible hash values are not "*
                         "required.", :HashVersion)
        return new{V}()
    end
end

"""
    stable_hash(x, context=HashVersion{1}(); alg=sha256)

Create a stable hash of the given objects. As long as the context remains the same, this is
intended to remain unchanged across julia verisons. How each object is hashed is determined
by [`hash_method`](@ref), which aims to have sensible fallbacks.

To ensure the greattest stability, you should explicitly pass the context object. It is also
best to pass an explicit version, since `HashVersion{2}` is generally faster than
`HashVerison{1}`. If the fallback methods change in a future release, the hash you get
by passing an explicit `HashVersin{N}` should *not* change. (Note that the number in
`HashVersion` may not necessarily match the package verison of `StableHashTraits`).

To change the hash algorithm used, pass a different function to `alg`. It accepts any `sha`
related function from `SHA` or any function of the form 
`hash(x::Union{NTuple{<:Any, UInt8}, AbstractArray{UInt8}, [old_hash])`.

The `context` value gets passed as the second argument to [`hash_method`](@ref), and as the
third argument to [`StableHashTraits.write`](@ref)

"""
function stable_hash(x, context=HashVersion{1}(); alg=sha256)
    return compute_hash!(stable_hash_helper(x, setup_hash_state(alg, context), context,
                                            hash_method(x, context)))
end

# extract contents of README so we can insert it into the some of the docstrings
const HASH_TRAITS_DOCS, HASH_CONTEXT_DOCS = let
    readme = read(joinpath(pkgdir(StableHashTraits), "README.md"), String)
    traits = match(r"START_HASH_TRAITS -->(.*)<!-- END_HASH_TRAITS"s, readme).captures[1]
    contexts = match(r"START_CONTEXTS -->(.*)<!-- END_CONTEXTS"s, readme).captures[1]
    # TODO: if we ever generate `Documenter.jl` docs we need to revise the
    # links to symbols here

    traits, contexts
end

"""
    hash_method(x, [context])

Retrieve the trait object that indicates how a type should be hashed using `stable_hash`.
You should return one of the following values.

$HASH_TRAITS_DOCS

$HASH_CONTEXT_DOCS
"""
function hash_method end

# recurse up to the parent until a method is defined or we hit the root (with parent `nothing`)
hash_method(x, context) = hash_method(x, parent_context(context))
# if we hit the root context, we call the one-argument form, which could be extended by a
# user
hash_method(x, ::Nothing) = hash_method(x)
# we signal that a method specific to a type is not available using `NotImplemented`; we
# need this to avoid method ambiguities, see `hash_method(x::T, ::HashContext{1}) where T`
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
    throw(ArgumentError("Unreconized hash method of type `$(typeof(method))` when " *
                        "hashing object $x. The implementation of `hash_method` for this " *
                        "object is invalid."))
    return nothing
end

#####
##### ================ Hash Algorithms ================
#####
"""
    update_hash!(state, bytes)

Returns the updated hash state given a set of bytes (either a tuple or array of UInt8
values).
"""
function update_hash! end

"""
    setup_hash_state(alg)

Given a function that specifies the hash algorithm to use, setup the necessary
state to track updates to hashing as we traverse an object's structure and return it.
"""
function setup_hash_state! end

"""
    compute_hash!(state)

Return the final hash value to return for `state`
"""
function compute_hash! end

"""
    start_hash!(state)

Return an updated state that delimits hashing of a nested struture; calls made to
`update_hash!` after start_hash! will be handled as nested elements up until `stop_hash!` is
called.
"""
function start_hash! end

"""
    stop_hash!(state)

Return an updated state that delimints the end of a nested structure.
"""
function stop_hash! end

"""
    hash_type(state)

The return type of `compute_hash!`
"""
function hash_type end

#####
##### BufferedHash: wrapper that buffers bytes before passing them to the hash algorithm 
#####

# NOTE: buffered hash never needs to implement `start/stop_hash!` since that
# is handled by `MarkerHash`

mutable struct BufferedHash{T}
    hash::T
    bytes::Vector{UInt8}
    io::IOBuffer
end
const HASH_BUFFER_SIZE = 2^12
function BufferedHash(hash, size=HASH_BUFFER_SIZE)
    bytes = Vector{UInt8}(undef, size)
    io = IOBuffer(bytes; write=true, read=false, maxsize=size)
    BufferedHash(hash, bytes, io)
end
view_(x::AbstractArray, ix) = @view x[ix]
view_(x::Tuple, ix) = x[ix]
write_(io::IO, x::AbstractArray, ixs) = write(io, view(x, ixs))
function write_(io::IO, bytes::Tuple, ixs) 
    total = 0
    @inbounds for i in ixs
        total += write(io, bytes[i])
    end
    return total
end

function update_hash!(x::BufferedHash, 
                      bytes::Union{NTuple{<:Any, UInt8}, AbstractArray{UInt8}})
    written = write_(x.io, bytes, 1:lastindex(bytes))
    if position(x.io) > length(x.bytes)
        x.hash = update_hash!(x.hash, x.bytes)
        seek(x.io, 0)
    end
    if length(bytes) - written > length(x.bytes)
        x.hash = update_hash!(x.hash, view_(bytes, (written+1):lastindex(bytes)))
    elseif length(bytes) > written
        write_(x.io, bytes, (written+1):lastindex(bytes))
    end
    
    return x
end

function compute_hash!(x::BufferedHash)
    hash = if position(x.io) > 0
        update_hash!(x.hash, @view x.bytes[1:position(x.io)])
    else
        x.hash
    end
    return compute_hash!(hash)
end

hash_type(x::BufferedHash) = hash_type(x.hash)

#####
##### SHA Hashing: support use of `sha256` and related hash functions
#####

for fn in filter(startswith("sha") ∘ string, names(SHA))
    CTX = Symbol(uppercase(string(fn)), :_CTX)
    if CTX in names(SHA)
        @eval function setup_hash_state(::typeof(SHA.$(fn)), context)
            # NOTE: BufferedHash speeds things up by about 1.8x
            # NOTE: MarkerHash speeds things up by about 4.5x
            root_version(context) < 2 && return SHA.$(CTX)()
            return MarkerHash(BufferedHash(SHA.$(CTX)()))
        end
    end
end

# NOTE: while MarkerHash is a faster implementation of `start/stop_hash!`
# we still need a recursive hash implementation to implement `HashVersion{1}()`
start_hash!(ctx::SHA.SHA_CTX) = typeof(ctx)()
update_hash!(sha::SHA.SHA_CTX, bytes) = (SHA.update!(sha, bytes); sha)
function stop_hash!(hash_state, nested_hash_state)
    return update_hash!(hash_state, SHA.digest!(nested_hash_state))
end
compute_hash!(sha::SHA.SHA_CTX) = SHA.digest!(sha)
hash_type(::SHA.SHA_CTX) = Vector{UInt8}

#####
##### MarkerHash: wrapper that uses delimiters to handle `start/stop_hash!` 
#####

struct MarkerHash{T}
    hash::T
end
function start_hash!(x::MarkerHash)
    return MarkerHash(update_hash!(x.hash, (0x01,)))
end
update_hash!(x::MarkerHash, bytes) = MarkerHash(update_hash!(x.hash, bytes))
function stop_hash!(::MarkerHash, nested::MarkerHash) 
    return MarkerHash(update_hash!(nested.hash, (0x02,)))
end
compute_hash!(x::MarkerHash) = compute_hash!(x.hash)
hash_type(x::MarkerHash) = hash_type(x.hash)

#####
##### RecursiveHash: handles a function of the form hash(bytes, [old_hash]) 
#####

setup_hash_state(fn::Function, ::Any) = RecursiveHash(fn)
struct RecursiveHash{F,T}
   fn::F 
   val::T
   init::T
end
function RecursiveHash(fn)
    hash = fn(UInt8[])
    return RecursiveHash(fn, hash, hash)
end
start_hash!(x::RecursiveHash) = RecursiveHash(x.fn, x.init, x.init)
update_hash!(x::RecursiveHash, bytes) = RecursiveHash(x.fn, x.fn(bytes, x.val), x.init)
function stop_hash!(fn::RecursiveHash, nested::RecursiveHash)
    return update_hash!(fn, bytesof(nested.val))
end
compute_hash!(x::RecursiveHash) = x.val
hash_type(::RecursiveHash{<:Any, T}) where {T} = T

#####
##### Hash function fnv: https://en.wikipedia.org/wiki/Fowler%E2%80%93Noll%E2%80%93Vo_hash_function
#####

const FNV_PRIME_32=0x01000193
const FNV_BASIS_32=0x811c9dc5
const FNV_PRIME_64=0x00000100000001B3
const FNV_BASIS_64=0xcbf29ce484222325
const FNV_PRIME_128=0x0000000001000000000000000000013B
const FNV_BASIS_128=0x6c62272e07bb014262b821756295c58d
function fnvdoc(len, namelen=len)
    return """
        fnv$(namelen)(bytes, seed::UInt$len)::UInt$(len)

    Compute Fowler-Noll-Vo hash function (variant 1a) of size $len bytes.
    See https://en.wikipedia.org/wiki/Fowler%E2%80%93Noll%E2%80%93Vo_hash_function for details.
    """
end
for len in [32, 64, 128]
    str = fnvdoc(len)
    @eval @doc $str function $(Symbol(:fnv, len))(bytes, hash::$(Symbol(:UInt,len))=$(Symbol(:FNV_BASIS_,len)))
        @inbounds for b in bytes
            hash *= $(Symbol(:FNV_PRIME_,len))
            hash ⊻= b
        end
        return hash
    end
end
@eval @doc fnvdoc(Sys.WORD_SIZE, "") const fnv = $(Symbol(:fnv, Sys.WORD_SIZE))

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
# TODO: we could reduce memory usage for all types if we had the hash
# state implement `IO`, but this would take some work
# see:
# https://discourse.julialang.org/t/making-a-simple-wrapper-for-an-io-stream/52587/9
function stable_hash_helper(x, hash_state, context, ::WriteHash)
    io = IOBuffer()
    write(io, x, context)
    return update_hash!(hash_state, take!(io))
end

# convert a primitive type to a tuple of its bytes
@generated function bytesof(x::Number)
    nbytes = sizeof(x)
    UIntX = Symbol(:UInt, nbytes << 3)
    bytes = gensym("bytes")
    tuple_args = map(1:nbytes) do i
        :(unsafe_trunc(UInt8, ($bytes >> $((i-1) << 3)) & 0xff))
    end
    tuple_result = Expr(:tuple, tuple_args...)
    return quote
        $bytes = reinterpret($UIntX, x)
        return $tuple_result
    end
end

# NOTE: this specialized method speeds up hashing by ~x45 when using 
# a simple hashing function like crc
function stable_hash_helper(x::Number, hash_state, context, ::WriteHash)
    # NOTE: `bytesof` increases speed by ~3x over reinterpret(UInt8, [x])
    return update_hash!(hash_state, bytesof(x))
end

function stable_hash_helper(x::AbstractString, hash_state, context, ::WriteHash)
    return update_hash!(hash_state, codeunits(x))
end

#####
##### IterateHash 
#####

struct IterateHash end
function stable_hash_helper(x, hash_state, context, ::IterateHash)
    return hash_foreach(identity, hash_state, context, x)
end

function hash_foreach(fn, hash_state, context, xs)
    for x in xs
        f_x = fn(x)
        inner_state = start_hash!(hash_state)
        inner_state = stable_hash_helper(f_x, inner_state, context,
                           hash_method(f_x, context))
        hash_state = stop_hash!(hash_state, inner_state)
    end
    return hash_state
end

#####
##### StructHash 
#####

struct StructHash{P,S}
    fnpair::P
end
fieldnames_(::T) where T = fieldnames(T)
function StructHash(sort::Symbol)
    return StructHash(fieldnames_ => getfield, sort)
end
function StructHash(fnpair::Pair=fieldnames_ => getfield, by::Symbol=:ByOrder)
    by ∈ (:ByName, :ByOrder) || error("Expected a valid sort order (:ByName or :ByOrder).")
    return StructHash{typeof(fnpair),by}(fnpair)
end
orderfields(::StructHash{<:Any,:ByOrder}, props) = props
orderfields(::StructHash{<:Any,:ByName}, props) = sort_(props)
sort_(x::Tuple) = TupleTools.sort(x; by=string)
sort_(x::AbstractSet) = sort!(collect(x); by=string)
sort_(x) = sort(x; by=string)
function stable_hash_helper(x, hash_state, context, use::StructHash)
    fieldsfn, getfieldfn = use.fnpair
    if root_version(context) > 1 && fieldsfn isa typeof(fieldnames_)
        # NOTE: hashes the field names at compile time if possible (~x10 speed up)
        hash_state = update_hash!(hash_state, bytesof(stable_typefields_id(x)))
        hash_state = hash_foreach(hash_state, context, orderfields(use, fieldsfn(x))) do k
            getfieldfn(x, k)
        end
    else
        return hash_foreach(hash_state, context, orderfields(use, fieldsfn(x))) do k
            return k => getfieldfn(x, k)
        end
    end
end

#####
##### Stable values for types
#####

qname_(T, name) = validate_name(cleanup_name(string(parentmodule(T), '.', name(T))))
qualified_name_(fn::Function) = qname_(fn, nameof)
qualified_type_(fn::Function) = qname_(fn, string)
qualified_name_(x::T) where {T} = qname_(T <: DataType ? x : T, nameof)
qualified_type_(x::T) where {T} = qname_(T <: DataType ? x : T, string)
function qualified_name(x)
    Base.depwarn("`qualified_name` is deprecated, favor `stable_typename_id` in all cases "*
                 "where backwards compatible hash values are not required.", 
                 :qualified_name)
    return qualified_name_(x)
end
function qualified_type(x)
    Base.depwarn("`qualified_type` is deprecated, favor `stable_type_id` in all cases "*
                 "where backwards compatible hash values are not required.", 
                 :qualified_type)
    return qualified_type_(x)
end

function hash_type_str(str, T)
    bytes = sha256(codeunits(str))
    return first(reinterpret(UInt128, bytes))
end

function hash_field_str(T)
    sha = SHA.SHA2_256_CTX()
    for f in sort_(fieldnames(T))
        if f isa Symbol
            SHA.update!(sha, codeunits(String(f)))
        else # isa Number
            SHA.update!(sha, reinterpret(UInt8, [f]))
        end
    end
    bytes = SHA.digest!(sha)

    return first(reinterpret(UInt128, bytes))
end

# NOTE: using stable_{typename|type}_id increases speed by ~x10-20 vs. `qualified_name`

"""
    stable_typename_id(x)

Returns a 128bit hash that is the same for a given type so long as the name and the module
of the type doesn't change. E.g. `stable_typename_id(Vector) == stable_typename_id(Matrix)`

NOTE: if the module of a type is `Core` it is renamed to `Base` before hashing because the
location of some types changes between `Core` to `Base` across julia versions
"""
stable_typename_id(x) = stable_id_helper(x, Val(:name))
stable_id_helper(::Type{T}, ::Val{:name}) where {T} = hash_type_str(qualified_name_(T), T)
stable_id_helper(::Type{T}, ::Val{:type}) where {T} = hash_type_str(qualified_type_(T), T)
@generated function stable_id_helper(x, name)
    T = x <: Function ? x.instance : x
    str = name <: Val{:name} ? qualified_name_(T) : qualified_type_(T)
    number = hash_type_str(str, T)
    :(return $number)
end

"""
    stable_type_id(x)`

Returns a 128bit hash that is the same for a given type so long as the module, and string
representation of a type is the same (invariant to comma spacing).

NOTE: if the module of a type is `Core` it is renamed to `Base` before hashing because the
location of some types changes between `Core` to `Base` across julia versions
"""
stable_type_id(x) = stable_id_helper(x, Val(:type))

"""
    stable_typefields_id(x)

Returns a 128bit hash that is the same for a given type so long as the set of field names
remains unchanged.
"""
stable_typefields_id(::Type{T}) where {T} = hash_field_str(T)
@generated function stable_typefields_id(x)
    number = hash_field_str(x)
    :(return $number)
end

function cleanup_name(str)
    # We treat all uses of the `Core` namespace as `Base` across julia versions. What is in
    # `Core` changes, e.g. Base.Pair in 1.6, becomes Core.Pair in 1.9; also see
    # https://discourse.julialang.org/t/difference-between-base-and-core/37426
    str = replace(str, r"^Core\." => "Base.")
    str = replace(str, ", " => ",") # spacing in type names vary across minor julia versions
    return str
end
function validate_name(str)
    if occursin(r"\.#[^.]*$", str)
        throw(ArgumentError("Annonymous types (those containing `#`) cannot be hashed to a reliable value"))
    end
    return str
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

struct ConstantHash{T,H}
    constant::T
    result_method::H # if non-nothing, apply to value `constant`
end
ConstantHash(val) = ConstantHash{typeof(val),Nothing}(val, nothing)
get_value_(x, method::ConstantHash) = method.constant

function stable_hash_helper(x, hash_state, context, method::Union{FnHash,ConstantHash})
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
    for method in methods
        result = stable_hash_helper(x, start_hash!(hash_state), context, method)
        hash_state = stop_hash!(hash_state, result)
    end

    return hash_state
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

Note that we could accomplish this same behavior using `HashFn(x -> htol.(x.data))`, but it
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
`HashVersion`)—then there may be a bit more work invovled. In this case, `parent_context`
should return `nothing` so that the single argument fallback for `hash_method` can be
called. You will also need to define [`StableHashTraits.root_version`](@ref).

Furthermore, if you implement a root context and want to implement `hash_method` over `Any`
you will instead have to manually manage the fallback mechanism as follows:

```julia
# generic fallback method
function hash_method(x::T, ::MyRootContext) where T
    default_method = hash_method(x)
    StableHashTraits.is_implemented(default_method) && return default_method

    # return generic fallback hash trait here
end
```

This works because `hash_method(::Any)` returns a sentinal value
(`StableHashTraits.NotImplemented()`) that indicates that there is no more specific method
available. This pattern is necessary to avoid the method ambiguities that would arise
between `hash_method(x::MyType, ::Any)` and `hash_method(x::Any, ::MyRootContext)`.
Generally if a type implements hash_method for itself, but absent a context, we want this
`hash_method` to be used.
"""
function parent_context(x::Any)
    Base.depwarn("You should explicitly define a `parent_context` method for context " *
                 "`$x`. See details in the docstring of `hash_method`.", :parent_context)
    return HashVersion{1}()
end

"""
    StableHashTraits.root_version(context)

Return the verison of the root context: an integer in the range (1, 2). The default
fallback method value returns 1. 

In almost all causes, a root hash context should return 2. With the implementation of
HashVersion{2} there are a number of changes to the hash-trait implementations that do not
alter the documented behavior but do change the actual hash value returned because of how
and when elements get hashed. 

"""
root_version(x) = 1

#####
##### HashVersion{V} (root contexts)
#####

parent_context(::HashVersion) = nothing
root_version(::HashVersion{V}) where V = V

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
    return (FnHash(typefn_for(c)), StructHash(:ByName))
end
typenamefn_for(::HashVersion{1}) = qualified_name_
typenamefn_for(::HashVersion{2}) = stable_typename_id
typefn_for(::HashVersion{1}) = qualified_type_
typefn_for(::HashVersion{2}) = stable_type_id

hash_method(::NamedTuple, c::HashVersion) = (FnHash(typenamefn_for(c)), StructHash())
function hash_method(::AbstractRange, c::HashVersion)
    return (FnHash(typenamefn_for(c)), StructHash(:ByName))
end
function hash_method(::AbstractArray, c::HashVersion)
    return (FnHash(typenamefn_for(c)), FnHash(size), IterateHash())
end
function hash_method(::AbstractString, c::HashVersion)
    return (FnHash(typenamefn_for(c), WriteHash()), WriteHash())
end
hash_method(::Symbol, ::HashVersion) = (ConstantHash(":"), WriteHash())
function hash_method(::AbstractDict, c::HashVersion)
    return (FnHash(typenamefn_for(c)), StructHash(keys => getindex, :ByName))
end
hash_method(::Tuple, c::HashVersion) = (FnHash(typenamefn_for(c)), IterateHash())
hash_method(::Pair, c::HashVersion) = (FnHash(typenamefn_for(c)), IterateHash())
function hash_method(::Type, c::HashVersion)
    return (ConstantHash("Base.DataType"), FnHash(typefn_for(c)))
end
function hash_method(::Function, c::HashVersion)
    return (ConstantHash("Base.Function"), FnHash(typenamefn_for(c)))
end
function hash_method(::AbstractSet, c::HashVersion)
    return (FnHash(typenamefn_for(c)), FnHash(sort! ∘ collect))
end

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
StableHashTraits.parent_context(x::TablesEq) = x.parent
function StableHashTraits.hash_method(x::T, m::TablesEq) where {T}
    if Tables.istable(T)
        return (ConstantHash("Tables.istable"),
                FnHash(Tables.columns, StructHash(Tables.columnnames => Tables.getcolumn)))
    end
    return StableHashTraits.hash_method(x, parent_context(m))
end

#####
##### ViewsEq 
#####

"""
    ViewsEq(parent_context)

Create a hash context where only the contents of an array or string determine its hash: that is,
the type of the array or string (e.g. `SubString` vs. `String`) does not impact the hash
value.
"""
struct ViewsEq{T}
    parent::T
end
ViewsEq() = ViewsEq(HashVersion{1}())
StableHashTraits.parent_context(x::ViewsEq) = x.parent
function StableHashTraits.hash_method(::AbstractArray, ::ViewsEq)
    return (ConstantHash("Base.AbstractArray"), FnHash(size), IterateHash())
end
function StableHashTraits.hash_method(::AbstractString, ::ViewsEq)
    return (ConstantHash("Base.AbstractString", WriteHash()), WriteHash())
end

end
