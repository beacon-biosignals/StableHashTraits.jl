module SimpleHashes

export simplehash, UseWrite, UseIterate, UseProperties, UseQualifiedName

using CRC, TupleTools, Compat

const crc32 = crc(CRC_32)

struct UseWrite end
hashwrite(io, x, ::UseWrite) = write(io, x)

struct UseIterate end
function hashwrite(io, x, ::UseIterate)
    for el in x
        hashwrite(io, el)
    end
end

struct UseProperties end
function hashwrite(io, x, ::UseProperties)
    for key in TupleTools.sort(propertynames(x), by=string)
        hashwrite(io, key)
        hashwrite(io, getproperty(x, key))
    end
end

struct UseQualifiedName{T}
    parent::T
end
UseQualifiedName() = UseQualifiedName(nothing)
qualified_name(x::Function) = string(parentmodule(x), '.', nameof(x))
qualified_name(::T) where T = string(parentmodule(T), '.', nameof(T))
qualified_name(::Type{T}) where T = string(parentmodule(T), '.', nameof(T))
function hashwrite(io, x, method::UseQualifiedName)
    str = qualified_name(x)
    if occursin(r"\.#[^.]*$", str)
        error("Annonymous types (those starting with `#`) cannot be hashed to a reliable value")
    end
    hashwrite(io, str)
    !isnothing(method.parent) && hashwrite(io, x, method.parent)
end

"""
    hashmethod(x)

Retrieve the trait object that indicates how a type should be hashed using
`stablehash`. You should return one of the following values.

1. `UseWrite()`: writes the object to a binary format using `write(io, x)` and
   takes a hash of that (this is the default behavior).
2. `UseIterate()`: assumes the object is iterable and finds a hash of all elements
3. `UseProperties()`: assumes a struct of some type and uses `propertynames` and
   `getproperty` to compute a hash of all fields.
4. `UseQualifiedName()`: hash the string `parentmodule(T).nameof(T)` where `T` is
   the type of the object. Throws an error if the name includes `#` (e.g. an
   anonymous function). If you wish to include this qualified name *and* another
   method, pass one of the other three methods as an arugment (e.g.
   `UseQualifiedName(UseProperites())`)

This means that by default, if `write` for an object changes, so will its hash.
The easiest way to make a hash stable is to return one of the other three
constructors from above.

## Implemented methods of `hashmethod`

- `Any`: `UseWrite()`
- `Function`: `UseQualifiedName`
- `NamedTuples`: `UseProperties` 
- `Array`, `Tuple`: `UseIterate`

"""
hashmethod(::Any) = UseWrite()
hashmethod(::Union{Tuple,Array}) = UseIterate()
hashmethod(::NamedTuple) = UseProperties()
hashmethod(::Function) = UseQualifiedName()

hashwrite(io, x) = hashwrite(io, x, hashmethod(x))

"""
    stablehash(arg1, arg2, ...)

Create a stable hash of the given objects. This is intended to remain unchanged
across julia verison. The default fallback method is to write the object and
compute the CRC of the written data. This method is the most generic but also
the most sensitive to various changes to the object that you might want to
consider irrelevant for its hash. 

You can customize how an object is hashed using `hashmethod`.
"""
function simplehash(obj...)
    io = IOBuffer()
    hashwrite(io, obj)
    crc32(take!(io))
end

end
