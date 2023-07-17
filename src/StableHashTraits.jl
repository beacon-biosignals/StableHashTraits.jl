module StableHashTraits

export stable_hash, UseWrite, UseIterate, UseStruct, Use, UseAndReplaceContext, HashVersion,
    qualified_name, qualified_type, TablesEq, ViewsEq
using CRC32c, TupleTools, Compat, Tables
using SHA: SHA

#####
##### Hash Function API 
#####

# SHA functions need to `update!` an context object for each object to hash and then
# `digest!` to get a final result. Many simpler hashing functions just take a second
# argument that is the output of a previous call to that function. We convert these generic
# functional hashes to match the interface of `SHA`, since it is the more general case.
mutable struct GenericFunHash{F,T}
    hasher::F
    hash::Union{T,Nothing}
    GenericFunHash(fn) = new{typeof(fn),typeof(fn(""))}(fn, nothing)
end
setup_hash(fn) = GenericFunHash(fn)
function update!(fn::GenericFunHash, bytes)
    return fn.hash = isnothing(fn.hash) ? fn.hasher(bytes) : fn.hasher(bytes, fn.hash)
end
digest!(fn::GenericFunHash) = fn.hash
similar_hasher(fn::GenericFunHash) = GenericFunHash(fn.hasher)

# TODO: support more sha versions?
setup_hash(::typeof(SHA.sha256)) = SHA.SHA2_256_CTX()
setup_hash(::typeof(SHA.sha1)) = SHA.SHA1_CTX()
similar_hasher(ctx::SHA.SHA_CTX) = typeof(ctx)()
update!(sha::SHA.SHA_CTX, bytes) = SHA.update!(sha, bytes)
digest!(sha::SHA.SHA_CTX) = SHA.digest!(sha)

#####
##### Hash Methods 
#####

# deprecations
@deprecate UseProperties(order=:ByOrder) UseStruct(propertynames => getproperty, order)
@deprecate UseQualifiedName(method=nothing) Use(qualified_name, method)
@deprecate UseSize(method=nothing) Use(size, method)
@deprecate UseTable() Use(Tables.columntable)

# These are the various methods to compute a hash from an object

struct UseWrite end
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
function stable_hash_helper(x, hash, context, ::UseWrite)
    io = IOBuffer()
    write(io, x, context)
    update!(hash, take!(io))
    return hash
end

function recursive_hash!(hash, result)
    interior_hash = digest!(result)
    # digest will return nothing if no objects have been added to the hash when using
    # GenericFunHash; in this case, don't update the hash at all
    if !isnothing(interior_hash)
        update!(hash, copy(reinterpret(UInt8, vcat(interior_hash))))
    end
    return hash
end

struct UseIterate end
function stable_hash_helper(x, hash, context, ::UseIterate)
    return hash_foreach(identity, hash, context, x)
end
function hash_foreach(fn, hash, context, args...)
    update!(hash, UInt8[])
    foreach(args...) do as...
        el = fn(as...)
        val = stable_hash_helper(el, similar_hasher(hash), context,
                                 hash_method(el, context))
        return recursive_hash!(hash, val)
    end
    return hash
end

struct UseStruct{P,S} 
    fnpair::P
end
UseStruct(x::Symbol) = UseStruct((fieldnames ∘ typeof) => getfield, x)
function UseStruct(fnpair::Pair=(fieldnames ∘ typeof) => getfield, by::Symbol=:ByOrder)
    by ∈ (:ByName, :ByOrder) || error("Expected a valid sort order (:ByName or :ByOrder).")
    return UseStruct{typeof(fnpair),by}(fnpair)
end
orderfields(::UseStruct{<:Any, :ByOrder}, props) = props
orderfields(::UseStruct{<:Any, :ByName}, props) = sort_(props)
sort_(x::Tuple) = TupleTools.sort(x; by=string)
sort_(x::AbstractSet) = sort!(collect(x))
sort_(x) = sort(x)
function stable_hash_helper(x, hash, context, use::UseStruct)
    fieldsfn, getfieldfn = use.fnpair
    return hash_foreach(hash, context, orderfields(use, fieldsfn(x))) do k
        return k => getfieldfn(x, k)
    end
end

