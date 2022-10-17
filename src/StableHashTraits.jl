module StableHashTraits

export stable_hash, UseWrite, UseIterate, UseProperties, UseQualifiedName

using CRC32c, TupleTools, Compat, UUIDs, Dates, Tables
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

"""
    StableHashTraits.transform(x, [context])

Before hashing object `x`, it is first passed through `transform`; the result of this call
is what is actually hashed. The fallback method is the identity function (`transform(x) =
x`).

!!! note "Optional Context"

    As with all other methods, you can specify a context---an aribtrary object---in which the
    given transform applies, but you need not implement a method that uses context unless you
    want to. If you do accept context, transform should return a tuple of the transformed object
    and the context, also possibly transformed. The fallback method is 
    `transform(x, context) = (transform(x), context)`.

In practice, the return value of `transform` is normally a tuple of some subset of values
from the object.
    
```julia
struct MyObject
    x::AbstractRange
    y::Vector{Float64}
    note::String
end
function StableHashTraits.transform(val::MyObject)
    return (val.x, val.y)
end
```

This would hash `MyObject` by hasing the data (x and y), but not the notes about that data.


By changing the context, you can change how something in that object gets hashed.

```julia
struct CustomHashObject
    x::AbstractRange
    y::Vector{Float64}
end
struct CustomContext{T}
    old_context::T
end
function StableHashTraits.transform(val::CustomHashObject, context)
    return (val.x, val.y), CustomContext(context)
end
StableHashTraits.hash_method(x::AbstractRange, ::CustomContext) = UseIterate()
StableHashTraits.hash_method(x, context::CustomContext) = hash_method(x, context.old_context)
```

This would ensure that the range (`x`) gets hashed by iterating of its contents, preserving
the behavior for all other objects that were true in the prior context.

## Methods of `transform`

```julia
transform(x::Set, context) = sort!(map(xᵢ -> stable_hash(xᵢ; context), collect(x)))
````

"""
transform(x, context) = transform(x), context
transform(x) = x
# NOTE: we need only call `transform` in `UseIterate` because all other hash methods that
# need to hash multiple subcomponents make use of of the `UseIterate` method.

function stable_hash_helper(x, hash, context, ::UseIterate)
    # this branch for isempty is not strictly necessary, (there are more elegant solutions)
    # but it is consistent with an older, less generic implementation of this method and
    # therefore avoids breaking changes to the hash value
    if isempty(x)
        update!(hash, UInt8[])
        return hash
    end
    for el in x
        el_, context_ = transform(el, context)
        val = stable_hash_helper(el_, similar_hasher(hash), context,
                                 hash_method(el_, context_))
        recursive_hash!(hash, val)
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
    vals = (k => getproperty(x, k) for k in orderproperties(use, propertynames(x)))
    return stable_hash_helper(vals, hash, context, UseIterate())
end

struct UseTable end
function stable_hash_helper(x, hash, context, ::UseTable)
    cols = Tables.columns(x)
    vals = (k => v for (k, v) in zip(Tables.columnnames(cols), cols))
    return stable_hash_helper(vals, hash, context, UseIterate())
end

struct UseQualifiedName{T}
    parent::T
end
UseQualifiedName() = UseQualifiedName(nothing)
qualified_name(x::Function) = string(parentmodule(x), '.', nameof(x))
qualified_name(::T) where {T} = string(parentmodule(T), '.', nameof(T))
qualified_name(::Type{T}) where {T} = string(parentmodule(T), '.', nameof(T))
function stable_hash_helper(x, hash, context, method::UseQualifiedName)
    str = qualified_name(x)
    if occursin(r"\.#[^.]*$", str)
        error("Annonymous types (those starting with `#`) cannot be hashed to a reliable value")
    end
    hash = stable_hash_helper(str, similar_hasher(hash), context, hash_method(str, context))
    if !isnothing(method.parent)
        val = stable_hash_helper(x, similar_hasher(hash), context, method.parent)
        recursive_hash!(hash, val)
        return hash
    else
        return hash
    end
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

#####
##### Hash method trait 
#####

# The way you indicate which method a given object uses to compute a hash.

