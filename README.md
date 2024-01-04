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
StableHashTraits.stable_hash(::MyType) = FnHash(x -> x.data) 
a = MyType(read("myfile.txt"), Dict{Symbol, Any}(:read => Dates.now()))
b = MyType(read("myfile.txt"), Dict{Symbol, Any}(:read => Dates.now()))
stable_hash(a; version=2) == stable_hash(b; version=2) # true
```

StableHashTraits aims to guarantee a stable hash so long as you only upgrade to non-breaking
versions (e.g. `StableHashTraits = "1"` in `[compat]` of `Project.toml`); any changes in an
object's hash in this case would be considered a bug.

> ⚠️ Julia 1.10 broke the stability of hashes in `StableHashTraits`; 1.1.4 corrects this
> bug. Please use version 1.1.4, or a higher version, when using Julia 1.10. More precisely:
> Hashes in 1 - 1.1.3 of StableHashTraits will generate the correct hashes on Julia 1.6 -
> 1.9 but an incorrect hash in 1.10. Hashes in 1.1.4 will generate the correct hash for
> Julia 1.6 - 1.10. (The cause of this bug was the change in the string representation
> named tuples, so any hashed objects that include the type of a named tuple changed).

## Why use `stable_hash` instead of `Base.hash`?

This package can be useful any time one of the following holds:

- you want to ensure the hash value will not change when you update Julia or start a new session
- you want to compute a hash for an object that does not have `hash` defined
- you want to customize how the hash works, within a specific scope

This is useful for content-addressed caching, in which e.g. some function of a value is stored at a location determined by a hash. Given the value, one can recompute the hash to determine where to look to see if the function evaluation on that value has already been cached.

## Details

You compute hashes using `stable_hash`. This is called on the object you want to hash, and
(optionally) a second argument called the context. The context you use affects how hashing
occurs (it defaults to `HashVersion{1}()`). It is generally recommended that you avoid
`HashVersion{1}()`, favoring `HashVersion{2}()` as it includes substantial speed
improvements. See the final section below for details on
how you can implement your own contexts. When you do not need to include a custom context, a short-hand for specifying
`HashVersion{2}()` is to call `stable_hash(x; version=2)`. 

There are sensible defaults for `stable_hash` that aim to ensure that if two values are
different, the input to the hash algorithm will differ. 

You can customize the hash behavior for particular types by implementing the trait
`StableHashTraits.hash_method`. It accepts the object you want to hash and, as an optional
second argument, the context. If you define a method that does not accept a context, it will
be used in all contexts. Any method of `hash_method` should simply return one of the
following values, typically based only on the *type* of its input.

<!-- The text between START_ and END_ comments are extracted from this readme and inserted into julia docstrings -->
<!-- START_HASH_TRAITS -->
1. `WriteHash()`: writes the object to a binary format using `StableHashTraits.write(io, x)`
    and takes a hash of that. `StableHashTraits.write(io, x)`
    falls back to `Base.write(io, x)` if no specialized methods are defined for x.
2. `IterateHash()`: assumes the object is iterable and finds a hash of all elements
3. `StructHash([pair = (fieldnames ∘ typeof) => getfield], [order])`: hash the structure of
    the object as defined by a sequence of pairs. How precisely this occurs is determined by
    the two arguments: 
      - `pair` Defines how fields are extracted; the default is 
        `fieldnames ∘ typeof => getfield` 
        but this could be changed to e.g. `propertynames => getproperty` or
        `Tables.columnnames => Tables.getcolumn`. The first element of the pair is a
        function used to compute a list of keys and the second element is a two argument
        function used to extract the keys from the object. 
      - `order` can be `:ByOrder` (the default)—which sorts by the order returned by
        `pair[1]`—or `:ByName`—which sorts by lexigraphical order.
4. `FnHash(fn, [method])`: hash the result of applying `fn` to the given object. Optionally,
   use `method` to hash the result of `fn`, otherwise calls `hash_method` on the result to
   determine how to hash it. There are two built-in functions commonly used with
   `FnHash`.
    - `stable_typename_id`: Get the qualified name of an object's type, e.g. `Base.String` and return 64 bit hash of this string
    - `stable_type_id`: Get the qualified name and type parameters of a type, e.g.
       `Base.Vector{Int}`, and return a 64 bit hash of this string.
5. `@ConstantHash(x)`: at compile time, hash the literal (constant) string or number using
    `sha256` and include the first 64 bits as a constant number that is recursively hashed
    using the `WriteHash` method.
6. `Tuple`: apply multiple methods to hash the object, and then recursively hash their
    results. For example: `(@ConstantHash("header"), StructHash())` would compute a hash for
    both the string `"header"` and the fields of the object, and then recursively hash
    these two hashes.

Your hash will be stable if the output for the given method remains the same: e.g. if
`write` is the same for an object that uses `WriteHash`, its hash will be the same; if the
fields are the same for `StructHash`, the hash will be the same; etc...

Missing from the above list is one final, advanced, trait: `HashAndContext` which can be used to change the context within the scope of a given object. You can learn more about contexts below.

<!-- END_HASH_TRAITS -->

## Breaking changes

### In 1.1

This release includes speed improvements of about 100 fold.

- **Feature**: `HashVersion{2}` is a new hash context that can be up to ~100x faster than
  `HashVersion{1}`.
- **Feature**: The requirements for `HashVersion{2}` on the passed hash function have been
  relaxed, such that `alg=crc32` should again work (no need to call `alg=(x,s=UInt32(0)) ->
  crc32c(copy(x),s)`).
- **Feature**: `@ConstantHash` allows for precomputed hash values of constant strings and
  numbers.
- **Feature**:  `stable_typename_id` and `stable_type_id` provide compile-time 64 bit hashes
  of the types of objects
- **Feature**: `root_version`: Most users can safely ignore this new function. If you are
  implementing a root context (one that returns `parent_context(::MyContext) = nothing`) you
  will need to define this function. It indicates what version of the hashing
  implementations to use (1 or 2). It defaults to 1 to avoid changing the hash values of
  existing root contexts, but should be defined to return 2 to make use of the more
  optimized implementations used by `HashVersion{2}`.
- **Deprecation**: `HashVersion{1}` has been deprecated, favor version 2 over 1 in all cases
  where backwards compatibility is not required.  
- **Deprecation**: `qualified_name` and `qualified_type` have been deprecated, in favor of
  `stable_typename_id` and `stable_type_id`.
- **Deprecation**: `ConstantHash` has been deprecated in favor of the more efficient
  `@ConstantHash`. To remove deprecated API: any call to `ConstantHash(x)` where `x` is
  a constant literal should be changed to `@ConstantHash(x)`. If `x` is an expression
  you can use `FnHash(_ -> x)` to achieve the same result. Note however that the use
  of a non-literal is probably a code smell, as `hash_method` should normally only
  depend on the type of its arguments.

### In 1.0:

This is a very breaking release, almost all values hash differently and the API has changed.
However, far fewer manual definitions of `hash_method` become necessary. The fallback for
`Any` should handle many more cases. 

- **Breaking**: `transform` has been removed, its features are covered by `FnHash` and
  `HashAndContext`.
- **Breaking**: `stable_hash` no longer accepts multiple objects to hash (wrap them in a
  tuple instead); it now accepts a single object to hash, and the second positional argument
  is the context (see below for details on contexts). 
- **Breaking**: The default `alg` for `stable_hash` is `sha256`; to use the old default
  (crc32c) you can pass `alg=(x,s=UInt32(0)) -> crc32c(copy(x),s)`.
- **Deprecation**: The traits to return from `hash_method` have changed quite a bit. You
  will need to replace the old names as follows to avoid deprecation warnings during your
  tests:
    - Favor `StructHash()` (which uses `fieldnames` instead of `propertynames`) 
      to `UseProperties()`.
    - *BUT* to reproduce `UseProperties()`, call `StructHash(propertynames => getproperty)`
    - Replace `UseQualifiedName()` with `FnHash(qualified_name, HashWrite())`
    - Replace `UseSize(method)` with `(FnHash(size), method)`
    - Replace `UseTable` with `FnHash(Tables.columns, StructHash(Tables.columnnames => Tables.getcolumn))`
- **Deprecation**: The fallback methods for hashing are defined within a specific
  context (`HashVersion{1}`). Any contexts you make should define a `parent_context`
  method that returns e.g. `HashVersion{1}` so that the fallback implementation for any
  methods of `hash_method` you don't implement work properly. (A default version of
  `parent_context` raises a deprecation warning and returns `HashVersion{1}`). Refer to the
  discussion below about contexts.

### In 0.3:

To prevent reshaped arrays from having the same hash (`stable_hash([1 2; 3 4]) ==
stable_hash(vec([1 2; 3 4]))`) the hashes for all arrays with more than 1 dimension have
changed.

### In 0.2:

To support hasing of all tables (`Tables.istable(x) == true`), hashes have changed for such
objects when:
   1. calling `stable_hash(x)` did not previously error
   1. `x` is not a `DataFrame` (these previously errored)
   2. `x` is not a `NamedTuple` of tables columns (these have the same hash as before)
   3. `x` is not an `AbstractArray` of `NamedTuple` rows (these have the same hash as before)
   4. `x` can be successfully written to an IO buffer via `Base.write` or
     `StableHashTraits.write` (otherwise it previously errored)
   5. `x` has no specialized `stable_hash` method defined for it (otherwise
   the hash will be the same)

Any such table now uses the method `UseTable`, rather than `UseWrite`, and so would have the
same hash as a `DataFrame` or `NamedTuple` with the same column contents instead of its
previous hash value. For example if you had a custom table type `MyCustomTable` for which
you only defined a `StableHashTraits.write` method and no `hash_method`, its hash will be
changed unless you now define `hash_method(::MyCustomTable) = UseWrite()`.

<!-- The text between START_ and END_ comments are extracted from this readme and inserted into julia docstrings -->
<!-- START_CONTEXTS -->
## Customizing hash computations with contexts

You can customize how hashes are computed within a given scope using a context object. This
is also a very useful way to avoid type piracy. The context can be any object you'd like and
is passed as the second argument to `stable_hash`. By default it is equal to
`HashVersion{1}()` and this determines how objects are hashed when a more specific method is not defined.

This context is then passed to both `hash_method` and `StableHashTraits.write` (the latter
is the method called for `WriteHash`, and falls back to `Base.write`). Because of the way
the root contexts (`HashVersion{1}` and `HashVersion{2}`) are defined, you normally don't
have to include this context as an argument when you define a method of `hash_context` or
`write` because there are appropriate fallback methods.

When you define a hash context it should normally accept a parent context that serves as a
fallback, and return it in an implementation of the method
`StableHashTraits.parent_context`. 

As an example, here is how we could write a context that treats all named tuples with the
same keys and values as equivalent. 

```julia
struct NamedTuplesEq{T}
    parent::T