qname_(T, name) = validate_name(cleanup_name(string(parentmodule(T), '.', name(T))))
qualified_name(fn::Function) = qname_(fn, nameof)
qualified_type(fn::Function) = qname_(fn, string)
qualified_name(x::T) where T = qname_(T, nameof)
qualified_type(x::T) where T = qname_(T, string)
qualified_name(::Type{T}, p) where {T} = qname_(T, nameof)
qualified_type(::Type{T}, p) where {T} = qname_(T, string)

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

struct Use{F,T}
    use::F
    then::T
end
Use(fn) = Use{typeof(fn), Nothing}(fn, nothing)
apply_use(x, method::Use{<:Base.Callable}) = method.use(x)
apply_use(_, method)  = method.use
function stable_hash_helper(x, hash, context, method)
    y = apply_use(x, method)
    if typeof(y) == typeof(x)
        throw(ArgumentError("The first argument to `Use` yields an object of the " *
                            "same type as the original object to be hashed; allowing this "*
                            "would almost certianly cause a StackOverflowError"))
    end
    h = stable_hash_helper(y, hash, context, hash_method(y, context))

    isnothing(method.then) && return h

    then_h = stable_hash_helper(x, similar_hasher(hash), context, method.then)
    return recursive_hash!(hash, then_h)
end

"""

    UseAndReplaceContext(method, old_context -> new_context)

A special hash method that changes the context when hashing the contents of an object. The
`method` defines how the object itself should be hashed and the second argument is a
callable which transforms the old context to the new.

!!! note It is best to nest the old context.

    In practice you generally only want to modify how hashing works for a subset 
    of the types, and then fallback to the old context. This can be achieved by
    nesting the old context, as follows:

    ```julia
        struct MyContext{P}
            parent_context::P
        end
        StableHashTraits.parent_context(x::MyContext) = x.parent_context

        StableHashTraits.hash_method(::MyContainedType, ::MyContext) = UseWrite()
        StableHashTraits.hash_method(::MyContainerType) = UseAndReplaceContext(UseIterate(), MyContext)
    ```
"""
struct UseAndReplaceContext{F,M}
    parent::M
    contextfn::F
end
function stable_hash_helper(x, hash, context, method::UseAndReplaceContext)
    return stable_hash_helper(x, hash, method.contextfn(context), method.parent)
end

#####
##### Hash method trait 
#####

"""
    StableHashTraits.parent_context(context)

Return the parent_context context of the given context object. (See [`hash_method`](@ref) for
details of using context). The default method falls back to returning `HashVersion{1}`, but
this is flagged as a deprecation warning; in the future it is expected that all contexts
define this method.

If your context is expected to be the root context (akin to `HashVersion{1}`), then 
`parent_context` should return `nothing` so that the single argument fallback for `hash_method`
can be called.
"""
function parent_context(x::Any)
    Base.depwarn("You should explicitly define a `parent_context` method for context " *
                 "`$x`. See details in the docstring of `hash_method`.", :parent_context)
    return HashVersion{1}()
end

# The way you indicate which method a given object used to compute a hash.

