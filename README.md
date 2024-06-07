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
                                                             hoist_type=true)
a = MyType(read("myfile.txt"), Dict{Symbol, Any}(:read => Dates.now()))
b = MyType(read("myfile.txt"), Dict{Symbol, Any}(:read => Dates.now()))
stable_hash(a; version=4) == stable_hash(b; version=4) # true
```
<!--END_EXAMPLE-->

Useres can define a method of `transformer` to customize how an object is hashed. It should return a function wrapped in `Transformer`. During hashing, this function is called and its result is the value that is actually hashed. (The `hoist_type` keyword shown above is an optional flag that can be used to further optimize performance of your transformer in some cases; you can do this any time the function is type stable, but some type-unstable functions are also possible. See the documentation for details).

StableHashTraits aims to guarantee a stable hash so long as you only upgrade to non-breaking versions (e.g. `StableHashTraits = "1"` in `[compat]` of `Project.toml`); any changes in an object's hash in this case would be considered a bug.

> [!WARNING]
> Hash versions 4 constitutes a substantial redesign of StableHashTraits so as to more conservatively avoid realiance on the internals of julia and packages. Hash versions 1-3 are deprecated and will be removed in a soon-to-be released StableHashTraits 2.0. Hash version 4 will remain unchanged in this 2.0 release. Hash version 1 is the default version if you don't specify a version. You can read the documentation for hash version 1 [here](https://github.com/beacon-biosignals/StableHashTraits.jl/blob/v1.0.0/README.md) and hash version 2 [here](https://github.com/beacon-biosignals/StableHashTraits.jl/blob/v1.1.8/README.md).

<!--The START_ and STOP_ comments are used to extract content that is also repeated in the documentation-->
<!--START_OVERVIEW-->
## Use Case and Design Rationale

StableHashTraits is designed to be used in cases where there is an object you wish to serialize in a content-addressed cache. How and when objects pass the same input to a hashing algorithm is meant to be predictable and well defined, so that the user can reliably define methods of `transformer` to modify this behavior.

## What gets hashed? (hash version 4)

This covers the behavior when using the latest hash version (4). You can read the documentation for hash version 1 [here](https://github.com/beacon-biosignals/StableHashTraits.jl/blob/v1.0.0/README.md) and hash version 2 [here](https://github.com/beacon-biosignals/StableHashTraits.jl/blob/v1.1.8/README.md).

When you call `stable_hash(x; version=4)`, StableHashTraits hashes both the value `x` and its type `T`, normally doing so according to `StructType(T)`. (ala
[SructTypes](https://github.com/JuliaData/StructTypes.jl)).

You can customize how the value is hashed using [`StableHashTraits.transformer`](https://beacon-biosignals.github.io/StableHashTraits.jl/stable/api/#StableHashTraits.transformer),
and how the type is hashed using [`StableHashTraits.transform_type`](https://beacon-biosignals.github.io/StableHashTraits.jl/stable/api/#StableHashTraits.transform_type).
If you need to customize either of these functions for a type that you don't own, you can use a [@context](https://beacon-biosignals.github.io/StableHashTraits.jl/stable/api/#StableHashTraits.@context)

### `StructType.DataType`

To hash the value, each field value of a data type is hashed.

If `StructType(T) <: StructTypes.UnorderedStruct`, the values are first sorted by the lexographic order of the fieldnames.

The type of a data type is hashed as `string(nameof(T))`, the `fieldnames(T)`, (sorting them if for `UnorderedStruct`), and hash the type of each element of `fieldtypes(T)` according to their `StructType`.

No type parameters are hashed by default. To hash these you need to specialize on [`transform_type`](https://beacon-biosignals.github.io/StableHashTraits.jl/stable/api/#StableHashTraits.transform_type) for your struct. Note that because `fieldtypes(T)` is hashed, you don't need to do this unless your type parameters are not used in the specification of your field types.

### `StructType.ArrayType`

To hash the value, each element of an array type is hashed using `iterate`. If the object `isa AbstractArray`, the `size(x)` of the object is also hashed.

If [`StableHashTraits.is_ordered`](https://beacon-biosignals.github.io/StableHashTraits.jl/stable/api/#StableHashTraits.is_ordered) returns `false` the elements are first `sort`ed according to [`StableHashTraits.hash_sort_by`](https://beacon-biosignals.github.io/StableHashTraits.jl/stable/api/#StableHashTraits.hash_sort_by).

To hash the type, the string `"StructTypes.ArrayTYpe"` is hashed (ergo, the kind of array won't matter), and the type of the `elype` is hashed, according to its `StructType`. If the type `<: AbstractArray`, the `ndims(T)` is hashed if it is available.

### `StructTypes.DictType`

To hash the value, each key-value pair of a dict type is hashed, as returned by `StructType.keyvaluepairs(x)`.

If [`StableHashTraits.is_ordered`](https://beacon-biosignals.github.io/StableHashTraits.jl/stable/api/#StableHashTraits.is_ordered) returns `false` the pairs are first `sort`ed according their keys using [`StableHashTraits.hash_sort_by`](https://beacon-biosignals.github.io/StableHashTraits.jl/stable/api/#StableHashTraits.hash_sort_by).

To hash the type `"StructTypes.DictType"` is hashed (ergo, the kind of dictionary won't matter), and the type of the `keytype` and `valtype` is hashed, according to its `StructType`.

### `AbstractRange`

`AbbstractRange` constitutes an exception to the rule that we use `StructType`: for efficient hashing, ranges are treated as another first-class container object, separate from array types.

The value is hashed as `(first(x), step(x), last(x))`.

The type is hashed as `"Base.AbstractRange"` along with the type of the `eltype`, according to its `StructType`. Ergo, the type of range doesn't matter (just that it is a range).

### `StructTypes{Number/String/Bool}Type`

To hash the value, the result of `Base.write`ing the object is hashed.

To hash the type, the value of `module_nameof_string(StructType))` is used. [`module_nameof_string`](https://beacon-biosignals.github.io/StableHashTraits.jl/stable/api/#StableHashTraits.parentmodule_name) can be used to provide a relatively stable name for an object composed of `string(parentmodule(T))` and `string(nameof(T))`, along with some additional regularizations and validations.

### `StructType.CustomStruct`

For any `StructType.CustomStruct`, the object is first `StructType.lower`ed and the result is hashed according to the lowered `StructType`.

### `missing` and `nothing`

There is no value hashed for `missing` or `nothing`; the type is hashed as the string `"Base.Missing"` and `"Base.Nothing"` respectively.

### `StructType.{Null/Singleton}Type`

These types error by default. You can opt in to behavior similar to `missing` and `nothing` by defining an appropriate [`transform_type`](https://beacon-biosignals.github.io/StableHashTraits.jl/stable/api/#StableHashTraits.type_identifier).

If `transform_type` for a singleton is defined, it will no longer error as the value is already defined to be empty.

### `Function`

Attempting to hash a function errors by default. You can opt in to hashing a function
by defining [`transform_type`](https://beacon-biosignals.github.io/StableHashTraits.jl/stable/api/#StableHashTraits.type_identifier). If `transform_type` is defined, functions will hash as if they were `UnorderedStructs`: functions can have fields if they are curried (e.g. `==(2)`), and so, for this reason, the fields are included in the hash by default.

If a function value `fn` can be hashed in this way, so can types of the form `typeof(fn)`.

### `Type`

When a type is provided as a value (e.g. `stable_hash(Int; version=4)`) hashing it will error by default.

You can opt in to hashing a given type as a value by defining [`transform_type_value`](https://beacon-biosignals.github.io/StableHashTraits.jl/stable/api/#StableHashTraits.transform_type_value) for your type.

## Examples

All of the following hash examples follow directly from the definitions above, but may not be so obvious to the reader.

Most of the behaviors described below can be customized/changed by using your own hash [`@context`](https://beacon-biosignals.github.io/StableHashTraits.jl/stable/api/#StableHashTraits.@context), which can be passed as the second argument to [`stable_hash`](https://beacon-biosignals.github.io/StableHashTraits.jl/stable/api/#StableHashTraits.stable_hash).

The order of NamedTuple pairs does not matter

```julia
stable_hash((;a=1,b=2); version=4) == stable_hash((;b=2,a=1); version=4)
```

Two structs with the same fields and name hash equivalently

```julia
module A
    struct X
        bar::Int
        foo::Float64
    end
