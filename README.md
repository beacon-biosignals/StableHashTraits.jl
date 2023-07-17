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
using StableHashTraits
using Dates

struct MyType
   data::Vector{UInt8}
   metadata::Dict{Symbol, Any}
end
# ignore `metadata`, `data` will be hashed using fallbacks for `AbstractArray` type
StableHashTraits.stable_hash(::MyType) = Use(x -> x.data) 
a = MyType(read("myfile.txt"), Dict{Symbol, Any}(:read => Dates.now()))
b = MyType(read("myfile.txt"), Dict{Symbol, Any}(:read => Dates.now()))
stable_hash(a) == stable_hash(b) # true
```

## Why use `stable_hash` instead of `Base.hash`?

This package can be useful when:
- you want to be ensure the hash value will not change when you update Julia or start a new session, OR
- you want to compute a hash for an object that does not have `hash` defined. 
- you want to customize how the hash works, but only within a specific scope.

This is useful for content-addressed caching, in which e.g. some function of a value is stored at a location determined by a hash. Given the value, one can recompute the hash to determine where to look to see if the function evaluation on that value has already been cached.

It isn't intended for secure hashing.

## Details

There is one exported method: `stable_hash`. You call this on the object you want to hash, and, as an optional second argument, you pass the context that determines how hasing occurs (this defaults to `HashVersion{1}`).

You can customize the hash behavior for particular types by implementing the trait
`StableHashTraits.hash_method`. It accepts the object you want to hash and, as an optional second argument, the context. Any method of `hash_method` should simply return one of the following values.

1. `UseWrite()`: writes the object to a binary format using `StableHashTraits.write(io, x)`
    and takes a hash of that (this is the default behavior). `StableHashTraits.write(io, x)`
    falls back to `Base.write(io, x)` if no specialized methods are defined for x.
2. `UseIterate()`: assumes the object is iterable and finds a hash of all elements
3. `UseStruct([pair = (fieldnames ∘ typeof) => getfield], [order])`: hash the structure of
    the object as defined by a sequence of pairs. How precisely this occurs is determined
    by the two arugments
        - `pair` Defines how fields are extracted; the default
          is `fieldnames ∘ typeof => getfield` but this could be changed to e.g.
          `propertynames => getproperty` or `Tables.columnnames => Tables.getcolumn`.
          The first element of the pair is a function used to compute a list of keys
          and the second element is a two argument function used to extract the keys 
          from the object.
        - `order` can be :ByOrder (the default)—which sorts by the order returned by 
          `pair[1]` or `:ByName`—which sorts by lexigraphical order.
4. `Use(fn | value, [method])`: hash the static `value` or hash the value of
   applying `fn` to the given object. To prevent an infinite loop it is an error to return
   an object of the same type as the object you're hashing. Optionally, you can pass a
   second method that is also included in the hashed value. 
   There are two functions avaible for specific use-cases of `Use`
        - `qualified_name`: Get the qualified name of an objects type, e.g. `Base.String`
        - `qualified_type`: The the qualified name and type parameters of a type, 
           e.g. `Base.Array{Int, 1}`.
    For example, `Use(qualified_name, UseStruct())` would hash the structure of an object
    (using its fields) along with a hash of the module and name of the type.
5. `nothing`: indicates that you want to use a fallback method (see below); the two argument
   version of `hash_method` should never return `nothing`.

Your hash will be stable if the output for the given method remains the same: e.g. if
`write` is the same for an object that uses `UseWrite`, its hash will be the same; if the
properties are the same for `UseProperties`, the hash will be the same; etc...

## Implemented methods of `hash_method`

In the absence of a specific `hash_method` for your type, the following fallbacks
are used. They are intended to avoid hash collisions as best as possible.

- `Any`: 
    - `UseWrite()` for any object `x` where `isprimitivetype(typeof(x))` is true
    - `Use(qualified_type, UseStruct(:ByName))` for all other types
- `NamedTuple`: `Use(qualified_name, UseStruct())`
- `Function`: `Use("Base.Function", Use(qualified_name))`
- `AbstractString`: `Use(qualified_name, UseWrite())`
- `Symbol`: `Use(":", UseWrite())`
- `String`: `UseWrite()` (note: removing the `Use(qualified_name` prevents an infinite loop)
- `Tuple`, `Pair`: `Use(qualified_name, UseIterate())`
- `Type`: `UseQualifiedType`
- `AbstractArray`: `Use("Base.AbstractArray", UseSize(UseIterate()))`
- `AbstractRange`: `Use(qualified_name, UseStruct())`
- `AbstractSet`: `Use(qualified_name, UseTransform(sort! ∘ collect))`
- `AbstractDict`: `Use(qualified_name, UseStruct(keys => getindex, :ByName))`

There are two built-in contexts that can be used to modify these default fallbacks:
`TablesEq` and `ViewsEq`. `TablesEq` makes any table with equivalent content have the same
hash, and `ViewsEq` makes any array or string with the same sequence of values and the same
size have an equal hash. You can pass one or more of these as the second argument to table hash, e.g. `stable_hash(x, ViewsEq())` or `stable_hash(x, ViewsEq(TablesEq()))`.

## Breaking changes

### In 1.0:

This is a very breaking release, almost all values hash differently and the API has changed.
However, far fewer manual defintiions of `hash_method` become necessary. The fallback for
`Any` should handle many more cases. 

- **Breaking**: `transform` has been removed, its features are covered by `Use` and
  `UseAndReplaceContext`.
- **Breaking**: `stable_hash` no longer accepts mutliple objects to hash (wrap them in a
  tuple instead); it now accepts a single object to hash, and the second positional argument
  is the context (see below for details on contexts).
- **Deprecation**: The `Use` objects have changed quite a bit. You will
  need to replace the old names to avoid deprecation warnings:
    - Favor `UseStruct()` (which uses `fieldnames` instead of `propertynames`) 
      to `UseProperties()`.
    - *BUT* to reproduce `UseProperties()`, call `UseStruct(propertynames => getproperty)`
    - Replace `UseQualifiedName()` with `Use(qualified_name)`
    - Replace `UseSize` with `Use(size)`
    - Reaplce `UseTable` with `Use(Tables.columntable)`
- **Deprecation**: The fallback methods above are defined within a specific context
  (`HashContext{1}`). Any contexts you make should should define a
  `StableHashTraits.parent_context` method that returns e.g. `HashContext{1}` so that the
  fallback implementation for any methods of `hash_method` you don't implement work
  properly. (A default version of `parent_context` raises a deprecation warning and returns
  `HashContext{1}`). Refer to the discussion below about contexts.

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

## Customizing hash computations with contexts

You can customize how hashes are computed within a given scope using a context object. This
is also a very useful way to avoid type piracy. The context can be any object you'd like and
is passed as the second argument to `stable_hash`. By default it is equal to
`HashVersion{1}` and this is the context for which the default fallbacks listed above are
defined.

This context is then passed to both `hash_method` and `StableHashTraits.write` (the latter
is the method called for `UseWrite`, and falls back to `Base.write`). Because of the way the
default context (`HashVersion{1}`) is defined, you normally don't have to include this
context as an argument when you define a method of `hash_context` or `write` because there
are appropriate fallback methods.

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
    return UseQualifiedName(UseStruct(:ByName))
end
c = NamedTuplesEq(HashVersion{1}())
stable_hash((; a=1:2, b=1:2), c) == stable_hash((; b=1:2, a=1:2), c) # true
```

If we did not define a method of `parent_context`, our context would need to implement a
`hash_method` that covered the types `AbstractRange`, `Int64`, `Symbol` and `Pair` for the
call to `stable_hash` above to succeede.

### Customizing hashes within an object

Contexts can be customized not only when you call `stable_hash` but also when you hash the
contents of a particular object. This lets you change how hasing occurs within the object.
See the docstring of `UseAndReplaceContext` for details. 
