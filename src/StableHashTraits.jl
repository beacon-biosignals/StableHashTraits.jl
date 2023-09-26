module StableHashTraits

export stable_hash, WriteHash, IterateHash, StructHash, FnHash, ConstantHash, @ConstantHash,
       HashAndContext, HashVersion, qualified_name, qualified_type, TablesEq, ViewsEq,
       stable_typename_id, stable_type_id, stable_eltype_id
using TupleTools, Tables, Compat
using SHA: SHA, sha256

"""
    HashVersion{V}()

The default `hash_context` used by `stable_hash`. There are currently three versions
(1-3). Unless you are aiming for backwards compatibility with an existing code base
it is recommended that you use the latest version, as it is fast and avoids
more hash collisions.

By explicitly passing this hash version in `stable_hash` you ensure that hash values for 
these fallback methods will not change even if new fallbacks are defined. 
"""
struct HashVersion{V}
    function HashVersion{V}() where {V}
        V < 3 && Base.depwarn("HashVersion{V} with V < 2 is deprecated, favor `HashVersion{3}` in " *
                               "all cases where backwards compatible hash values are not " *
                               "required.", :HashVersion)
        return new{V}()
    end
end

"""
    stable_hash(x, context=HashVersion{1}(); alg=sha256)

Create a stable hash of the given objects. As long as the context remains the same, this is
intended to remain unchanged across julia versions. How each object is hashed is determined
by [`hash_method`](@ref), which aims to have sensible fallbacks.

To ensure the greatest stability, you should explicitly pass the context object. It is also
best to pass an explicit version, since `HashVersion{3}` is generally faster and has fewer
hash collisions, it is the recommended version. If the fallback methods change in a future
release, the hash you get by passing an explicit `HashVersion{N}` should *not* change. (Note
that the number in `HashVersion` does not necessarily match the package version of
`StableHashTraits`).

To change the hash algorithm used, pass a different function to `alg`. It accepts any `sha`
related function from `SHA` or any function of the form `hash(x::AbstractArray{UInt8},
[old_hash])`. 

The `context` value gets passed as the second argument to [`hash_method`](@ref), and as the
third argument to [`StableHashTraits.write`](@ref)

"""
function stable_hash(x, context=HashVersion{1}(); alg=sha256)
    return compute_hash!(stable_hash_helper(x, setup_hash_state(alg, context), context,
                                            Val(root_version(context)), 
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

function stable_hash_helper(x, hash_state, context, root, method::NotImplemented)
    throw(ArgumentError("There is no appropriate `hash_method` defined for objects" *
                        " of type `$(typeof(x))` in context of type `$(typeof(context))`."))
    return nothing
end

function stable_hash_helper(x, hash_state, context, root, method)
    throw(ArgumentError("Unrecognized hash method of type `$(typeof(method))` when " *
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

    update_hash!(state, obj, context)

Returns the update hash, given an object and some context. The object will
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
    setup_hash_state(alg, context)

Given a function that specifies the hash algorithm to use and the current hash context,
setup the necessary state to track updates to hashing as we traverse an object's structure
and return it.
"""
function setup_hash_state end

"""
    compute_hash!(state)

Return the final hash value to return for `state`
"""
function compute_hash! end

"""
    start_hash!(state)

Return an updated state that delimits hashing of a nested structure; calls made to
`update_hash!` after start_hash! will be handled as nested elements up until `stop_hash!` is
called.
"""
function start_hash! end

"""
    stop_hash!(state)

Return an updated state that delimints the end of a nested structure.
"""
function stop_hash! end

#####
##### SHA Hashing: support use of `sha256` and related hash functions
#####

for fn in filter(startswith("sha") ∘ string, names(SHA))
    CTX = Symbol(uppercase(string(fn)), :_CTX)
    if CTX in names(SHA)
        @eval function setup_hash_state(::typeof(SHA.$(fn)), context)
            root_version(context) < 2 && return SHA.$(CTX)()
            return BufferedHasher(SHA.$(CTX)())
        end
    end
end

# NOTE: while BufferedHasher is a faster implementation of `start/stop_hash!`
# we still need a recursive hash implementation to implement `HashVersion{1}()`
start_hash!(ctx::SHA.SHA_CTX) = typeof(ctx)()
function update_hash!(sha::SHA.SHA_CTX, bytes::AbstractVector{UInt8}) 
    SHA.update!(sha, bytes)
    return sha
end
function stop_hash!(hash_state::SHA.SHA_CTX, nested_hash_state)
    SHA.update!(hash_state, SHA.digest!(nested_hash_state))
    return hash_state
end
compute_hash!(sha::SHA.SHA_CTX) = SHA.digest!(sha)

#####
##### RecursiveHasher: handles a function of the form hash(bytes, [old_hash]) 
#####

function setup_hash_state(fn::Function, context)
    root_version(context) < 2 && return RecursiveHasher(fn)
    return BufferedHasher(RecursiveHasher(fn))
end

struct RecursiveHasher{F,T}
    fn::F
    val::T
    init::T
end
function RecursiveHasher(fn)
    hash = fn(UInt8[])
    return RecursiveHasher(fn, hash, hash)
end
start_hash!(x::RecursiveHasher) = RecursiveHasher(x.fn, x.init, x.init)
function update_hash!(hasher::RecursiveHasher, bytes::AbstractVector{UInt8})
    return RecursiveHasher(hasher.fn, hasher.fn(bytes, hasher.val), hasher.init)
end
function stop_hash!(fn::RecursiveHasher, nested::RecursiveHasher)
    return update_hash!(fn, reinterpret(UInt8, [nested.val]))
end
compute_hash!(x::RecursiveHasher) = x.val

#####
##### BufferedHasher: wrapper that buffers bytes before passing them to the hash algorithm 
#####

mutable struct BufferedHasher{T}
    hasher::T
    bytes::Vector{UInt8} # tye bytes that back `io`
    starts::Vector{Int} # delimits the start of nested structures (for `start_hash!`)
    stops::Vector{Int} # delimits the end of nested structures (for `stop_hash!`)
    limit::Int # the preferred limit on the size of `io`'s buffer
    io::IOBuffer
end
const HASH_BUFFER_SIZE = 2^14
function BufferedHasher(hasher, size=HASH_BUFFER_SIZE)
    bytes = Vector{UInt8}(undef, size)
    starts = sizehint!(Vector{Int}(), size)
    stops = sizehint!(Vector{Int}(), size)
    io = IOBuffer(bytes; write=true, read=false)
    return BufferedHasher(hasher, bytes, starts, stops, size, io)
end

# flush bytes that are stored internally to the underlying hasher
function flush_bytes!(x::BufferedHasher, limit=x.limit - (x.limit >> 2))
    # the default `limit` tries to flush before the allocated buffer increases in size
    if position(x.io) ≥ limit
        content_size = position(x.io)

        # NOTE: we now write a block of meta-data that represents the start/stop delimeters
        # for nested elements. We mark the number of bytes of user-hashed content it covers,
        # and the number of delimeters represented, so that there is no way to have content
        # replicate the exact metadata block used to represent a given byte sequence
        # (including any such block would change the nubmer of bytes the metadata block
        # indexes). We can verify that this is the cases by imagining that we're scanning
        # the bytes from end to start; given the information in the metadata block (and
        # given that we know the last thing written is metadata) we can easily scan in this
        # direction to correctly distinguish all metadata from all user-hashed content

        # write out the delimeters
        Base.write(x.io, x.starts)
        Base.write(x.io, x.stops)
        empty!(x.starts)
        empty!(x.stops)

        # write out user and metadata content size
        @assert x.starts == x.stops
        Base.write(x.io, length(x.starts))
        Base.write(x.io, content_size)

        # hash both user data and the data block above
        x.hasher = update_hash!(x.hasher, @view x.bytes[1:position(x.io)])

        seek(x.io, 0)
    end
    return x
end

function start_hash!(x::BufferedHasher)
    push!(x.starts, position(x.io))
    return x
end

function stop_hash!(root::BufferedHasher, x::BufferedHasher)
    push!(x.stops, position(x.io))
    return x
end

function update_hash!(hasher::BufferedHasher, obj, context)
    write(hasher.io, obj, context)
    flush_bytes!(hasher)
    return hasher
end

function compute_hash!(x::BufferedHasher)
    return compute_hash!(flush_bytes!(x, 0).hasher)
end

#####
##### CachedHash: cache hashed values where appropriate 
#####

struct CachedHash{H}
    buffered::BufferedHash
    cache::Dict{Tuple{UInt,Uint},H}
    seen::IdSet
    caching::Bool
end
CachedHash(buffered, caching) = CachedHash(buffered, IdDict{Union{hash_type(buffered), Nothing}}(), 0, caching)

# sketch of how to handle caching
# we might also want to have some cumulative count for an object
# e.g. if we hash 1MB or mor of the same object (e.g. hashing the 
# same object twice for 0.5MB)
# acutally I like that, so we should just count the contents of an
# object (with sizeof being a lower bound)

# TODO: also, how do manage the context (it could change)
const CACHCE_CAP = HASH_BUFFER_SIZE - (HASH_BUFFER_SIZE >> 2)
function hash_within(body, x::T, hash::CachedHash, context) where T
    isprimitivetype(T) && return body(hash)
    if hash.caching
        if !isnothing(get(hash.cache, x, nothing)) 
            return update_hash!(hash, hash.cache[x])
        end

        # cache object id's that are above a size limit or
        # that have been marked as being above the size limit, post-hoc
        if sizeof(x) > CACHE_CAP || get(hash.object_cost, x, 0) > CACHE_CAP
            new_buffered = BufferedHash(hash.buffered.hash)
            result = body(CachedHash(new_buffered, false))
            hash.cache[x] = compute_hash!(result)
            return update_hash!(hash, hash.cache[x])
        end
    end

    bytebefore = hash.bytecount
    result = body(hash)


    return result
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

function stable_hash_helper(x, hash_state, context, root, ::WriteHash)
    update_hash!(hash_state, x, context)
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
    if constant isa Symbol || constant isa String
        return PrivateConstantHash(first(reinterpret(UInt64,
                                                     sha256(codeunits(String(constant))))),
                                   WriteHash())
    elseif constant isa Number
        return PrivateConstantHash(first(reinterpret(UInt64,
                                                     sha256(reinterpret(UInt8, [constant])))),
                                   WriteHash())
    else
        error("Unexpected expression: `$constant`")
    end
end

function stable_hash_helper(x, hash_state, context, root,
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

    return stable_hash_helper(y, hash_state, context, root, new_method)
end

#####
##### Type Elision 
#####

# Type elision strips a hash method of type-based identifiers of an object

struct ElideType{P}
    parent::P
end
parent_context(x::ElideType) = x.parent
ignore_elision(x) = x
ignore_elision(x::ElideType) = parent_context(x)

struct ElidedTypeHash end

elide_type(trait) = trait
elide_type(trait::Tuple{}) = ()
function elide_type(trait::Tuple)
    head, rest... = trait
    return elide_head_type(head, rest)
end

function stable_type_id end
elide_head_type(x::FnHash{<:typeof(stable_type_id)}, rest) = ElidedTypeHash(), rest...
elide_head_type(x, rest) = (x, elide_type(rest)...)

#####
##### IterateHash 
#####

eltype_(xs) = eltype_(xs, Base.IteratorEltype(xs))
eltype_(_, _) = Any
eltype_(x, ::Base.HasEltype) = eltype(x)

struct IterateHash end
function stable_hash_helper(xs, hash_state, context, root, ::IterateHash)
    if !(root isa Union{Val{1}, Val{2}}) &&
       context isa ElideType && 
       (isdispatchtuple(typeof(xs)) || isdispatchtuple(Tuple{eltype_(xs)}))
       
        return hash_foreach(hash_state, root, xs) do x
            x, elide_type(hash_method(x, context)), ignore_elision(context)
        end
    else
        return hash_foreach(hash_state, root, xs) do x
            return x, hash_method(x, context), context
        end
    end
end

function hash_foreach(fn, hash_state, root::Val{1}, xs)
    for x in xs
        f_x, method, context = fn(x)
        inner_state = start_hash!(hash_state)
        inner_state = stable_hash_helper(f_x, inner_state, context, root, method)
        hash_state = stop_hash!(hash_state, inner_state)
    end
    return hash_state
end

function hash_foreach(fn, hash_state, root, xs)
    inner_state = start_hash!(hash_state)
    for x in xs
        f_x, method, context = fn(x)
        inner_state = stable_hash_helper(f_x, inner_state, context, root, method)
    end
    hash_state = stop_hash!(hash_state, inner_state)
    return hash_state
end

#####
##### StructHash 
#####

struct StructHash{P,S}
    fnpair::P
end
fieldnames_(::T) where {T} = fieldnames(T)
function StructHash(sort::Symbol)
    return StructHash(fieldnames_ => getfield, sort)
end
const FieldStructHash = StructHash{<:Pair{<:typeof(fieldnames_),<:Any}}
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

function stable_hash_helper(x::T, hash_state, context, root,
                            use::StructHash{<:Any,S}) where {T,S}
    fieldsfn, getfieldfn = use.fnpair
    if !(root isa Val{1}) && fieldsfn isa typeof(fieldnames_)
        # NOTE: hashes the field names at compile time if possible (~x10 speed up)
        hash_state = stable_hash_helper(stable_typefields_id(x), hash_state, context,
                                        root, WriteHash())
        # NOTE: sort fields at compile time if possible (~x1.33 speed up)
        fields = S == :ByName ? sorted_field_names(x) : fieldnames_(x)
        if !(root isa Val{2}) && getfieldfn isa typeof(getfield)
            return hash_foreach(hash_state, root, fields) do k
                val = getfield(x, k)
                if isdispatchtuple(Tuple{fieldtype(T, k)})
                    return val, elide_type(hash_method(val, context)),
                           ignore_elision(context)
                else
                    return val, hash_method(val, context), ignore_elision(context)
                end
            end
        else
            return hash_foreach(hash_state, root, fields) do k
                val = getfieldfn(x, k)
                return val, hash_method(val, context), context
            end
        end
    else
        return hash_foreach(hash_state, root, orderfields(use, fieldsfn(x))) do k
            pair = k => getfieldfn(x, k)
            return pair, hash_method(pair, context), context
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

function hash_type_str(str, T)
    bytes = sha256(codeunits(str))
    return first(reinterpret(UInt64, bytes))
end

function hash_field_str(T)
    sha = SHA.SHA2_256_CTX()
    for f in sort_(fieldnames(T))
        if f isa Symbol
            SHA.update!(sha, codeunits(String(f)))
        else # e.g. in some weird cases the field names can be numbers ???
            SHA.update!(sha, reinterpret(UInt8, [f]))
        end
    end
    bytes = SHA.digest!(sha)

    return first(reinterpret(UInt64, bytes))
end

# NOTE: using stable_{typename|type}_id increases speed by ~x10-20 vs. `qualified_name`

"""
    stable_typename_id(x)

Returns a 64 bit hash that is the same for a given type so long as the name and the module
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

Returns a 64 bit hash that is the same for a given type so long as the module, and string
representation of a type is the same (invariant to comma spacing).

NOTE: if the module of a type is `Core` it is renamed to `Base` before hashing because the
location of some types changes between `Core` to `Base` across julia versions
"""
stable_type_id(x) = stable_id_helper(x, Val(:type))

"""
    stable_typefields_id(x)

Returns a 64 bit hash that is the same for a given type so long as the set of field names
remains unchanged.
"""
stable_typefields_id(::Type{T}) where {T} = hash_field_str(T)
@generated function stable_typefields_id(x)
    number = hash_field_str(x)
    :(return $number)
end

stable_eltype_id(x) = stable_type_id(eltype(x))

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
        throw(ArgumentError("Anonymous types (those containing `#`) cannot be hashed to a reliable value"))
    end
    return str
end

#####
##### Tuples 
#####

# detecting when we can elide struct and element types
elideable(fn::F, methods) where F = any(x -> x isa FnHash{F} || x isa ElidedTypeHash, methods)
has_iterate_type(methods) = any(x -> x isa IterateHash, methods)
has_struct_type(methods) = any(x -> x isa FieldStructHash, methods)

function stable_hash_helper(x, hash_state, context, root, methods::Tuple)
    if (elideable(stable_type_id, methods) && (has_iterate_type(methods) || has_struct_type(methods)))
        return tuple_hash_helper(x, hash_state, ElideType(context), root, methods)
    elseif (elideable(stable_eltype_id, methods) && has_iterate_type(methods))
        return tuple_hash_helper(x, hash_state, ElideType(context), root, methods)
    else
        return tuple_hash_helper(x, hash_state, context, root, methods)
    end
end

function tuple_hash_helper(x, hash_state, context, root, methods::Tuple{<:ElidedTypeHash})
    return hash_state
end

function tuple_hash_helper(x, hash_state, context, root, 
                           methods::Tuple{<:ElidedTypeHash, <:Any})
    return stable_hash_helper(x, hash_state, context, root, methods[2])
end

function tuple_hash_helper(x, hash_state, context, root, 
                           methods::Tuple{<:ElidedTypeHash, <:Any, Vararg{<:Any}})
    _, rest... = methods
    return hash_foreach(hash_state, root, rest) do method
        return x, method, context
    end
end

function tuple_hash_helper(x, hash_state, context, root, methods)
    return hash_foreach(hash_state, root, methods) do method
        return x, method, context
    end
end

function stable_hash_helper(x, hash_state, context, root::Union{Val{1}, Val{2}}, methods::Tuple)
    return hash_foreach(hash_state, root, methods) do method
        return x, method, context
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
function stable_hash_helper(x, hash_state, context, root, method::HashAndContext)
    return stable_hash_helper(x, hash_state, method.contextfn(context), root, method.parent)
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
    if Base.isprimitivetype(T) 
        V < 3 && return WriteHash()
        return (TypeHash(c), WriteHash())
    end
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
function hash_method(::AbstractString, c::HashVersion{V}) where V
    return (FnHash(V > 1 ? stable_type_id : qualified_name, WriteHash()),
            WriteHash())
end
hash_method(::Symbol, ::HashVersion{1}) = (PrivateConstantHash(":"), WriteHash())
hash_method(::Symbol, ::HashVersion) = (@ConstantHash(":"), WriteHash())
function hash_method(::AbstractDict, c::HashVersion{V}) where V
    return (V < 2 ? FnHash(qualified_name_) :
            FnHash(stable_typename_id, WriteHash()),
            StructHash(keys => getindex, :ByName))
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

Create a hash context where only the contents of an array or string determine its hash: that is,
the type of the array or string (e.g. `SubString` vs. `String`) does not impact the hash
value.
"""
struct ViewsEq{T}
    parent::T
end
ViewsEq() = ViewsEq(HashVersion{1}())
parent_context(x::ViewsEq) = x.parent
function hash_method(::AbstractArray, c::ViewsEq)
    return (root_version(c) > 1 ? @ConstantHash("Base.AbstractArray") : 
                                  ConstantHash("Base.AbstractArray"), 
            (root_version(c) > 2 ? (FnHash(stable_eltype_id),) : ())...,
            FnHash(size), 
            IterateHash())
end
function hash_method(::AbstractString, c::ViewsEq)
    return (root_version(c) > 1 ? @ConstantHash("Base.AbstractString") : 
                                  ConstantHash("Base.AbstractString", WriteHash()), 
            WriteHash())
end

end
