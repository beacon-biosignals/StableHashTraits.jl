# StableHashTraits

{INSERT_OVERVIEW}

## Basic Customization

You typically want to simply override a method of [`StableHashTraits.transformer`](@ref). This should return a function wrapped in a [`StableHashTraits.Transformer`](@ref) object that will be applied to an object and its result is the actual value that gets hashed.

{INSERT_EXAMPLE}

!!! note "Use `pick_fields` and `omit_fields`
    It is recommended you use [`pick_fields`](@ref) or [`omit_fields`](@ref) when you simply want to select some subset of fields to be hashed, as they allow for more optimized hashes than directly returning a named tuple of a field subset.

[`StableHashTraits.Transformer`](@ref) takes a second positional argument which is the `StructType` you wish to use on the transformed return value. By default `StructType` is applied to the result to determine this automatically, but in some cases it can be useful to modify this trait by passing a second argument (see the example below).

**To avoid StackOverflow errors** make sure you don't return the object itself as an element of some collection. It can be tempting to do e.g. `(mymetadata(x), x)` as a return value for `transformer`'s function. Instead you can use [`StableHashTraits.TransformIdentity`](@ref) to make sure this won't lead to an infinite regress: e.g. `(mymetadata(x), TransformIdentity(x))`. Using [`StableHashTraits.TransformIdentity`](@ref) will cause `x`'s transformed result to be `x` itself, thereby avoiding the infinite regress.

`transformer` customizes how the *content* of your object is hashed. The hash of the type and any structure is customized separately. If you wish to customize how the type of an object is hashed, read on.

## Using Contexts

Because not every package knows about either `StableHashTraits` or `StructTypes`, there may be types you don't own that you want to customize the hash of. In this scenario you should define a context object that you pass as the second argument to `stable_hash` and define a method of `transformer` that dispatches on this context object as its second argument.

A context is simply an arbitrary object that defines a method for
[`StableHashTraits.parent_context`](@ref). By default the context to `stable_hash` is
`HashVersion{version}()`. Because of `parent_context`, contexts can be stacked, and a
`HashVersion` should be at the bottom of the stack. There are fallback methods for
`transformer` that look at the value implemented by the parent context. In this way you need
only define methods for the types you want to customize.

For example, this customization makes the ordering of named tuple keys affect the hash value.

```@doctest
julia> begin
        @context NamedTuplesOrdered
        function transformer(::Type{<:NamedTuple}, ::NamedTuplesOrdered)
            Transformer(identity, StructTypes.OrderedStruct())
        end
        context = NamedTuplesOrdered(HashVersion{3}())
       end;

julia> stable_hash((; a=1:2, b=1:2), context) != stable_hash((; b=1:2, a=1:2), context)
true
```

Without this context, the keys are first sorted because `StructType(NamedTuple) isa StructType.UnorderedStruct`.

There are two useful, predefined contexts available in `StableHashTraits` that can be used to change how hashing works:

- [`WithTypeNames`](@ref)
- [`TablesEq`](@ref)

## Optimizing Transformers

By default, stable hash traits follows a safe, but slower code path for arbitrary functions passed to `Transformer`. However, in some cases it can use a faster code path, given that some assumptions about the types returned by the transforming function are maintained.
The `identity` function and the helper functions [`pick_fields`](@ref) and [`omit_fields`](@ref) use this faster code path by default.

In particular, a keyword argument to `Transformer`, `hoist_type` can be set to true to use this faster code path. Functions that implement `StableHashTraits.hoist_type(::typeof(fn))` can return `true` to signal that they are safe when using this faster code path.

You can always safely use `hoist_type=true` if the return value of your function maintains any of the field and element types of the input argument in the value it returns. For example, if a field has type `Any` and it is used to compute some part of the transformed value, than that part should also be of type `Any`.

This is because, when set to true, `hoist_type=true` hashes the type of the pre-transformed object, prior to looping over the contents of the post-transformed object: where the contents are the fields of a data type or the elements of an array or dict type. Once the contents of the object are being looped over, the hashing of each type of the elements or fields are skipped. For example, when hashing an `Array{Int}` the `Int` will only be hashed once, not once for every element.

This hoisting is only valid when the pre-transformed type is sufficient to disambiguate the hashed values that are produced downstream after transformation and when the post-transformed types that are concrete depend only on pre-transformed types that are themselves concrete. When `hoist_type=false` (the default for most functions) this signals that the type of the return value from `transformer` should be hashed alongside the transformed value, which is much slower, but ensures the that no unexpected hash collisions will occur.

### Examples

Most type-unstable functions are unsafe to use with `hoist_type=true`. For instance, the assmuptions of `hoist_type=true` would be violated by the function `x -> x < 0 : Char(0) ? Int32(0)`.

However, `x -> x < 0 : Char(1) : Int32(2)` is safe to use with `hoist_type=true`, since the byte sequence is unique irrespective of the type returned.

These two examples hopefully help to clarify when type-unstable functions can lead to incorrect hashes when `hoist_type=true`.

However type stable functions can also lead to invalid hashes with `hoist_type=true`. For example:

```julia
struct MyType
    a::Any
end
# ignore `metadata`, `data` will be hashed using fallbacks for `AbstractArray` type
# DO NOT DO IT THIS WAY; YOUR CODE WILL BE BUGGY!!!
StableHashTraits.transformer(::Type{<:MyType}) = Transformer(x -> (;x.a); hoist_type=true)
stable_hash(MyType(missing)) == stable_hash(MyType(nothing)) ## OOPS, we wanted these to be different but this returns `true`
```

Setting the flag to `hoist_type=true` here causes the type of the `missing` and `nothing` to be hoisted, since the field `a` is a concrete type in the return value of `Transformer`'s function. Since only the type of these two values is hashed, their hashes now collide. If the field of the pre-transformed type `a` was concrete, there wouldn't be any problem, because its type would be hashed, and would include either the `Missing` or `Nothing` type hash.

This is why `pick_fields` and `omit_fields` exist, to provide a way to select or remove fields from a type you want to transform that can safely use `hoist_type`.

```julia
struct MyType
    a::Any
end
# ignore `metadata`, `data` will be hashed using fallbacks for `AbstractArray` type
StableHashTraits.transformer(::Type{<:MyType}) = Transformer(x -> (;x.a); hoist_type=false)
stable_hash(MyType(missing)) != stable_hash(MyType(nothing)) ## this works

# NOTE: pick_fields sets `hoist_type=true` by default; it is set here to clearly illustrate
# what is happening.
StableHashTraits.transformer(::Type{<:MyType}) = Transformer(pick_fields(:a); hoist_type=true)
stable_hash(MyType(missing)) != stable_hash(MyType(nothing)) ## this also works and is faster than the previous implementation
```

## Customizing Type Hashes

Types are hashed by hashing the return value of [`transform_type`](@ref) when hashing an object's type and the return value of [`transform_type_value`](@ref) when hashing a type as a value (e.g. `stable_hash(Int)`). The docs for these functions provide several examples of their usage.

In addition there is some structure of the type that is always hashed:

- `fieldtypes(T)` of any `StructType.DataType` (e.g. StructType.Struct)
- `eltype(T)` of any `StructType.ArrayType` or `StructType.DictType` or `AbstractRange`

These get added internally so as to ensure that the type-hoisting describe above can rely on eltypes and fieldtypes storing all downstream children's concrete types.
