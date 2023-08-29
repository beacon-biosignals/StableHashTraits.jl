module StableHashTraits

export stable_hash, WriteHash, IterateHash, StructHash, FnHash, ConstantHash,
       HashAndContext, HashVersion, qualified_name, qualified_type, TablesEq, ViewsEq
using TupleTools, Tables, Compat
using SHA: SHA, sha256

"""
    HashVersion{1}()

The default `hash_context` used by `stable_hash`. There is currently only one version (`1`)
and it is the default context. By explicitly passing this context to `stable_hash` you
ensure that hash values for these fallback methods will not change even if new fallbacks are
defined. This is a "root" context, meaning that `parent_context(::HashVersion) = nothing`.
"""
struct HashVersion{V} end

"""
    stable_hash(x, context=HashVersion{1}(); alg=sha256)

Create a stable hash of the given objects. As long as the context remains the same, this is
intended to remain unchanged across julia verisons. How each object is hashed is determined
by [`hash_method`](@ref), which aims to have sensible fallbacks.

To ensure the greattest stability, explicitly pass the context object. Even if the fallback
methods change in a future release, the hash you get by passing an explicit `HashVersin{N}`
should *not* change. (Note that the number in `HashVersion` may not necessarily match the
package verison of `StableHashTraits`).

To change the hash algorithm used, pass a different function to `alg`. It accepts any `sha`
related function from `SHA` or any function of the form `hash(x::AbstractArray{UInt8},
[old_hash])`.

The `context` value gets passed as the second argument to [`hash_method`](@ref), and as the
third argument to [`StableHashTraits.write`](@ref)

"""
function stable_hash(x, context=HashVersion{1}(); alg=sha256)
    return digest!(stable_hash_helper(x, setup_hash_state(alg), context,
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
##### Hash Function API 
#####

# setup_hash_state: given a function that identifies the hash, setup up the state used for hashing
for fn in filter(startswith("sha") ∘ string, names(SHA))
    CTX = Symbol(uppercase(string(fn)), :_CTX)
    if CTX in names(SHA)
        @eval setup_hash_state(::typeof(SHA.$(fn))) = SHA.$(CTX)()
    end
end
# similar_hash_state: setup up a new hasher, given some existing state created by `setup_hash_state`
similar_hash_state(ctx::SHA.SHA_CTX) = typeof(ctx)()
# update!: update the hash state with some new data to hash
update!(sha::SHA.SHA_CTX, bytes) = SHA.update!(sha, bytes)
# digest!: convert the hash state to the final hashed value
digest!(sha::SHA.SHA_CTX) = SHA.digest!(sha)

# convert a function of the form `new_hash = hasher(x, [old_hash])`, to conform to the API
# above that uses `setup_hash_state`, `similar_hash_state`, `update!` and `digest!`
mutable struct GenericFunHash{F,T}
    hasher::F
    hash::T
    init::T
    function GenericFunHash(fn)
        hash = fn(UInt8[])
        return new{typeof(fn),typeof(hash)}(fn, hash, hash)
    end
    function GenericFunHash(fn, hash, init)
        return new{typeof(fn), typeof(hash)}(fn, hash, init)
    end
end
setup_hash_state(fn) = GenericFunHash(fn)
function update!(fn::GenericFunHash, bytes)
    return fn.hash = fn.hasher(bytes, fn.hash)
end
digest!(fn::GenericFunHash) = fn.hash
similar_hash_state(fn::GenericFunHash) = GenericFunHash(fn.hasher, fn.init, fn.init)

#####
##### Hash Traits
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
# These are the various methods to compute a hash from an object

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
    io = IOBuffer()
    write(io, x, context)
    update!(hash_state, take!(io))
    return hash_state
end

# optimized hash helpers for primitive types
bytesof(x::Int64) = (UInt8(x & 0xff), UInt8((x >> 8) & 0xff), UInt8((x >> 16) & 0xff), 
                     UInt8((x >> 32) & 0xff))
# TODO: make a more generic version of `bytesof` for all primitive types
function stable_hash_helper(x::Number, hash_state, context, ::WriteHash)
    update!(hash_state, bytesof(x))
    return hash_state
end

function stable_hash_helper(x::String, hash_state, context, ::WriteHash)
    update!(hash_state, codeunits(x))
    return hash_state
end

function recursive_hash!(hash_state, nested_hash_state)
    nested_hash = digest!(nested_hash_state)
    update!(hash_state, reinterpret(UInt8, vcat(nested_hash)))
    return hash_state
end

struct IterateHash end
function stable_hash_helper(x, hash_state, context, ::IterateHash)
    return hash_foreach(identity, hash_state, context, x)
end

# TODO: handle when recursive hashing occurs based on
# the HashContext{1} vs. HashContext{2}
function hash_foreach(fn, hash_state, context, xs)
    inner_state = similar_hash_state(hash_state)
    for x in xs
        f_x = fn(x)
        stable_hash_helper(f_x, inner_state, context,
                           hash_method(f_x, context))
    end
    return recursive_hash!(hash_state, inner_state)
end

# function hash_foreach(fn::typeof(identity), hash_state, context, xs::AbstractVector{<:Real})
#     inner_state = similar_hash_state(hash_state)
#     for x in xs
#         f_x = fn(x)
#         stable_hash_helper(f_x, inner_state, context,
#                            hash_method(f_x, context))
#     end
#     return recursive_hash!(hash_state, inner_state)
# end

struct StructHash{P,S}
    fnpair::P
end
StructHash(x::Symbol) = StructHash((fieldnames ∘ typeof) => getfield, x)
function StructHash(fnpair::Pair=(fieldnames ∘ typeof) => getfield, by::Symbol=:ByOrder)
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
    return hash_foreach(hash_state, context, orderfields(use, fieldsfn(x))) do k
        return k => getfieldfn(x, k)
    end
end

qname_(T, name) = validate_name(cleanup_name(string(parentmodule(T), '.', name(T))))
qualified_name(fn::Function) = qname_(fn, nameof)
qualified_type(fn::Function) = qname_(fn, string)
qualified_name(x::T) where {T} = qname_(T <: DataType ? x : T, nameof)
qualified_type(x::T) where {T} = qname_(T <: DataType ? x : T, string)

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

function stable_hash_helper(x, hash_state, context, methods::Tuple)
    for method in methods
        val = stable_hash_helper(x, similar_hash_state(hash_state), context, method)
        recursive_hash!(hash_state, val)
    end

    return hash_state
end

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
##### Contexts
#####

"""
    StableHashTraits.parent_context(context)

Return the parent context of the given context object. (See [`hash_method`](@ref) for
details of using context). The default method falls back to returning `HashVersion{1}`, but
this is flagged as a deprecation warning; in the future it is expected that all contexts
define this method.

This is normally all that you need to know to implement a new context. However, if your
context is expected to be the root context—one that does not fallback to any parent (akin to
`HashVersion{1}`)—then there may be a bit more work invovled. In this case, `parent_context`
should return `nothing` so that the single argument fallback for `hash_method` can be
called. 

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

function hash_method(x::T, c::HashVersion{1}) where {T}
    # we need to find `default_method` here because `hash_method(x::MyType, ::Any)` is less
    # specific than the current method, but if we have something defined for a specific type
    # as the first argument, we want that to be used, rather than this fallback (as if it
    # were defined as `hash_method(::Any)`). Note that changing this method to be x::Any,
    # and using T = typeof(x) would just lead to method ambiguities when trying to decide
    # between `hash_method(::Any, ::HashVersion{1})` vs. `hash_method(::MyType, ::Any)`.
    # Furthermore, this would would require the user to define `hash_method` with two
    # arguments.
    default_method = hash_method(x, parent_context(c)) # we call `parent_context` to exercise all fallbacks
    is_implemented(default_method) && return default_method
    Base.isprimitivetype(T) && return WriteHash()
    # merely reordering a struct's fields should be considered an implementation detail, and
    # should not change the hash
    return (FnHash(qualified_type), StructHash(:ByName))
end
hash_method(::NamedTuple, ::HashVersion{1}) = (FnHash(qualified_name), StructHash())
function hash_method(::AbstractRange, ::HashVersion{1})
    return (FnHash(qualified_name), StructHash(:ByName))
end
function hash_method(::AbstractArray, ::HashVersion{1})
    return (FnHash(qualified_name), FnHash(size), IterateHash())
end
function hash_method(::AbstractString, ::HashVersion{1})
    return (FnHash(qualified_name, WriteHash()), WriteHash())
end
hash_method(::Symbol, ::HashVersion{1}) = (ConstantHash(":"), WriteHash())
function hash_method(::AbstractDict, ::HashVersion{1})
    return (FnHash(qualified_name), StructHash(keys => getindex, :ByName))
end
hash_method(::Tuple, ::HashVersion{1}) = (FnHash(qualified_name), IterateHash())
hash_method(::Pair, ::HashVersion{1}) = (FnHash(qualified_name), IterateHash())
function hash_method(::Type, ::HashVersion{1})
    return (ConstantHash("Base.DataType"), FnHash(qualified_type))
end
function hash_method(::Function, ::HashVersion{1})
    return (ConstantHash("Base.Function"), FnHash(qualified_name))
end
function hash_method(::AbstractSet, ::HashVersion{1})
    return (FnHash(qualified_name), FnHash(sort! ∘ collect))
end

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

parent_context(::HashVersion) = nothing

end
