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
5. `UseSize(method)`: hash the result of calling `size` on the object and use 
    `method` to hash the contents of the value (e.g. `UseIterate`).

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

## Breaking changes

### In 0.3:

To prevent reshaped arrays from having the same hash (`stable_hash([1 2; 3 4]) ==
stable_hash(vec([1 2; 3 4]))`) the hashes for all arrays with more than 1 dimension have
changed.

### In 0.2:

To support hasing of all tables (`Tables.istable(x) == true`), hashes have changed for such
objects when:
   1. calling `stable_hash(x)` did not previously error
   1. `x` is not a `DataFrame` (these previosuly errored)
   2. `x` is not a `NamedTuple` of tables columns (these have the same hash as before)
   3. `x` is not an `AbstractArray` of `NamedTuple` rows (these have the same hash as before)
   4. `x` can be succefully written to an IO buffer via `Base.write` or
     `StableHashTraits.write` (otherwise it previosuly errored)
   5. `x` has no specialized `stable_hash` method defined for it (otherwise
   the hash will be the same)

Any such table now uses the method `UseTable`, rather than `UseWrite`, and so would have the
same hash as a `DataFrame` or `NamedTuple` with the same column contents instead of its
previous hash value. For example if you had a custom table type `MyCustomTable` for which
you only defined a `StableHashTraits.write` method and no `hash_method`, its hash will be
changed unless you now define `hash_method(::MyCustomTable) = UseWrite()`.

## Avoiding Type Piracy

It can be very tempting to define `hash_method` for types that were defined by another
package or from Base. This is type piracy, and can easily lead to two different packags
defining the same method: in this case, the method which gets used depends on the order of
`using` statements... yuck.

To avoid this problem, it is possible define a two argument version of `hash_method` (and/or
a three argument version of `StableHashTraits.write`). This final arugment can be anything
you want, so long as it is a type you have defined. For example:

    using DataFrames
    struct MyContext end
    StableHashTraits.hash_method(::DataFrame, ::MyContext) = UseProperties(:ByName)
    stable_hash(DataFrames(a=1:2, b=1:2); context=MyContext())

By default the context is `StableHashTraits.GlobalContext` and just two methods are defined.

    hash_method(x, context) = hash_method(x)
    StableHashTraits.write(io, x, context) = StableHashTraits.write(io, x)

In this way, you only need to define methods for the types that have non-default behavior
for your context; furthermore, those who have no need of a particular context can simply
define the one-argument version of `hash_method` and/or two argument version of `write`.

## Hashing gotcha's

Here-in is a list of hash collisions that have been deemed to be acceptable in practice:

- `stable_hash(sin) == stable_hash("Base.sin")`
- `stable_hash([1,2,3]) == stable_hash((1,2,3))`
- `stable_hash(DataFrame(x=1:10)) == stable_hash((; x=collect(1:10)))`
- `stable_hash(1:10) == stable_hash((;start=1, stop=10))`