"""
    hash_method(x, [context])

Retrieve the trait object that indicates how a type should be hashed using `stable_hash`.
You should return one of the following values.

1. `UseWrite()`: writes the object to a binary format using `StableHashTraits.write(io, x)`
    and takes a hash of that (this is the default behavior). `StableHashTraits.write(io, x)`
    falls back to `Base.write(io, x)` if no specialized methods are defined for x.
2. `UseIterate()`: assumes the object is iterable and finds a hash of all elements
3. `UseStruct([pair = (fieldnames ∘ typeof) => getfield], [order])`: hash the structure of
    the object as defined by a sequence of pairs. How precisely this occurs is determined
    by the two arugments
        - `pair` Defines how fields are extracted; the default
          is `fieldnames ∘ typeof => getfield` but this could be changed to e.g.
          `propertynames => getproperty` or `Tables.columnnames => Tables.getcolumn`.
          The first element of the pair is a function used to compute a list of keys
          and the second element is a two argument function used to extract the keys 
          from the object.
        - `order` can be :ByOrder (the default)—which sorts by the order returned by `pair[1]` or
         `:ByName`—which sorts by lexigraphical order.
4. `Use(fn | value, [method])`: hash the static `value` or hash the value of
   applying `fn` to the given object. To prevent an infinite loop it is an error to return
   an object of the same type as the object you're hashing. Optionally, you can pass a
   second method that is also included in the hashed value. 
   There are two functions avaible for specific use-cases of `Use`
        - `qualified_name`: Get the qualified name of an objects type, e.g. `Base.String`
        - `qualified_type`: The the qualified name and type parameters of a type, 
           e.g. `Base.Array{Int, 1}`.
    For example, `Use(qualified_name, UseStruct())` would hash the structure of an object
    (using its fields) along with a hash of the module and name of the type.
5. `nothing`: indicates that you want to use a fallback method (see below); the two argument
   version of `hash_method` should never return `nothing`.

Your hash will be stable if the output for the given method remains the same: e.g. if
`write` is the same for an object that uses `UseWrite`, its hash will be the same; if the
fields are the same for `UseStruct`, the hash will be the same; etc...

## Implemented methods of `hash_method`

In the absence of a specific `hash_method` for your type, the following fallbacks are used.
They are intended to avoid hash collisions as best as possible.

- `Any`: 
    - `UseWrite()` for any object `x` where `isprimitivetype(typeof(x))` is true
    - `Use(qualified_type, UseStruct(:ByName))` for all other types
- `NamedTuple`: `Use(qualified_name, UseStruct())`
- `Function`: `Use("Base.Function", Use(qualified_name))`
- `AbstractString`: `Use(qualified_name, UseWrite())`
- `Symbol`: `Use(":", UseWrite())`
- `String`: `UseWrite()` (note: removing the `Use(qualified_name` prevents an infinite loop)
- `Tuple`, `Pair`: `Use(qualified_name, UseIterate())`
- `Type`: `UseQualifiedType`
- `AbstractArray`: `Use("Base.AbstractArray", UseSize(UseIterate()))`
- `AbstractRange`: `Use(qualified_name, UseStruct())`
- `AbstractSet`: `Use(qualified_name, UseTransform(sort! ∘ collect))`
- `AbstractDict`: `Use(qualified_name, UseStruct(keys => getindex, :ByName))`

## Customizing hash computations with contexts

You can customize how hashes are computed within a given scope using a context object. This
is also a very useful way to avoid type piracy. The context can be any object you'd like and
is passed as the second argument to `stable_hash`. By default it is equal to
`HashVersion{1}` and this is the context for which the default fallbacks listed above are
defined.

This context is then passed to both `hash_method` and `StableHashTraits.write` (the latter
is the method called for `UseWrite`, and which falls back to `Base.write`). Because of the
way the default context (`HashVersion{1}`) is defined, you normally don't have to include
this context as an argument when you define a method of `hash_context` or `write` because
there are appropriate fallback methods.

When you define a hash context it should normally accept a parent context that serves as a
fallback, and return it in an implementation of the method
`StableHashTratis.parent_context`. For example, here is how we could write a context that
treats all named tuples with the same keys as equivalent. 

```julia
struct NamedTuplesEq{T}
    parent::T
end
StableHashTraits.parent_context(x::NamedTuplesEq) = x.parent
function StableHashTraits.hash_method(::NamedTuple, ::NamedTuplesEq) 
    return UseQualifiedName(UseStruct(:ByName))
end
c = NamedTuplesEq(HashVersion{1}())
stable_hash((; a=1:2, b=1:2), c) == stable_hash((; b=1:2, a=1:2), c) # true
```

If we did not define a method of `parent_context`, our context would need to implement a a
`hash_method` that covered the types `AbstractRange`, `Int64`, `Symbol` and `Pair` for the
call to `stable_hash` above to succeede.

### Customizing hashes within an object

Contexts can be changed not only when you call `stable_hash` but also when you hash the
contents of a particular object. This lets you change how hasing occurs within the object.
See the docstring of [`UseAndReplaceContext`](@ref) for details. 
"""
hash_method(x, context) = hash_method(x, parent_context(context))
hash_method(x, ::Nothing) = hash_method(x)
hash_method(::Any) = nothing

struct HashVersion{V} end
function hash_method(x::T, c::HashVersion{1}) where {T}
    default_method = hash_method(x)
    isnothing(default_method) || return default_method
    Base.isprimitivetype(T) && return UseWrite()
    # merely reordering a struct's fields should be considered an implementation detail, and
    # should not change the hash
    return Use(qualified_type, UseStruct(:ByName))
