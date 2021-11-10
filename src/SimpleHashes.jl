module SimpleHashes

const crc32 = crc(CRC_32)

struct UseWrite; end
hashwrite(io, x, ::UseWrite) = write(io, x)

struct UseIterate{T}; end
UseIterate() = UseIteratoe{:nottyped}()
qualified_name(::T) where T = string(parentmodule(T), '.', nameof(T))
function hashwrite(io, x, ::UseIterate{T}) where T
    T == :typed && haswrite(io, qualified_name(x))
    for el in x
        hashwrite(io, el)
    end
end

struct UseProperties{T}; end
UseProperties() = UseProperties{:nottyped}()
function hashwrite(io, x, ::UseProperties{T}) where T
    T == :typed && haswrite(io, qualified_name(x))
    for key in propertynames(x)
        hashwrite(io, key)
        hashwrite(io, getproperty(x, key))
    end
end

struct UseStringify; end
function hashwrite(io, x, ::UseStringify)
    str = string(x)
    if startswith(str, "#")
        error("Unnamed function objects cannot be hashed to a reliable value")
    end
    hashwrite(io, str)
end

"""
    hashmethod(x)

Retrieve the trait object that indicates how a type should be hashed using
`stablehash`. 

There are four (zero-argument) constructors you can return from this function. 
1. `UseWrite`: writes the object to a binary format using `write(io, x)` and
   takes a hash of that.
2. `UseIterate`: assumes the object is iterable and finds a hash of all elements
3. `UseProperties`: assumes a struct of some type and uses `propertynames` and
   `getproperty` to compute a hash of all fields.
4. `UseStringify`: hashes `string(x)`, throwing an error for strings that start
   with `#` 

## Implemented methods

Functions default to `UseStringify`, NamedTuple's to `UseProperties` and tuples
and arrays to `UseIterate`, all other objects default to `UseWrite`.

## Including object type in the hashed value

The type is not hashed for `UseIterate` and `UseProperties`. This means that
e.g. two objects with the same set of properties and values will hash to the
same value. You can include the qualified name of the type (as a string) in the
hashed value, by setting the first type argument to :typed (e.g.
`UseIterate{:typed}()`) (a fall back method sets this argument to `:nottyped` by
default).

"""
hashmethod(::Any) = UseWrite()
hashmethod(::Union{Tuple,Array}) = UseIterate()
hashmethod(::NamedTuple) = UseProperties()
hashmethod(::Function) = UseStringify()

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
function stablehash(obj...)
    io = IOBuffer()
    hashwrite(io,obj)
    crc32(take!(io))
end

end
