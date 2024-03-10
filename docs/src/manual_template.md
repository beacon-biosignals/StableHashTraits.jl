# StableHashTraits

{INSERT_OVERVIEW}

## Basic Customization

You typically want to simply override a method of [`transformer`](@ref). This should
return a function wrapped in a [`Transformer`](@ref) object that will be applied
to an object and its result is the actual value that gets hashed.

{INSERT_EXAMPLE}

In this example we also optimize our hash by setting `preserves_structure=true`. You can do this any time your function is type stable, but there are additional conditions under which
you can still set this flag to true, discussed below.

`Transformer` takes a second positional argument which is the `StructType` you wish to use
on the transformed return value. By default `StructType` is applied to the result to
determine this automatically, but in some cases it can be useful to modify this trait by
passing a second argument (see the example below).

**To avoid StackOverflow errors** make sure you don't return the object itself as an element
of some collection. It can be tempting to do e.g. `(mymetadata(x), x)` as a return value for
`transformer`'s function. Instead you can use [`TransformIdentity`](@ref) to make sure this
won't lead to an infinite regress: e.g. `(mymetadata(x), TransformIdentity(x))`. Using [`TransformIdentity`](@ref) will cause `x`'s transformed result to be `x` itself, thereby avoiding the infinite regress.

`transformer` customizes how the *content* of your object is hashed. The hash of the type
and any structure it customized separately. If you wish to customize how the type of an
object is hashed, you need to refer to the section below.

## Using Contexts
Because not every package knows about either `StableHashTraits` or `StructTypes`, there may
be types you don't own that you want to customize the hash of. In this scenario you should
define a context object that you pass as the second argument to `stable_hash` and define a
method of `transform` that dispatches on this context object as its second argument.

A context is simply an arbitrary object that defines a method for `parent_context`. By
default the context to `stable_hash` is `HashVersion{version}`. Because of `parent_context`
contexts can be stacked, and a `HashVersion` should be at the bottom of the stack. There are
fallback methods for `transformer` that look at the value implemented by the parent context.
In this way you need only define methods for the types you want to customize.

For example, this customization makes the ordering of named tuple keys affect the hash
value.

```julia
struct NamedTuplesOrdered{T}
    parent::T
end
StableHashTraits.parent_context(x::NamedTuplesOrdered) = x.parent
function transformer(::Type{<:NamedTuple}, ::NamedTuplesOrdered)
    Transformer(identity, StructTypes.OrderedStruct())
end
context = NamedTuplesOrdered(HashVersion{3}())
stable_hash((; a=1:2, b=1:2), context) != stable_hash((; b=1:2, a=1:2), context) # true
```

Without this context, the keys are first sorted because `StructType(NamedTuple) isa
StructType.UnorderedStruct`.

## Optimizing Transformers

As noted `preserves_structure` can safely be set to true for any type-stable function. It is set to true by default for `identity`. When set to true, `stable_hash` will hoist type hashes outside of loops when possible, avoiding type hashes for any deeply nested fields, so long as the path to them includes all concretetypes. For example, when hashing an `Array{Int}` the `Int` will only be hashed once, not once for every element.

When `preserves_structure=false` (the default for most functions) the type of the return value from `transform` is always hashed alongside the transformed value.

This should give the reader some idea of when a type-unstable function can be safely marked as `preserves_structure=true`. In particular any case where each value passed to transform maps to a value that will hash to a unique bit-sequence should be fine. This would be violated, for instance, by `x -> x < 0 : UInt8(0) ? Int8(0)`, but not by `x -> x < 0 : UInt(1) : Int8(2)`. In the latter case we could safely mark `preserves_structure=true`.

## Customizing Type Hashes

Types are hahed by hashing a type name and a type structure. The structure is determined by the `StructType` as detailed above (e.g. `ArrayType`s hash their `eltype`). As noted there, the name will be based on `StructType` when hashing the type of an object, and the name of the type itself when hashing the type as a value.

You can change how a type name is hashed for an object using [`type_hash_name`](@ref), how a
type name is hashed as a value using [`type_value_name`](@ref) and how the structure is
hashed using [`type_structure`](@ref). You should ensure that [`type_structure`](@ref) calls the `type_structure(x, trait, parent_context(x))` so that the `HashVersion{3}` method for `type_structure` is eventually called. If you don't do this the assumptions of type
hoisting described in the previous section will be violated.

## Caching

StableHashTraits cached hash results for all types and large values. This cache is generated
per call to `stable_hash`; to leverage the same cache over multiple calls you can create a
`CachingHashContext`,

```julia
context = CachingHashContext(HashVersion{3}())
stable_hash(x, context)
stable_hash(y, context) # previously cached values will be re-used
```

However, if you change any method definitions to `transform` between calls to `stable_hash` you will need to create a new context to avoid using stale method results.

If you know that a particular object is referenced in multiple places, you can make sure
that it is cached by wrapping it in a `HashShouldCache` object during a call to
`transformer`, like so:

```@doctest
julia> begin;
            using StableHashTraits
            using StableHashTraits: Transformer

            struct Foo
                x::Int
                ref::Bar
            end

            struct Bar
                data::Vector{Int}
            end

            foos = Foo.(rand(Int, 10_000), Ref(Bar(rand(Int, 1_000))))
            transformer(::Type{<:Bar}) = Transformer(function(x)
                @show "Hello!"
                HashShouldCache(x)
            end
        end

julia> stable_hash(foos) # Bar will only be cached once
"Hello!"

```
