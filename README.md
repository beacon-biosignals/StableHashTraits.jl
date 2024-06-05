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

Useres can define a method of `transformer` to customize how an object is hashed. It should return a function wrapped in `Transformer`. During hashing, this function is called and its result is the value that is actually hashed. (The `preserves_structure` keyword shown above is an optional flag that can be used to further optimize performance of your transformer in some cases; you can do this any time the function is type stable, but some type-unstable functions are also possible. See the documentation for details).

StableHashTraits aims to guarantee a stable hash so long as you only upgrade to non-breaking versions (e.g. `StableHashTraits = "1"` in `[compat]` of `Project.toml`); any changes in an object's hash in this case would be considered a bug.

> [!WARNING]
> Hash versions 3 constitutes a substantial redesign of StableHashTraits so as to avoid reliance on some unstable Julia internals. Hash versions 1 and 2 are deprecated and will be removed in a soon-to-be released StableHashTraits 2.0. Hash version 3 will remain unchanged in this 2.0 release. Hash version 1 is the default version if you don't specify a version.
You can read the documentation for hash version 1 [here](https://github.com/beacon-biosignals/StableHashTraits.jl/blob/v1.0.0/README.md) and hash version 2 [here](https://github.com/beacon-biosignals/StableHashTraits.jl/blob/v1.1.8/README.md).

<!--The START_ and STOP_ comments are used to extract content that is also repeated in the documentation-->
<!--START_OVERVIEW-->
## Use Case and Design Rationale

StableHashTraits is designed to be used in cases where there is an object you wish to serialize in a content-addressed cache. How and when objects pass the same input to a hashing algorithm is meant to be predictable and well defined, so that the user can reliably define methods of `transformer` to modify this behavior.

## What gets hashed? (hash version 3)

This describes what gets hashed when using the latest hash version. You can read the documentation for hash version 1 [here](https://github.com/beacon-biosignals/StableHashTraits.jl/blob/v1.0.0/README.md) and hash version 2 [here](https://github.com/beacon-biosignals/StableHashTraits.jl/blob/v1.1.8/README.md).

By default, an object is hashed according to its `StructType` (ala
[SructTypes](https://github.com/JuliaData/StructTypes.jl)), and this can usuablly be customized by writing a new method of
[`StableHashTraits.transformer`](https://beacon-biosignals.github.io/StableHashTraits.jl/stable/api/#StableHashTraits.transformer).

> [!NOTE]
> Hashing makes use of [`parentmodule_nameof`](https://beacon-biosignals.github.io/StableHashTraits.jl/stable/api/#StableHashTraits.parentmodule_nameof) and related functions; it generates `string(parentmodule(T)) * "." * string(nameof(T))` for type `T`, with a few additional regularizations to ensure e.g. `Core.` values become `Base.` values (as what is in `Core` vs. `Base` changes across julia versions). This function also ensures that no anonymous values (those that include `#`) are hashed, as these are not stable across sessions.

StableHashTraits breaks the hashing of each value into three distinct components:

**TODO**: maybe we can have just the single method `transformer` and `Transformer` accepts an optional argument that is a function of the type and its `StructType`. 🤔

- the value itself (see [`transformer`](https://beacon-biosignals.github.io/StableHashTraits.jl/stable/api/#StableHashTraits.transformer))
- the type identifier (see [`type_identifier`](https://beacon-biosignals.github.io/StableHashTraits.jl/stable/api/#StableHashTraits.type_identifier))
- the type structure (see [`type_structure`](https://beacon-biosignals.github.io/StableHashTraits.jl/stable/api/#StableHashTraits.type_structure))

For an object of type `T`, its hash normally depends on the value of `StructType(T)`.

### `StructType.DataType`

**TODO** rather than explaining everything at once, move some of these details
to parts of the documentation

Each field and fieldname of a datatype is hashed.

If the `StructType(T) <: StructTypes.UnorderedStruct`, the named and values are first sorted by the lexographic order of the `fieldnames`.

The type identifier of a data type is the string `nameof(T)`. The type structure consists of the type identifiers and type structure of each of the `fieldtypes` in the same order as the `fieldnames`.

If you wish to hash additional type parameters of your struct, you will have to do so by writing a method of [`type_structure](https://beacon-biosignals.github.io/StableHashTraits.jl/stable/api/#StableHashTraits.type_structure).

### `StructType.ArrayType`

Each element of an array type is hashed using `iterate`.

If [`StableHashTraits.is_ordered`](https://beacon-biosignals.github.io/StableHashTraits.jl/stable/api/#StableHashTraits.is_ordered) returns `false` the elements are first `sort`ed according to [`StableHashTraits.hash_sort_by`](https://beacon-biosignals.github.io/StableHashTraits.jl/stable/api/#StableHashTraits.hash_sort_by).

The type identifier of an array is the string `StructType.ArrayType`. The type structure of any `ArrayType` is a hash of the `eltype`'s type identifier and type structure.

In addition, if `T <: AbstractArray` the `size(x)` is considered part of the value, and the type structure includes `ndims(T)` if it is defined.

### `StructTypes.DictType`

Each key-value pair of a dict type is hashed, as returned by `StructType.keyvaluepairs(x)`.

If [`StableHashTraits.is_ordered`](https://beacon-biosignals.github.io/StableHashTraits.jl/stable/api/#StableHashTraits.is_ordered) returns `false` the pairs are first `sort`ed according their keys using [`StableHashTraits.hash_sort_by`](https://beacon-biosignals.github.io/StableHashTraits.jl/stable/api/#StableHashTraits.hash_sort_by).

The type identifier of a dictionary is the string `StructType.DictType`. The type structure of any `DictType` is a hash of the `eltype`'s type identifier and type structure.

### `AbstractRange`

For efficient hashing, ranges are treated as another first-class container object, separate from dict and array types. For an `x isa AbstractRange`, the value is hashed as `(first(x), step(x), last(x))`, its type identifier is the string `Base.AbstractRange` and its type structure is the identifier and structure of its `eltype`.

### `StructTypes{Number/String/Bool}Type`

When `StructType(T)` is any of `StructType.NumberType`, `StructType.StringType`, `StructType.BoolType`, the result of `Base.write`ing these values is hashed. The type identifier is `parentmodule_nameof(StructType(T))` and there is no type structure.

### `StructType.CustomStruct`

For any `StructType.CustomStruct`, the object is first `StructType.lower`ed and the result is hashed according to the lowered `StructType`.

### `missing` and `nothing`

There is no value hashed for `missing` or `nothing`; the type identifier is `Base.Missing` and `Base.Nothing` respectively and there is no type structure.

### `StructType.{Null/Singleton}Type`

These types error by default. You can opt in to behavior similar to `missing` and `nothing` by defining an appropriate [`type_identifier`](https://beacon-biosignals.github.io/StableHashTraits.jl/stable/api/#StableHashTraits.type_identifier).

If the type identifier for a singleton is defined, it will no longer error, as the the type structure and value are already defined to be empty.

### `Function`

Attempting to hash a function errors by default. You can opt in to hashing a function
by defining its `type_identifier`. By default functions hash as if they were `UnorderedStructs`: functions can have fields if they are curried (e.g. `==(2)`), and
so, for this reason, the fields are included in the hash by default.

If a function value `fn` can be hashed in this way, so can values of `typeof(fn)`.

> [!WARNING]
> This behavior is opt-in to signal to the user is responsible for ensuring the stability of these hashes. A more generic method, operating over many types, could easily lead to hash instabilitys when non-breaking, internal changes are made (e.g. by changing in which module a type is defined in). If the user does not require such guarantees they can define a short, generic method for all types of interest within a specific hash context; this behavior then only affects the hashes where this specific context is used.

### `Type`

When a type is provided as a value (e.g. `Ref(Int)`) hashing it will error by default.

Hashing a type as a value is a bit of a special case that requires care to avoid a stack overflow. You can opt in to hashing of a type as a value, hashing its identifier and its type structure by defining [`type_value_identifier`](https://beacon-biosignals.github.io/StableHashTraits.jl/stable/api/#StableHashTraits.type_value_identifier) as follows, for your type.

```julia
struct MyType end
StableHashTraits.type_value_identifier(::Type{T}, ::StructType.DataType) where {T <: MyType} = parentmodule_nameof(T)
stable_hash(Ref(MyType)) # does not error
```

If your type has structure (e.g. fieldtypes) the types contained by your type must also
have appropriate methods defined for `type_value_identifier`.

Likewise, you can opt in to this behavior for a type you don't own by defining a context.

```julia
StableHashTraits.@context HashNumberTypes
function StableHashTraits.type_value_identifier(::Type{T}, ::StructType.NumberType,
                                                ::HashNumberTypes)
    return parentmodule_nameof(T)
end
stable_hash(Ref(Int), HashNumberTypes(HashVersion{3}()))
```

> [!WARNING]
> This behavior is opt-in to signal to the user is responsible for ensuring the stability of these hashes. A more generic method, operating over many types, could easily lead to hash instabilitys when non-breaking, internal changes are made (e.g. by changing in which module a type is defined in). If the user does not require such guarantees they can define a short, generic method for all types of interest within a specific hash context; this behavior then only affects the hashes where this specific context is used.

## Examples

All of the following hash examples follow directly from the definitions above, but may not be so obvious to the reader.

Most of the behaviors described below can be customized/changed by using your own hash context, which can be passed as the second argument to [`stable_hash`](https://beacon-biosignals.github.io/StableHashTraits.jl/stable/api/#StableHashTraits.stable_hash).

The order of NamedTuple pairs does not matter

```julia
stable_hash((;a=1,b=2); version=3) == stable_hash((;b=2,a=1); version=3)
```

Two structs with the same fields hash equivalently

```julia
struct X
    bar::Int
    foo::Float64
end

struct Y
    foo::Float64
    bar::Int
end

stable_hash(X(2, 1); version=3) == stable_hash(Y(1, 2); version=3)
```

Different array types with the same content hash to the same value.

```julia
stable_hash(view([1,2,3], 1:2); version=3) == stable_hash([1,2]; version=3)
```

Byte equivalent arrays of all `NumberType` values will hash to the same value.

```julia
stable_hash([0.0, 0.0]; version=3) == stable_hash([0, 0]; version=3)
```

But if the eltype has a different `StructType`, or if the bytes are different, the collision will not occur.

```julia
stable_hash(Any[0.0, 0.0]; version=3) != stable_hash([0, 0]; version=3)
stable_hash([1.0, 2.0]; version=3) != stable_hash([1, 2]; version=3)
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

julia> bytes2hex(stable_hash(rotate((pi / 4), SVector{2}(0.42095778959006, -0.42095778959006)); version=3))
"4ccdc172688dd2b5cd50ba81071a19217c3efe2e3b625e571542004c8f96c797"

julia> rotate((pi / 4), SVector{2}(0.42095778959006, -0.42095778959006))
2-element SVector{2, Float64} with indices SOneTo(2):
  7.419375817039376e-17
 -0.5953242152248626
```

In julia 1.6.7

```julia
julia> bytes2hex(stable_hash(rotate((pi / 4), SVector{2}(0.42095778959006, -0.42095778959006)); version=3))
"3b8d998f3106c05f8b74ee710267775d0d0ce0e6780c1256f4926d3b7dcddf9e"

julia> rotate((pi / 4), SVector{2}(0.42095778959006, -0.42095778959006))
2-element SVector{2, Float64} with indices SOneTo(2):
  5.551115123125783e-17
 -0.5953242152248626
```

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