end

module B
    struct X
        foo::Float64
        bar::Int
    end
end

stable_hash(B.X(2, 1); version=4) == stable_hash(A.X(1, 2); version=4)
```

Different array types with the same content hash to the same value.

```julia
stable_hash(view([1,2,3], 1:2); version=4) == stable_hash([1,2]; version=4)
```

Byte equivalent arrays of all `NumberType` values will hash to the same value.

```julia
stable_hash([0.0, 0.0]; version=4) == stable_hash([0, 0]; version=4)
```

But if the eltype has a different `StructType`, or if the bytes are different, the collision will not occur.

```julia
stable_hash(Any[0.0, 0.0]; version=4) != stable_hash([0, 0]; version=4)
stable_hash([1.0, 2.0]; version=4) != stable_hash([1, 2]; version=4)
```

Two types with the same name but different type parameters will hash the same unless your
`transform_type_value` method includes those type parameters in its return value.

```julia
struct MyType{T} end
StableHashTraits.transform_type_value(::Type{T}) where {T<:MyType} = module_nameof_string(T)
stable_hash(MyType{:a}) == stable_hash(MyType{:b}) # true
```

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

julia> bytes2hex(stable_hash(rotate((pi / 4), SVector{2}(0.42095778959006, -0.42095778959006)); version=4))
"4ccdc172688dd2b5cd50ba81071a19217c3efe2e3b625e571542004c8f96c797"

julia> rotate((pi / 4), SVector{2}(0.42095778959006, -0.42095778959006))
2-element SVector{2, Float64} with indices SOneTo(2):
  7.419375817039376e-17
 -0.5953242152248626
```

