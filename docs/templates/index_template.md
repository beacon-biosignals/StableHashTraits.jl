# StableHashTraits

{INSERT_OVERVIEW}

## Basic Customization

You typically want to simply override a method of [`StableHashTraits.transformer`](@ref). This should return a function wrapped in a [`StableHashTraits.Transformer`](@ref) object that will be applied to an object and its result is the actual value that gets hashed.

{INSERT_EXAMPLE}

!!! note "Use `pick_fields` and `omit_fields`
    It is recommended you use [`pick_fields`](@ref) or [`omit_fields`](@ref) when you simply want to select some subset of fields to be hashed, as they allow for more optimized hashes than directly returning a named tuple of a field subset.

[`StableHashTraits.Transformer`](@ref) takes a second positional argument which is the `StructType` you wish to use on the transformed return value. By default `StructType` is applied to the result to determine this automatically, but in some cases it can be useful to modify this trait by passing a second argument (see the example below).

**To avoid StackOverflow errors** make sure you don't return the object itself as an element of some collection. It can be tempting to do e.g. `(mymetadata(x), x)` as a return value for `transformer`'s function. Instead you can use [`StableHashTraits.TransformIdentity`](@ref) to make sure this won't lead to an infinite regress: e.g. `(mymetadata(x), TransformIdentity(x))`. Using [`StableHashTraits.TransformIdentity`](@ref) will cause `x`'s transformed result to be `x` itself, thereby avoiding the infinite regress.

`transformer` customizes how the *content* of your object is hashed. The hash of the type is customized separately using [`transform_type`](@ref).

## Using Contexts

Because not every package knows about either `StableHashTraits` or `StructTypes`, there may be types you don't own that you want to customize the hash of. In this scenario you should define a context object that you pass as the second argument to `stable_hash` and define a method of `transformer` that dispatches on this context object as its second argument.

A context is simply an arbitrary object that defines a method for [`StableHashTraits.parent_context`](@ref). By default the context to `stable_hash` is `HashVersion{version}()`. Because of `parent_context`, contexts can be stacked, and a `HashVersion` should be at the bottom of the stack. There are fallback methods for `transformer` that look at the value implemented by the parent context. In this way you need only define methods for the types you want to customize.

For example, this customization makes the ordering of named tuple keys affect the hash value.

```@doctest
julia> begin
        sturct NamedTuplesOrdered{T}
            parent::T
        end
        StableHashTraits.parent_context(x::NamedTuplesOrdered) = x.parent
        function transformer(::Type{<:NamedTuple}, ::NamedTuplesOrdered)
            Transformer(identity, StructTypes.OrderedStruct())
        end
        context = NamedTuplesOrdered(HashVersion{4}())
       end;

julia> stable_hash((; a=1:2, b=1:2), context) != stable_hash((; b=1:2, a=1:2), context)
true
```

Without this context, the keys are first sorted because `StructType(NamedTuple) isa StructType.UnorderedStruct`.

As a short hand you can use [`StableHashTraits.@context`](@ref) for creating simple contexts, like the one above.

There are several useful, predefined contexts available in `StableHashTraits` that can be used to change how hashing works:

- [`WithTypeNames`](@ref)
- [`TablesEq`](@ref)
- [`HashFunctions`](@ref)
- [`HashNullTypes`](@ref)
- [`HashSingletonTypes`](@ref)

## Optimizing Transformers

By default, stable hash traits follows a safe, but slower code path for arbitrary functions passed to `Transformer`. However, in some cases it can use a faster code path, given that some assumptions about the types returned by the transforming function are maintained.
The `identity` function and the helper functions [`pick_fields`](@ref) and [`omit_fields`](@ref) use this faster code path by default.

In particular, a keyword argument to `Transformer`, `hoist_type` can be set to true to use this faster code path. Functions that implement `StableHashTraits.hoist_type(::typeof(fn))` can return `true` to signal that they are safe when using this faster code path. This function is called to determine the default value of the keyword argument `hoist_type` of `Transformer`.

The exact criteria for when this code path is unsafe are complex, and will be describe below, along with some examples. However, you can always safely use `hoist_type=true` either when the function *always* returns the same type (e.g. it transforms all inputs into `String` values) OR when the following three criteria are met:

1. The type that `transformer` dispatches on is concrete.
2. The type that `transformer` dispatches on contains no abstract types: that is, for any contained array type or dict types have, their eltypes are concrete and any contained data type has concrete `fieldtypes`.
3. The function you pass to `Transformer` is type stable

