# SimpleHashes

[![Project Status: Active – The project has reached a stable, usable state and is being actively developed.](https://www.repostatus.org/badges/latest/active.svg)](https://www.repostatus.org/#active)
 [![GitHub Actions](https://github.com/beacon-biosignals/SimpleHashes.jl/workflows/CI/badge.svg)](https://github.com/beacon-biosignals/SimpleHashes.jl/actions/workflows/ci.yml)


The aim of SimpleHashes is to make it easy to compute a stable hash of any Julia
value with minimal boilerplate; here, "stable" means the value will not change
across Julia versions.

For example:


```julia
struct MyType
   a
   b
end
SimpleHashes.hashmethod(::MyType) = UseProperties()

simplehash(MyType(1,2)) == simplehash((a=1, b=2)) # true
```

## Details

There is one exported method: `simplehash`. You call this on any number of
objects and the returned value is a hash of those objects (the argument order
matters).

You can cuztomize its behavior for particular types by implementing the trait
`SimpleHashes.hashmethod`. Any method of `hashmethod` should simply return one of the following values.

1. `UseWrite()`: writes the object to a binary format using `write(io, x)` and
   takes a hash of that (this is the default behavior).
2. `UseIterate()`: assumes the object is iterable and finds a hash of all
   elements
3. `UseProperties()`: assumes a struct of some type and uses `propertynames` and
   `getproperty` to compute a hash of all fields.
4. `UseQualifiedName()`: hash the string `parentmodule(T).nameof(T)` where `T`
   is the type of the object. Throws an error if the name includes `#` (e.g. an
   anonymous function). If you wish to include this qualified name *and* another
   method, pass one of the other three methods as an arugment (e.g.
   `UseQualifiedName(UseProperites())`)

This means that by default, if `write` for an object changes, so will its hash.
The easiest way to make a hash stable is to use one of the other options (2-4).

## Implemented methods of `hashmethod`

- `Any`: `UseWrite()`
- `Function`: `UseQualifiedName`
- `NamedTuples`: `UseProperties` 
- `Array`, `Tuple`: `UseIterate`
