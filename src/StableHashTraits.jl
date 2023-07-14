module StableHashTraits

export stable_hash, UseWrite, UseIterate, UseFields, UseProperties, UseTable,
       UseQualifiedName, UseSize, UseTransform, UseHeader, UseAndReplaceContext, HashVersion
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

struct UseProperties{S} end
function UseProperties(by::Symbol=:ByOrder)
    by ∈ (:ByName, :ByOrder) || error("Expected a valid sort order (:ByName or :ByOrder).")
    return UseProperties{by}()
end
orderproperties(::UseProperties{:ByOrder}, props) = props
orderproperties(::UseProperties{:ByName}, props) = TupleTools.sort(props; by=string)
function stable_hash_helper(x, hash, context, use::UseProperties)
    return hash_foreach(hash, context, orderproperties(use, propertynames(x))) do k
        return k => getproperty(x, k)
    end
end

struct UseFields{S} end
function UseFields(by::Symbol=:ByOrder)
    by ∈ (:ByName, :ByOrder) || error("Expected a valid sort order (:ByName or :ByOrder).")
    return UseFields{by}()
end
orderfields(::UseFields{:ByOrder}, props) = props
orderfields(::UseFields{:ByName}, props) = TupleTools.sort(props; by=string)
function stable_hash_helper(x::T, hash, context, use::UseFields) where {T}
    return hash_foreach(hash, context, orderfields(use, fieldnames(T))) do k
        return k => getfield(x, k)
    end
end

struct UseTable end
function stable_hash_helper(x, hash, context, ::UseTable)
    cols = Tables.columns(x)
    return hash_foreach(Pair, hash, context, Tables.columnnames(cols), cols)
end

struct UseQualifiedName{P,T}
    parent::T
end
UseQualifiedName{P}(parent::T) where {P,T} = UseQualifiedName{P,T}(parent)
UseQualifiedName(parent::T=nothing) where {T} = UseQualifiedName{:WithoutParams}(parent)
UseQualifiedType(parent::T=nothing) where {T} = UseQualifiedName{:WithParams}(parent)
qualified_name_(T, ::Val{:WithoutParams}) = string(parentmodule(T), '.', nameof(T))
qualified_name_(T, ::Val{:WithParams}) = string(parentmodule(T), '.', string(T))
qualified_name(x::Function, _) = qualified_name_(x, Val(:WithoutParams))
qualified_name(::Type{T}, p) where {T} = qualified_name_(T, p)
qualified_name(::T, p) where {T} = qualified_name_(T, p)
function stable_hash_helper(x, hash, context, method::UseQualifiedName{P}) where {P}
    # We treat all uses of the `Core` namespace as `Base` across julia versions. What is in
    # `Core` changes, e.g. Base.Pair in 1.6, becomes Core.Pair in 1.9; also see
    # https://discourse.julialang.org/t/difference-between-base-and-core/37426
    str = replace(qualified_name(x, Val(P)), r"^Core\." => "Base.")
    if occursin(r"\.#[^.]*$", str)
        error("Annonymous types (those containing `#`) cannot be hashed to a reliable value")
    end
    return _stable_hash_header(str, x, hash, context, method.parent)
end

struct UseSize{T}
    parent::T
end
function stable_hash_helper(x, hash, context, method::UseSize)
    sz = size(x)
    hash = stable_hash_helper(sz, similar_hasher(hash), context, hash_method(sz, context))
    val = stable_hash_helper(x, similar_hasher(hash), context, method.parent)
    recursive_hash!(hash, val)
    return hash
end

struct UseHeader{T}
    str::String
    parent::T
end
function stable_hash_helper(x, hash, context, method::UseHeader)
    return _stable_hash_header(method.str, x, hash, context, method.parent)
end

strip_qualifier(x::UseQualifiedName) = x.parent
strip_qualifier(x::UseHeader) = x.parent
strip_qualifier(x) = x
function _stable_hash_header(str::String, x, hash, context, method)
    # we do not qualify the type of the header value (it will always be a string)
    # because that leads to an infinite recursion
    hash = stable_hash_helper(str, similar_hasher(hash), context,
                              strip_qualifier(hash_method(str, context)))
    isnothing(method) && return hash

    val = stable_hash_helper(x, similar_hasher(hash), context, method)
    recursive_hash!(hash, val)
    return hash
end

struct UseTransform{F}
    fn::F
end
function stable_hash_helper(x, hash, context, method::UseTransform)
    y = transform(x, method, context)
    return stable_hash_helper(y, hash, context, hash_method(y, context))
end

transform(x, _, _) = x
function transform(x, t::UseTransform, context)
    result = t.fn(x)
    if typeof(result) == typeof(x)
        # this would almost certainly lead to a StackOverflowError
        throw(ArgumentError("The function passed to `UseTransform` returns an object of the " *
                            "same type as its input."))
    else
        return transform(result, hash_method(result, context), context)
    end
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
                 "`$x`. See details in the docstring of `hash_method`.",
                 :parent_context)
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
3. `UseFields()`: assume a struct of some type and use `fieldnames(typeof(x))` and
   `getfield` to compute a hash of all fields. You can further customize its behavior by
   passing the symbol `:ByOrder` (to hash properties in the order they are listed by
   `propertynames`), which is the default, or `:ByName` (sorting properties by their name
   before hashing).