In julia 1.6.7

```julia
julia> bytes2hex(stable_hash(rotate((pi / 4), SVector{2}(0.42095778959006, -0.42095778959006)); version=4))
"3b8d998f3106c05f8b74ee710267775d0d0ce0e6780c1256f4926d3b7dcddf9e"

julia> rotate((pi / 4), SVector{2}(0.42095778959006, -0.42095778959006))
2-element SVector{2, Float64} with indices SOneTo(2):
  5.551115123125783e-17
 -0.5953242152248626
```

<!--END_OVERVIEW-->

## Breaking changes

### In 1.3

This release includes a new hash version 4 that has breaking API changes, documeted above. The prior API is deprecated. In version 2 of StableHashTraits, which will be released in relatively short order, only hash version 4 will be available.

### In 1.2

This release includes a bugfix to `stable_type_id` and the underlying hashes that depend on it (true for most types). This bug caused `stable_type_id` to yield a different value depending on the scope in which `stable_type_id` was first called for a given type. Now that 1.3 is available, 1.2 should not be used, as it addresses the same bug with a better API, rather than the hotfix applied here.

1.2 provides defines hash version 3, which uses a fixed version of `stable_type_id` that can be used by leveraging hash version 3. E.g. if you call `stable_hash(x, version=3)` or use `HashVersion{3}()` where you would have used `HashVersion{2}()` you will not be susceptible to the bug. If you make use of `stable_type_id` directly and want to avoid this bug, you should use `StableHashTraits.stable_type_id_fixed`.

Because existing uses of `StableHashTraits` might depend on the extant, broken behavior, versions 1 and 2 of hashing remain unchanged.

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