"""
    hash_method(x, [context])

Retrieve the trait object that indicates how a type should be hashed using `stable_hash`.
You should return one of the following values.

1. `UseWrite()`: writes the object to a binary format using `StableHashTraits.write(io, x)`
    and takes a hash of that (this is the default behavior). `StableHashTraits.write(io, x)`
    falls back to `Base.write(io, x)` if no specialized methods are defined for x.
2. `UseIterate()`: assumes the object is iterable and finds a hash of all elements
3. `UseProperties()`: assumes a struct of some type and uses `propertynames` and
    `getproperty` to compute a hash of all fields. You can further customize its behavior by
    passing the symbol `:ByOrder` (to hash properties in the order they are listed by
    `propertynames`), which is the default, or `:ByName` (sorting properties by their name
    before hashing).
4. `UseTable()`: assumes the object is a `Tables.istable` and uses `Tables.columns` and
   `Tables.columnnames` to compute a hash of each columns content and name, ala
   `UseProperties`. This method should rarely need to be specified by the user, as the
   fallback method for `Any` should normally handle this case.
4. `UseQualifiedName()`: hash the string `parentmodule(T).nameof(T)` where `T` is the type
    of the object. Throws an error if the name includes `#` (e.g. an anonymous function). If
    you wish to include this qualified name *and* another method, pass one of the other
    methods as an arugment (e.g. `UseQualifiedName(UseProperties())`). This can be used to
    include the type as part of the hash. Do you want a named tuple with the same properties
    as your custom struct to hash to the same value? If you don't, then use
    `UseQualifiedName`.
5. `UseSize(method)`: hash the result of calling `size` on the object and use `method` to
    hash the contents of the value (e.g. `UseIterate`).

Your hash will be stable if the output for the given method remains the same: e.g. if
`write` is the same for an object that uses `UseWrite`, its hash will be the same; if the
properties are the same for `UseProperties`, the hash will be the same; etc...

## Implemented methods of `hash_method`

- `Any`: either
    - `UseWrite()` OR
    - `UseTable()` for any object `x` where `Tables.istable(x)` is true
- `Function`: `UseQualifiedName()`
- `NamedTuples`: `UseProperties()` 
- `AbstractVector`, `Tuple`, `Pair`: `UseIterate()`
- `AbstractArray`: `UseSize(UseIterate())`
- `Missing`, `Nothing`: `UseQualifiedNamed()`
- `VersionNumber`: `UseProperties()`
- `UUID`: `UseProperties()`
- `Dates.AbstractTime`: `UseProperties()`

For more complicated scenarios where impleneting `hash_method` will not suffice, refer to
the documentaiton of `transform` and `write`.

## Avoiding Type Piracy Using a Context Object

It can be very tempting to define `hash_method` for types that were defined by another
package or from Base. This is type piracy, and can easily lead to two different packags
defining the same method: in this case, the method which gets used depends on the order of
`using` statements... yuck.

To avoid this problem, it is possible to define a version of any method you specialize (e.g.
`hash_method`, `transform` and/or `write`) with one additional argument. This final argument
can be anything you want, so long as it is a type you have defined. For example:

    using DataFrames
    struct MyContext end
    StableHashTraits.hash_method(::DataFrame, ::MyContext) = UseProperties(:ByOrder)
    stable_hash(DataFrames(a=1:2, b=1:2); context=MyContext())

By default the context is `StableHashTraits.GlobalContext` and fall back methods are defined
that pass through to the methods without a context argument (e.g. `hash_method(x, context) =
hash_method(x)`)

In this way, you only need to define methods for the types that have non-default behavior
for your context; furthermore, those who have no need of a particular context objects can
simply define methods without it.

```
"""
hash_method(x::Any) = Tables.istable(x) ? UseTable() : UseWrite()
hash_method(::AbstractVector) = UseIterate()
hash_method(::AbstractArray) = UseSize(UseIterate())
hash_method(::AbstractRange) = UseProperties()
hash_method(::Tuple) = UseIterate()
hash_method(::Pair) = UseIterate()
hash_method(::NamedTuple) = UseProperties()
hash_method(::Function) = UseQualifiedName()
hash_method(::Type) = UseQualifiedName()
hash_method(::Nothing) = UseQualifiedName()
hash_method(::Missing) = UseQualifiedName()
hash_method(::VersionNumber) = UseProperties()
hash_method(::UUID) = UseProperties()
hash_method(::Dates.AbstractTime) = UseProperties()
# TODO: improve the API so context knows about the algorithm
# c.f. https://github.com/beacon-biosignals/StableHashTraits.jl/issues/17
transform(x::Set, context) = sort!([stable_hash(xᵢ; context) for xᵢ in x])

struct GlobalContext end
hash_method(x, context) = hash_method(x)

"""
    stable_hash(arg1, arg2, ...; context=StableHashTraits.GlobalContext(), alg=crc32c)

Create a stable hash of the given objects. This is intended to remain unchanged across julia
verisons. The default fallback method is to write the object and compute the CRC of the
written data. This method is the most generic but also the most sensitive to various changes
to the object that you might want to consider irrelevant for its hash. 

You can customize how an object is hashed using `hash_method`.

To change the hash algorithm used, pass a different function to `alg`. The function should
take one required argument (value to hash) and a second, optional argument (a hash value to
mix). Additionally `sha1` and `sha256` are supported (from the standard library `SHA`).

The `context` value gets passed as the second argument to [`hash_method`](@ref), and the
third argument to [`StableHashTraits.write`](@ref)

"""
function stable_hash(args...; context=GlobalContext(), alg=crc32c)
    # we always choose `UseIterate` here because that's how we want to hash multiple args,
    # regardless of how tuple hashing is defined.
    return digest!(stable_hash_helper(args, setup_hash(alg), context, UseIterate()))
end

end
