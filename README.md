# SimpleHashes

[![Project Status: Active – The project has reached a stable, usable state and is being actively developed.](https://www.repostatus.org/badges/latest/active.svg)](https://www.repostatus.org/#active)
 [![GitHub Actions](https://github.com/beacon-biosignals/SimpleHashes.jl/workflows/CI/badge.svg)](https://github.com/beacon-biosignals/SimpleHashes.jl/actions/workflows/ci.yml)
[![Code Style: YASGuide](https://img.shields.io/badge/code%20style-yas-violet.svg)](https://github.com/jrevels/YASGu


The aim of SimpleHashes is to make it easy to compute a stable hash of any Julia
value with minimal boilerplate; here, "stable" means the value will not change
across Julia versions (or between Julia).

For example:


```julia
struct MyType
   a
   b
end
SimpleHashes.hash_method(::MyType) = UseProperties()

simple_hash(MyType(1,2)) == simple_hash((a=1, b=2)) # true
```

## Details

There is one exported method: `simple_hash`. You call this on any number of
objects and the returned value is a hash of those objects (the argument order
matters).

You can cuztomize its behavior for particular types by implementing the trait
`SimpleHashes.hash_method`. Any method of `hash_method` should simply return one of the following values.

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

Your hash will be stable if the output for the given method remains the same: e.g. if `write` is the same for an object that uses `UseWrite`, its hash will be the same; if the properties are the same for `UseProperties`, the hash will be the same; etc...

## Implemented methods of `hash_method`

- `Any`: `UseWrite()`
- `Function`: `UseQualifiedName()`
- `NamedTuples`: `UseProperties()` 
- `Array`, `Tuple`: `UseIterate()`
