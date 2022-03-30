# StableHashTraits

[![Project Status: Active – The project has reached a stable, usable state and is being actively developed.](https://www.repostatus.org/badges/latest/active.svg)](https://www.repostatus.org/#active)
 [![GitHub Actions](https://github.com/beacon-biosignals/StableHashTraits.jl/workflows/CI/badge.svg)](https://github.com/beacon-biosignals/StableHashTraits.jl/actions/workflows/ci.yml)
 [![codecov](https://codecov.io/gh/beacon-biosignals/StableHashTraits.jl/branch/main/graph/badge.svg?token=4O1YO0GMNM)](https://codecov.io/gh/beacon-biosignals/StableHashTraits.jl)
[![Code Style: YASGuide](https://img.shields.io/badge/code%20style-yas-violet.svg)](https://github.com/jrevels/YASGu)


The aim of StableHashTraits is to make it easy to compute a stable hash of any Julia value
with minimal boilerplate using trait-based dispatch; here, "stable" means the value will not
change across Julia versions (or between Julia sessions).

For example:


```julia
struct MyType
   a
   b
end
StableHashTraits.hash_method(::MyType) = UseProperties()

stable_hash(MyType(1,2)) == stable_hash((a=1, b=2)) # true
```

## Why use `stable_hash` instead of `Base.hash`?

This package can be useful when:
- you want to be ensure the hash value will not change when you update Julia or start a new session, OR
- you want to compute a hash for an object that does not have `hash` defined. 

This is useful for content-addressed caching, in which e.g. some function of a value is stored at a location determined by a hash. Given the value, one can recompute the hash to determine where to look to see if the function evaluation on that value has already been cached.

It isn't intended for secure hashing.

## Details

There is one exported method: `stable_hash`. You call this on any number of
objects and the returned value is a hash of those objects (the argument order
matters).

You can customize its behavior for particular types by implementing the trait
`StableHashTraits.hash_method`. Any method of `hash_method` should simply return one of the following values.

1. `UseWrite()`: writes the object to a binary format using `StableHashTraits.write(io, x)` and
   takes a hash of that (this is the default behavior). `StableHashTraits.write(io, x)` falls
   back to `Base.write(io, x)` if no specialized methods are defined for x.
2. `UseIterate()`: assumes the object is iterable and finds a hash of all
   elements
3. `UseProperties()`: assumes a struct of some type and uses `propertynames` and
   `getproperty` to compute a hash of all fields. You can further customize its
   behavior by passing the symbol `:ByOrder` (to hash properties in the order
   they are listed by `propertynames`), which is the default, or `:ByName`
   (sorting properties by their name before hashing).
4. `UseQualifiedName()`: hash the string `parentmodule(T).nameof(T)` where `T`
   is the type of the object. Throws an error if the name includes `#` (e.g. an
   anonymous function). If you wish to include this qualified name *and* another
   method, pass one of the other three methods as an arugment (e.g.
   `UseQualifiedName(UseProperites())`). This can be used to include the type as
   part of the hash. Do you want a named tuple with the same properties as your
   custom struct to hash to the same value? If you don't, then use
   `UseQualifiedName`.

Your hash will be stable if the output for the given method remains the same: e.g. if `write` is the same for an object that uses `UseWrite`, its hash will be the same; if the properties are the same for `UseProperties`, the hash will be the same; etc...

## Implemented methods of `hash_method`

- `Any`: `UseWrite()`
- `Function`: `UseQualifiedName()`
- `NamedTuples`: `UseProperties()` 
- `AbstractArray`, `Tuple`, `Pair`: `UseIterate()`
- `Missing`, `Nothing`: `UseQualifiedNamed()`