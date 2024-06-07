# StableHashTraits

{INSERT_OVERVIEW}

## Basic Customization

You typically want to simply override a method of [`StableHashTraits.transformer`](@ref). This should return a function wrapped in a [`StableHashTraits.Transformer`](@ref) object that will be applied to an object and its result is the actual value that gets hashed.

{INSERT_EXAMPLE}

In this example we also optimize our hash by setting `hoist_type=true`. You can do this any time your function is type stable, but there are additional conditions under which you can still set this flag to true, discussed below.

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

As noted, `hoist_type` can safely be set to true for any type-stable function. It is set to
true by default for `identity`. When set to true, `stable_hash` will hoist the type of the
pre-transformed object outside of loops when possible, avoiding type hashes for any deeply
nested fields, so long as the path to them includes all concrete types. For example, when
hashing an `Array{Int}` the `Int` will only be hashed once, not once for every element.

This hoisting is only valid when the pre-transformed type is sufficient to disambiguate the the hashed values that are produced downstream after transformation. When `hoist_type=false` (the default for most functions) this signals that the type of the return value from `transformer` should be hashed alongside the transformed value, which is much slower, but ensures the that no unexpected hash collisions will occur.

This should give the reader some idea of when a type-unstable function can be safely marked as `hoist_type=true`. In particular any case where each value passed to transform maps to a value that will ultimately be hashed as a unique bit-sequence should be fine. This would be violated, for instance, by `x -> x < 0 : Char(0) ? Int32(0)`, but not by `x -> x < 0 : Char(1) : Int32(2)`. In the latter case we could safely mark `hoist_type=true`.

## Customizing Type Hashes

Types are hashed by hashing the return value of [`transform_type`](@ref) when hashing an object's type and the return value of [`transform_type_value`](@ref) when hashing a type as a value (e.g. `stable_hash(Int)`).

In addition there is some structure of the type that is always hashed:

- `fieldtypes(T)` of any `StructType.DataType` (e.g. StructType.Struct)
- `eltype(T)` of any `StructType.ArrayType` or `StructType.DictType` or `AbstractRange`

These get added internally so as to ensure that the type-hoisting describe above can rely on eltypes and fieldtypes storing all downstream children's concrete types.