When set to true, `hoist_type=true` hashes the type of the pre-transformed object, prior to looping over the contents of the post-transformed object: its fields (for a data type) or the elements (for an array or dict type). Once the contents of the object are being looped over, the hashing of each concrete-typed elements or fields are skipped. For example, when hashing an `Array{Int}` the `Int` will only be hashed once, not once for every element.

When `hoist_type=false` (the default for most functions) the type of the return value from `transformer` is hashed alongside the transformed value. This can be a lot slower, but ensures the that no unexpected hash collisions will occur.

More precisely, this hoisting is only valid when one of these two criteria are satisfied:

1. the pre-transformed type is sufficient to disambiguate the hash of the downstream object *values* absent their object *types*.
2. the post-transformed types do not change unless the *caller inferred* type of the input it depends on changes

The latter criteria is more stringent than type stability. A function input could have caller inferred type of `Any`, be type stable, and return either `Char` or an `Int` depending on the value of its input. Such a function would violate this second criteria.

### Examples

When is the pre-transformed type sufficient to disambiguate hashed values? First, many type-unstable functions should be considered unable to meet this criteria. The only time they are certain to be safe is when the values disambiguate the hash regardless of the type.

For instance, the assmuptions of `hoist_type=true` would be violated by the function `x -> x < 0 : Char(0) ? Int32(0)` because the bits that are hashed downstream are identical, even though the type information that should be hashed with them are different: `Char` is a `StringType` and `Ing32` is a `NumberType`.

In contrast, `x -> x < 0 : Char(1) : Int32(2)` is safe to use with `hoist_type=true`, because although the type changes, the byte sequence of the value never overlaps, regardless of the type rerturned. If you are confident the bit sequence will be unique in this way, you could safely use `hoist_type=true` even though the transformer is type unstable.

Beware! When a type unstable function will be unsafe for a given type depends on the context, because users can define their own `type_transform` that can lead to more type details being important to the hashed value. For instance, in the default context `x -> x < 0 : Int32(0) ? UInt32(0)` would be considered safe, since both `Int32` and `UInt32` have the same type for purposes of hashing (`NumberType`), *but* if the user were to write a custom `transform_type` in a `HashExactNumberType` context, now this function is no longer safe to use with `hoist_type=true`.

These examples hopefully help to clarify when type-unstable functions can lead to unexpected hash collisions with `hoist_type=true`. However type *stable* functions can also lead to invalid hashes with `hoist_type=true`. For example:

```julia
struct MyType
    a::Any
end
# ignore `metadata`, `data` will be hashed using fallbacks for `AbstractArray` type
# DO NOT DO IT THIS WAY; YOUR CODE WILL BE BUGGY!!!
StableHashTraits.transformer(::Type{<:MyType}) = Transformer(x -> (;x.a); hoist_type=true)
stable_hash(MyType(missing)) == stable_hash(MyType(nothing)) ## OOPS, we wanted these to be different but this returns `true`
```

Setting the flag to `hoist_type=true` here causes the type of the `missing` and `nothing` to be hoisted, since the field `a` is a concrete type in the return value of `Transformer`'s function. Since only the type of these two values is hashed, their hashes now collide. If the field of the pre-transformed type `a` was concrete, there wouldn't be any problem, because its type would be hashed, and that would include either the `Missing` or `Nothing` in the type hash.

For this reason, it is better to use `pick_fields` and `omit_fields` to select or remove fields from a type you want to transform.

```julia
struct MyType
    a::Any
end
StableHashTraits.transformer(::Type{<:MyType}) = Transformer(x -> (;x.a); hoist_type=false)
stable_hash(MyType(missing)) != stable_hash(MyType(nothing)) ## this works

# NOTE: pick_fields sets `hoist_type=true` by default; it is set here to clearly illustrate
# what is happening.
StableHashTraits.transformer(::Type{<:MyType}) = Transformer(pick_fields(:a); hoist_type=true)
stable_hash(MyType(missing)) != stable_hash(MyType(nothing)) ## this also works and is faster than the previous implementation
```

Bottom line: It is not sufficient for the function to be type stable. If the return value of your transformer function over its known domain returns multiple distinct concrete types, you can run into this problem.

## Customizing Type Hashes

Types are hashed by hashing the return value of [`transform_type`](@ref) when hashing an object's type and the return value of [`transform_type_value`](@ref) when hashing a type as a value (e.g. `stable_hash(Int)`). The docs for these functions provide several examples of their usage.

In addition there is some structure of the type that is always hashed:

- `fieldtypes(T)` of any `StructType.DataType` (e.g. StructType.Struct)
- `eltype(T)` of any `StructType.ArrayType` or `StructType.DictType` or `AbstractRange`

These get added internally so as to ensure that the type-hoisting describe above can rely on eltypes and fieldtypes storing all downstream children's concrete types.
