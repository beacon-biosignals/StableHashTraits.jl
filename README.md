# SimpleHashes

The aim of SimpleHashes is to make it easy to compute a stable hash of any Julia
value with minimal boilerplate; here, "stable" means the value will not change
across julia versions.

There is one exported method: `stablehash`. You call this on any number of
objects and the returned value is a hash of those objects (the argument order
matters).

You can cuztomize its behavior for particular objects by implementing `SimpleHashes.hashmethod` for the
type you'd like to customize. 

There are four (zero-argument) constructors you can return from `hashmethod`. 
1. `UseWrite`: writes the object to a binary format using `write(io, x)` and
   takes a hash of that (this is the default behavior).
2. `UseIterate`: assumes the object is iterable and finds a hash of all elements
3. `UseProperties`: assumes a struct of some type and uses `propertynames` and
   `getproperty` to compute a hash of all fields.
4. `UseStringify`: hashes `string(x)`, throwing an error for strings that start
   with `#`

Note that if `write` for an object changes, so will its hash, so the easiest way
to make its hash stable is to use one of the other methods.

## Implemented methods of `hashmethod`

The fallback method of `hashmethod` returns `UseWrite()`. Functions default to `UseStringify`, NamedTuple's to `UseProperties` and tuples
and arrays to `UseIterate`.

## Including object type in the hashed value

The type is not hashed for `UseIterate` and `UseProperties`. This means that
e.g. two objects with the same set of properties and values will hash to the
same value. You can include the qualified name of the type (as a string) in the
hashed value, by setting the first type argument to :typed (e.g.
`UseIterate{:typed}()`) (a fall back method sets this argument to `:nottyped` by
default).