end
StableHashTraits.parent_context(x::NamedTuplesEq) = x.parent
function StableHashTraits.hash_method(::NamedTuple, ::NamedTuplesEq) 
    return FnHash(stable_typename_id), StructHash(:ByName)
end
context = NamedTuplesEq(HashVersion{2}())
stable_hash((; a=1:2, b=1:2), context) == stable_hash((; b=1:2, a=1:2), context) # true
```

If we instead defined `parent_context` to return `nothing`, our context would need to
implement a `hash_method` that covered the types `AbstractRange`, `Int64`, `Symbol` and
`Pair` for the call to `stable_hash` above to succeed. 

### Customizing hashes within an object

Contexts can be customized not only when you call `stable_hash` but also when you hash the
contents of a particular object. This lets you change how hashing occurs within the object.
See the docstring of `HashAndContext` for details. 
<!-- END_CONTEXTS -->

## Hashing Gotchas

Numerical changes will, of course, change the hash. One way this can catch you off guard
are some differences in `StaticArray` outputs between julia versions:

```julia
julia> using StaticArrays, StableHashTraits;

julia> begin
        rotmatrix2d(a) = @SMatrix [cos(a) sin(a); -sin(a) cos(a)]
        rotate(a, p) = rotmatrix2d(a) * p 
        rotate((pi / 4), SVector{2}(0.42095778959006, -0.42095778959006))
    end;
```

In julia 1.9.4:

```julia

julia> bytes2hex(stable_hash(rotate((pi / 4), SVector{2}(0.42095778959006, -0.42095778959006)); version=2))
"4ccdc172688dd2b5cd50ba81071a19217c3efe2e3b625e571542004c8f96c797"

julia> rotate((pi / 4), SVector{2}(0.42095778959006, -0.42095778959006))
2-element SVector{2, Float64} with indices SOneTo(2):
  7.419375817039376e-17
 -0.5953242152248626
```

In julia 1.6.7

```julia
julia> bytes2hex(stable_hash(rotate((pi / 4), SVector{2}(0.42095778959006, -0.42095778959006)); version=2))
"3b8d998f3106c05f8b74ee710267775d0d0ce0e6780c1256f4926d3b7dcddf9e"

julia> rotate((pi / 4), SVector{2}(0.42095778959006, -0.42095778959006))
2-element SVector{2, Float64} with indices SOneTo(2):
  5.551115123125783e-17
 -0.5953242152248626
```
