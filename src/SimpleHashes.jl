module SimpleHashes

export simple_hash, UseWrite, UseIterate, UseProperties, UseQualifiedName

using CRC32c, TupleTools, Compat

struct UseWrite end
function simple_hash_helper(x, hash, ::UseWrite) 
    io = IOBuffer()
    write(io, x)
    return hash(take!(io))
end

hash_default(::typeof(crc32c)) = UInt32(0)
hash_default(x) = UInt

struct UseIterate end
function simple_hash_helper(x, hash, ::UseIterate)
    result = hash(UInt8[])
    for el in x
        result = hash(copy(reinterpret(UInt8, [simple_hash_helper(el, hash)])), result)
    end
    return result
end

struct UseProperties{S} end
function UseProperties(by::Symbol = :ByName)
    by ∈ (:ByName, :ByOrder) || error("Expected a valid sort order (:ByName or :ByOrder).")
    return UseProperties{by}()
end
orderproperties(::UseProperties{:ByOrder}, props) = props
orderproperties(::UseProperties{:ByName}, props) = TupleTools.sort(props; by=string)
function simple_hash_helper(x, hash, use::UseProperties)
    return simple_hash_helper((k => getproperty(x, k)
                               for k in orderproperties(use, propertynames(x))), hash, UseIterate())
end

struct UseQualifiedName{T}
    parent::T
end
UseQualifiedName() = UseQualifiedName(nothing)
qualified_name(x::Function) = string(parentmodule(x), '.', nameof(x))
qualified_name(::T) where {T} = string(parentmodule(T), '.', nameof(T))
qualified_name(::Type{T}) where {T} = string(parentmodule(T), '.', nameof(T))
function simple_hash_helper(x, hash, method::UseQualifiedName)
    str = qualified_name(x)
    if occursin(r"\.#[^.]*$", str)
        error("Annonymous types (those starting with `#`) cannot be hashed to a reliable value")
    end
    result = simple_hash_helper(str, hash)
    if !isnothing(method.parent)
        return hash(copy(reinterpret(UInt8, [simple_hash_helper(x, hash, method.parent)])), result)
    else
        return result
    end
end

"""
    hash_method(x)

Retrieve the trait object that indicates how a type should be hashed using
`simple_hash`. You should return one of the following values.

1. `UseWrite()`: writes the object to a binary format using `write(io, x)` and
   takes a hash of that (this is the default behavior).
2. `UseIterate()`: assumes the object is iterable and finds a hash of all
   elements
3. `UseProperties()`: assumes a struct of some type and uses `propertynames` and
   `getproperty` to compute a hash of all fields. You can further customize its
   behavior by passing the symbol `:ByName` (sorting properties by their name
   before hashing), which is the default, or `:ByOrder` (to hash properties in
   the order they are listed by `propertynames`).
4. `UseQualifiedName()`: hash the string `parentmodule(T).nameof(T)` where `T`
   is the type of the object. Throws an error if the name includes `#` (e.g. an
   anonymous function). If you wish to include this qualified name *and* another
   method, pass one of the other three methods as an arugment (e.g.
   `UseQualifiedName(UseProperites())`). This can be used to include the type as
   part of the hash. Do you want a named tuple with the same properties as your
   custom struct to hash to the same value? If you don't then use
   `UseQualifiedName`.

This means that by default, if `write` for an object changes, so will its hash.
The easiest way to make a hash stable is to use one of the other options (2-4).

## Implemented methods of `hash_method`

- `Any`: `UseWrite()`
- `Function`: `UseQualifiedName()`
- `NamedTuples`: `UseProperties()` 
- `Array`, `Tuple`: `UseIterate()`

"""
hash_method(::Any) = UseWrite()
hash_method(::Array) = UseIterate()
hash_method(::Tuple) = UseIterate()
hash_method(::Pair) = UseIterate()
hash_method(::NamedTuple) = UseProperties()
hash_method(::Function) = UseQualifiedName()

simple_hash_helper(x, hash) = simple_hash_helper(x, hash, hash_method(x))

"""
    simple_hash(arg1, arg2, ...; hash = crc32c)

Create a stable hash of the given objects. This is intended to remain unchanged
across julia verison. The default fallback method is to write the object and
compute the CRC of the written data. This method is the most generic but also
the most sensitive to various changes to the object that you might want to
consider irrelevant for its hash. 

You can customize how an object is hashed using `hash_method`.
"""
function simple_hash(obj...; hash = crc32c)
    return simple_hash_helper(obj, hash)
end

end