4. `UseQualifiedName([method])`: hash the string `parentmodule(T).nameof(T)` where `T` is
    the type of the object. Throws an error if the name includes `#` (e.g. an anonymous
    function). If you wish to include this qualified name *and* another method, pass one of
    the other methods as an arugment (e.g. `UseQualifiedName(UseProperties())`). This can be
    used to include the type as part of the hash. Do you want objects with the same field
    names and values but different types to hash to different values? Then specify
    `UseQualifiedName`.
5. `UseQualifiedType([method])`: like `UseQualifiedName` but use the string
   `parentmodule(T).string(T)` thereby including the type parameters of the type as well as
   its name.
6. `UseSize(method)`: hash the result of calling `size` on the object and use `method` to
    hash the contents of the value (e.g. `UseIterate`).
7. `UseTransform(fn -> body)`: before hashing the result, transform it by the given
   function; hash_method is then called on the return value. To help avoid stack overflows
   this cannot return an object of the same type.
8. `UseHeader(str::String, method)`: prefix the hash created by `method` with a hash of
   `str`.
9. `UseProperties()`: same as `UseField` but using `propertynames` and `getproperty` in lieu
   of `fieldnames` and `getfield`
10. `UseTable()`: assumes the object is a `Tables.istable` and uses `Tables.columns` and
   `Tables.columnnames` to compute a hash of each columns content and name, ala `UseFields`. 
10. `nothing`: indicates that you want to use a fallback method (see below); the two
   argument version of `hash_method` should never return `nothing`.

Your hash will be stable if the output for the given method remains the same: e.g. if
`write` is the same for an object that uses `UseWrite`, its hash will be the same; if the
properties are the same for `UseProperties`, the hash will be the same; etc...

## Implemented methods of `hash_method`

In the absence of a specific `hash_method` for your type, the following fallbacks are used.
They are intended to avoid hash collisions as best as possible.

- `Any`: 
    - `UseWrite()` for any object `x` where `isprimitivetype(typeof(x))` is true
    - `UseQualifiedType(UseFields(:ByName))` for all other types
- `NamedTuple`: `UseQualifiedName(UseFields())`
- `Function`: `UseHeader("Base.Function", UseQualifiedName())`
- `AbstractString`, `Symbol`: `UseQualifiedName(UseWrite())`
- `Tuple`, `Pair`: `UseQualifiedName(UseIterate())`
- `AbstractArray`: `UseHeader("Base.AbstractArray", UseSize(UseIterate()))`
- `AbstractRange`: `UseQualifiedName(UseFields())`
- `AbstractSet`: `UseQualifiedName(UseTransform(sort! ∘ collect))`
- `AbstractDict`: `UseQualifiedName(UseTransform(x -> sort!(collect(pairs(x)); by=first)))`

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
    return UseQualifiedName(UseFields(:ByName))
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
function hash_method(x::T, ::HashVersion{1}) where {T}
    default_method = hash_method(x)
    isnothing(default_method) || return default_method
    Base.isprimitivetype(T) && return UseWrite()
    # merely reordering a struct's fields should be considered an implementation detail, and
    # should not change the hash
    return UseQualifiedType(UseFields(:ByName))
end
hash_method(::NamedTuple, ::HashVersion{1}) = UseQualifiedName(UseFields())
hash_method(::AbstractRange, ::HashVersion{1}) = UseQualifiedName(UseFields(:ByName))
hash_method(::AbstractArray, ::HashVersion{1}) = UseQualifiedName(UseSize(UseIterate()))
hash_method(::AbstractString, ::HashVersion{1}) = UseQualifiedName(UseWrite())
hash_method(::Symbol, ::HashVersion{1}) = UseQualifiedName(UseWrite())
function hash_method(::AbstractDict, ::HashVersion{1})
    return UseQualifiedName(UseTransform(x -> sort!(collect(pairs(x)); by=first)))
end
hash_method(::Tuple, ::HashVersion{1}) = UseQualifiedName(UseIterate())
hash_method(::Pair, ::HashVersion{1}) = UseQualifiedName(UseIterate())
hash_method(::Type, ::HashVersion{1}) = UseQualifiedName()
hash_method(::Function, ::HashVersion{1}) = UseHeader("Base.Function", UseQualifiedName())
function hash_method(::AbstractSet, ::HashVersion{1})
    return UseQualifiedName(UseTransform(sort! ∘ collect))
end

"""
    HashVersion{1}()

The default `hash_context` used by `stable_hash`. There is currently only one version (`1`)
and it is the default version. By explicitly passing this context to `stable_hash` you
ensure that hash values for these fallback methods will not change even if new fallbacks are
defined. This is a "root" context, meaning that `parnet(::HashVersion) = nothing`. If
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
    return digest!(stable_hash_helper(x, setup_hash(alg), context,
                                      hash_method(x, context)))
end

end