end
hash_method(::NamedTuple, ::HashVersion{1}) = Use(qualified_name, UseStruct())
hash_method(::AbstractRange, ::HashVersion{1}) = Use(qualified_name, UseStruct(:ByName))
hash_method(::AbstractArray, ::HashVersion{1}) = Use(qualified_name, Use(size, UseIterate()))
hash_method(::AbstractString, ::HashVersion{1}) = Use(qualified_name, UseWrite())
hash_method(::String, ::HashVersion{1}) = UseWrite()
hash_method(::Symbol, ::HashVersion{1}) = Use(":", UseWrite())
function hash_method(::AbstractDict, ::HashVersion{1})
    return Use(qualified_name, UseStruct(keys => getindex, :ByName))
end
hash_method(::Tuple, ::HashVersion{1}) = Use(qualified_name, UseIterate())
hash_method(::Pair, ::HashVersion{1}) = Use(qualified_name, UseIterate())
hash_method(::Type, ::HashVersion{1}) = Use(qualified_name)
hash_method(::Function, ::HashVersion{1}) = Use("Base.Function", Use(qualified_name))
hash_method(::AbstractSet, ::HashVersion{1}) = Use(qualified_name, Use(sort! ∘ collect))

"""
    TablesEq(parent_context)

Create a hash context for which `Tables.columntable(x) == Tables.columntable(y)` implies
that `stable_hash(x) == stable_hash(y)`. All other hashes as specified in the
`parent_context` remain unchanged.
"""
struct TablesEq{T}
    parent::T
end
TablesEq() = TablesEq(HashVersion{1}())
StableHashTraits.parent_context(x::TablesEq) = x.parent
function is_columntable(::Type{T}) where {T}
    T <: NamedTuple && all(f -> f <: AbstractVector, fieldtypes(T))
end
function StableHashTraits.hash_method(x::T, m::TablesEq) where {T}
    if Tables.istable(T)
        is_columntable(T) && return Use("Tables.AbstractColumns", UseStruct(:ByName))
        return Use(Tables.columntable)
    end
    return StableHashTraits.hash_method(x, parent_context(m))
end

"""
    ViewsEq(parent_context)

Create a hash context for which, if `all(x == y for x in xs, y in ys)` and `size(x) ==
size(y)` for two arrays `xs` and `ys`, and if `x == y` and `x` and `y` are `<:
AbstractString`, it implies that `stable_hash(x) == stable_hash(y)`, regardless of the types
of the arrays. All other hash values, as specified in the `parent_context` remain unchanged.
"""
struct ViewsEq{T}
    parent::T
end
ViewsEq() = ViewsEq(HashVersion{1}())
StableHashTraits.parent_context(x::ViewsEq) = x.parent
function StableHashTraits.hash_method(::AbstractArray, ::ViewsEq)
    return Use("Base.AbstractArray", Use(size, UseIterate()))
end
StableHashTraits.hash_method(::AbstractString, ::ViewsEq) = UseWrite()
StableHashTraits.hash_method(::String, ::ViewsEq) = UseWrite()

"""
    HashVersion{1}()

The default `hash_context` used by `stable_hash`. There is currently only one version (`1`)
and it is the default context. By explicitly passing this context to `stable_hash` you
ensure that hash values for these fallback methods will not change even if new fallbacks are
defined. This is a "root" context, meaning that `parent_context(::HashVersion) = nothing`. If
no method is defined for a type in this context, it will fallback to the single-argument
version of `hash_context`.
"""
parent_context(::HashVersion) = nothing

"""
    stable_hash(x, context=HashVersion{1}(); alg=crc32c)

Create a stable hash of the given objects. As long as the context remains the same, this is
intended to remain unchanged across julia verisons. How each object is hashed is determined
by [`hash_method`](@ref), which aims to have sensible fallbacks.

To ensure the greattest stability, explicitly pass the context object. Even if the fallback
methods change in a future release, the hash you get by passing an explicit `HashVersin{N}`
should *not* change. (Note that the number in `HashVersion` may not necessarily match the
package verison of `StableHashTraits`).

To change the hash algorithm used, pass a different function to `alg`. The function should
take one required argument (value to hash) and a second, optional argument (a hash value to
mix). Additionally `sha1` and `sha256` are supported (from the standard library `SHA`).

The `context` value gets passed as the second argument to [`hash_method`](@ref), and as the
third argument to [`StableHashTraits.write`](@ref)

"""
function stable_hash(x, context=HashVersion{1}(); alg=crc32c)
    return digest!(stable_hash_helper(x, setup_hash(alg), context, hash_method(x, context)))
end

end
