# StableHashTraits

[![Project Status: Active – The project has reached a stable, usable state and is being actively developed.](https://www.repostatus.org/badges/latest/active.svg)](https://www.repostatus.org/#active)
[![GitHub Actions](https://github.com/beacon-biosignals/StableHashTraits.jl/workflows/CI/badge.svg)](https://github.com/beacon-biosignals/StableHashTraits.jl/actions/workflows/CI.yml)
[![docs](https://img.shields.io/badge/docs-dev-blue.svg)](https://beacon-biosignals.github.io/StableHashTraits.jl/dev)
[![docs](https://img.shields.io/badge/docs-stable-blue.svg)](https://beacon-biosignals.github.io/StableHashTraits.jl/stable)
[![codecov](https://codecov.io/gh/beacon-biosignals/StableHashTraits.jl/branch/main/graph/badge.svg?token=4O1YO0GMNM)](https://codecov.io/gh/beacon-biosignals/StableHashTraits.jl)
[![Code Style: YASGuide](https://img.shields.io/badge/code%20style-yas-violet.svg)](https://github.com/jrevels/YASGu)

The aim of StableHashTraits is to make it easy to compute a stable hash of any Julia value with minimal boilerplate using trait-based dispatch; here, "stable" means the value will not change across Julia versions (or between Julia sessions).

For example:

<!--The START_ and STOP_ comments are used to extract content that is also repeated in the documentation-->
<!--START_EXAMPLE-->
```julia
using StableHashTraits
using StableHashTraits: Transformer
using Dates

struct MyType
   data::Vector{UInt8}
   metadata::Dict{Symbol, Any}
end
# ignore `metadata`, `data` will be hashed using fallbacks for `AbstractArray` type
StableHashTraits.transformer(::Type{<:MyType}) = Transformer(x -> (; x.data);
                                                             preserves_structure=true)
a = MyType(read("myfile.txt"), Dict{Symbol, Any}(:read => Dates.now()))
b = MyType(read("myfile.txt"), Dict{Symbol, Any}(:read => Dates.now()))
stable_hash(a; version=3) == stable_hash(b; version=3) # true
```
<!--END_EXAMPLE-->

Useres can define a method of `transformer` to customize how an object is hashed. It should return a function wrapped in `Transformer`. During hashing, this function is called and its result is the value that is actually hashed. (The `preserves_structure` keyword shown above is an optional flag that can be used to further optimize performance of your transformer in some cases; you can do this any time the function is type stable, but some type-instable functions are also possible. See the documentation for details).

StableHashTraits aims to guarantee a stable hash so long as you only upgrade to non-breaking versions (e.g. `StableHashTraits = "1"` in `[compat]` of `Project.toml`); any changes in an object's hash in this case would be considered a bug.

> ⚠️ Hash versions 3 constitutes a substantial redesign of StableHashTraits so as to avoid reliance on some unstable Julia internals. Hash versions 1 and 2 are deprecated and will be removed in a soon-to-be released StableHashTraits@2.0. Hash version 3 will remain unchanged in this 2.0 release. Hash version 1 is the default version if you don't specify a version.

<!--The START_ and STOP_ comments are used to extract content that is also repeated in the documentation-->
<!--START_OVERVIEW-->
## Use Case and Design Rationale

StableHashTraits is designed to be used in cases where there is an object you wish to serialize in a content-addressed cache. How and when objects pass the same input to a hashing algorithm is meant to be predictable and well defined, so that the user can reliably define methods of `transformer` to modify this behavior.

## What gets hashed?

By default, an object is hashed according to its `StructType` (ala
[SructTypes](https://github.com/JuliaData/StructTypes.jl)), and this can be customized using
[`StableHashTraits.transformer`](https://beacon-biosignals.github.io/StableHashTraits.jl/stable/api/#StableHashTraits.transformer).

Hashing makes use of [`stable_type_name`](https://beacon-biosignals.github.io/StableHashTraits.jl/stable/api/#StableHashTraits.stable_type_name) which generates `string(parentmodule(T)) * "." * string(nameof(T))` for type `T`, with a few additional regularizations to ensure e.g. `Core.` values become `Base.` values (as what is in `Core` vs. `Base` changes across julia versions). This function also ensures that no anonymous values (those that include `#`) are hashed, as these are not stable across sessions.

- `Type`: when hashing the type of an object or its contained types, only the name of `stable_type_name(StructType(T))` is hashed along with any structure as determined by the particular return value of `StructType(T)` (e.g. `eltype` for `ArrayType`). If you hash a type as a value (e.g. `stable_hash(Int)`) the `stable_type_name` of the type itself, rather than `StructType(T)` is used.

- `StructType.DataType` — the `fieldnames`, `fieldtypes` and the field values are hashed, and if this is a `StructType.UnorderedStruct` those are all sorted in lexicographic order of the fieldnames. `StructType.UnorderedStruct` is the default struct-type trait so this is how most objects get hashed.

- `StructType.ArrayType` — the `eltype` is hashed and elements are hashed using `iterate`.
If [`StableHashTraits.is_ordered`](https://beacon-biosignals.github.io/StableHashTraits.jl/stable/api/#StableHashTraits.is_ordered) returns `false` the elements are first `sort`ed according to [`StableHashTraits.hash_sort_by`](https://beacon-biosignals.github.io/StableHashTraits.jl/stable/api/#StableHashTraits.hash_sort_by).

- `StructType.DictType` — the `eltype` of the keys and values are hashed by iterating over `StructTypes.keyvaluepairs`. If [`StableHashTraits.is_ordered`](https://beacon-biosignals.github.io/StableHashTraits.jl/stable/api/#StableHashTraits.is_ordered) returns `false` the pairs of the dictionary are first `sort`ed according their keys using [`StableHashTraits.hash_sort_by`](https://beacon-biosignals.github.io/StableHashTraits.jl/stable/api/#StableHashTraits.hash_sort_by).

- `StructType.CustomStruct` - the object is first `StructType.lower`ed and the result is hashed according to its `StructType`.

- `StructType.NullType`, `StructType.SingletonType`: in these cases the `stable_type_name` of the type `T` is hashed rather than `StructType(T)`

- `StructType.NumberType`, `StructType.StringType`, `StructType.BoolType`: the the type of the object is hashed along with its bytes

- `Function`: functions are a special case and their `stable_type_name` is hashed along with their fieldnames, fieldtypes and fieldvalues. Functions have fields when they are curried, e.g. `==(2)` or when they are defined via a `struct` definition.

- `AbstractRange`: though their `StructType` is `AbstractArray`, abstract ranges are treated as `UnorderedStruct` objects for purposes of hashing, as this normally leads to a more effeicient hash computation.

- `AbstractArray`: in addition to hashing the `eltype`, any abstract array type with a
concrete dimension (`AbstractArray{<:Any, 3}` but not `AbstractArray{Int}`) will hash
this dimension. The size of an array is hashed along with the array contents.

> [!WARNING]
> Some type parameters are ignored by this hashing scheme; specifically, the only parameters hashed are those specified above. This means, for example, that a parameter not included in `fieldtype(T)` for `StructType(T) == StructTypes.Struct` will be ignored during hashing. You can use [`StableHashTraits.type_structure`](https://beacon-biosignals.github.io/StableHashTraits.jl/stable/api/#StableHashTraits.type_structure) to explicitly hash additional type parameters for a type.
<!--END_OVERVIEW-->

## Breaking changes

### In 1.2

This release includes a new hash version 3 that has breaking API changes, documeted above. The prior API is deprecated. In version 2, which will be released in relatively short order, only hash version 3 will be available

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

<!--TODO: move this to docs-->
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
