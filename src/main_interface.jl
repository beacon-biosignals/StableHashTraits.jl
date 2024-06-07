"""
    HashVersion{V}()

The default `hash_context` used by `stable_hash`. There are currently four versions (1-4).
Version 4 should be favored when at all possible. Version 1 is the default version, so as to
avoid changing the hash computed by existing code.

By explicitly passing this hash version in `stable_hash` you ensure that hash values for
these fallback methods will not change even if new hash versions are developed.
"""
struct HashVersion{V}
    function HashVersion{V}() where {V}
        V < 4 &&
            Base.depwarn("HashVersion{T} for T < 4 are deprecated, favor `HashVersion{4}` in " *
                         "all cases where backwards compatible hash values are not " *
                         "required.", :HashVersion)
        return new{V}()
    end
end

"""
    stable_hash(x, context=HashVersion{1}(); alg=sha256)
    stable_hash(x; alg=sha256, version=1)

Create a stable hash of the given objects. As long as the context remains the same, this
hash is intended to remain unchanged across julia versions. The built-in context is
HashVersion{N}, and if you specify a `version`, this is equivalent to explicitly passing
`HashVersion{version}`. To customize how the hash is copmuted see [Using Contexts](@ref).

It is best to pass an explicit version, since `HashVersion{4}` is the only non-deprecated
version; it is much faster than 1 and more stable than 2. Furthermore, a new hash version is
provided in a future release, the hash you get by passing an explicit `HashVersion{N}`
should *not* change. (Note that the number in `HashVersion` does not necessarily match the
package version of `StableHashTraits`).

In hash version 4, you customize how hashes are computed using [`transformer`](@ref), and in
versions 1-4 using [`hash_method`](@ref).

To change the hash algorithm used, pass a different function to `alg`. It accepts any `sha`
related function from `SHA` or any function of the form `hash(x::AbstractArray{UInt8},
[old_hash])`.

The `context` value gets passed as the second argument to [`hash_method`](@ref) and
[`transformer`](@ref), and as the third argument to [`StableHashTraits.write`](@ref). Note
that both `hash_method` and `StableHashTraits.write` are deprecated.

## See Also

[`transformer`](@ref)
"""
stable_hash(x; alg=sha256, version=1) = return stable_hash(x, HashVersion{version}(); alg)
function stable_hash(x, context; alg=sha256)
    if root_version(context) < 4
        return compute_hash!(deprecated_hash_helper(x, HashState(alg, context), context,
                                                    hash_method(x, context)))
    else
        hash_state = hash_type_and_value(x, HashState(alg, context), context)
        return compute_hash!(hash_state)
    end
end

"""
    StableHashTraits.parent_context(context)

Return the parent context of the given context object. (See [`hash_method`](@ref) and
[`@context`](@ref) for details of using context). The default method falls back to returning
`HashVersion{1}`, but this is flagged as a deprecation warning; in the future it is expected
that all contexts define this method.

This is normally all that you need to know to implement a new context. However, if your
context is expected to be the root context—one that does not fallback to any parent (akin to
`HashVersion`)—then there may be a bit more work involved. In this case, `parent_context`
should return `nothing`. You will also need to define
[`StableHashTraits.root_version`](@ref).
"""
function parent_context(x::Any)
    Base.depwarn("You should explicitly define a `parent_context` method for context " *
                 "`$x`. See details in the docstring of `hash_method`.", :parent_context)
    return HashVersion{1}()
end

"""
    StableHashTraits.Transformer(fn=identity, result_method=nothing;
                                 hoist_type=StableHashTraits.hoist_type(fn))

Wraps the function used to transform values before they are hashed. The function is applied
(`fn(x)`), and then its result is hashed according to the trait `@something result_method
StructType(fn(x))`.

The flag `hoist_type` indicates if it is safe to hoist type hashes outside of
loops; this is always the case when `fn` is type stable. See the manual for details about
other cases when it is safe to set this flag to true.

## See Also

[`transformer`](@ref)
"""
struct Transformer{F,H}
    fn::F
    result_method::H # if non-nothing, apply to result of `fn`
    hoist_type::Bool
    function Transformer(fn::Base.Callable=identity, result_method=nothing;
                         hoist_type=StableHashTraits.hoist_type(fn))
        return new{typeof(fn),typeof(result_method)}(fn, result_method, hoist_type)
    end
end

"""
    StableHashTraits.hoist_type(fn)

Returns true if it is known that `fn` preservess type structure ala [`Transformer`](@ref).
See [Optimizing Transformers](@ref) for details. This is false by default for all functions
but `identity` and [`module_nameof_string`](@ref). You can define a method of this function
for your own fn's to signal that their results can be safely optimized via hoisting the
type hash outside of loops.
"""
hoist_type(::typeof(identity)) = true
hoist_type(::Function) = false
hoist_type(::Type) = false
(tr::Transformer)(x) = tr.fn(x)

"""
    StableHashTraits.transformer(::Type{T}, [context]) where {T}

Return [`Transformer`](@ref) indicating how to modify an object of type `T` before hashing
it. Methods without `context` are called first, and if no method for that type exists there
is a fallback that calls the method without a `context`. Users can therefore implement a
method with a context object to customize transformations for that context only, or a single
argument method when you wish to affect the transformation across all contexts (where no
specialized method for that context exists).
"""
transformer(::Type{T}, context) where {T} = transformer(T, parent_context(context))
transformer(::Type{T}, ::HashVersion{4}) where {T} = transformer(T)
transformer(x) = Transformer()

"""
    StableHashTraits.TransformIdentity(x)

Signal that the type `x` should not be transformed in the usual way, but by hashing `x`
directly. This is useful when you want to hash both `x` the way it would normally be hashed
without a specialized method of [`transformer`](@ref) along with some metadata. Without this
wrapper, returning `(metadata(x), x)` from the transforming function would cause an infinite
regress (adding `metadata(x)` upon each call).

## Example

```julia
struct MyArray <: AbstractVector{Int}
    data::Vector{Int}
    meta::Dict{String, String}
end
# other array methods go here...
function StableHashTraits.transformer(::Type{<:MyArray})
    return Transformer(x -> (x.meta, TransformIdentity(x)); hoist_type=true)
end
```

In this example we hash both some metadata about a custom array, and each of the elements of
`x`
"""
struct TransformIdentity{T}
    val::T
end
function transformer(::Type{<:TransformIdentity}, ::HashVersion{4})
    return Transformer(x -> x.val; hoist_type=true)
end

function stable_hash_helper(x, hash_state, context, trait)
    throw(ArgumentError("Unrecognized trait of type `$(typeof(trait))` when " *
                        "hashing object $x. The implementation of `transformer` for this " *
                        "object provides an invalid second argument."))
    return
end

"""
    StableHashTraits.@context MyContext

Shorthand for declaring a hash context.

Contexts are used to customize the behavior of a hash for a type you don't own, by passing
the context as the second argument to `stable_hash`, and specializing methods of
[`transform`](@ref) or [`transform_type`](@ref) on your context (see example below).

The clause `@context MyContext` is re-written to:

```julia
struct MyContext{T}
    parent::T
end
StableHashTraits.parent_context(x::MyContext) = x.parent
```

The parent context is typically another custom context, or the root context
`HashVersion{4}()`.

## Example

```julia
StableHashTraits.@context NumberAbs
transformer(::Type{<:Number}, ::NumberAbs) = Transformer(abs; hoist_type=true)
stable_hash(10, NumberAbs(HashVersion{4}())) == stable_hash(-10, NumberAbs(HashVersion{4}()))
```

## See Also
- [`parent_context`](@ref)

"""
macro context(TypeName)
    quote
        Base.@__doc__ struct $(esc(TypeName)){T}
            parent::T
        end
        StableHashTraits.parent_context(x::$(esc(TypeName))) = x.parent
    end
end

"""
    module_nameof_string(::Type{T})
    module_nameof_string(T::Module)
    module_nameof_string(::T) where {T}

Get a (mostly!) stable name of `T`. This is a helpful utility for writing your own methods
of [`transform_type`](@ref) and [`transform_type_value`](@ref). The stable name includes the
name of the module that `T` was defined in. Any uses of `Core` are replaced with `Base` to
keep the name stable across versions of julia. Anonymous names (e.g. `module_nameof_string(x
-> x+1)`) throw an error, as no stable name is possible in this case.

If the module or name of a type changes, this value will (obviously) change. The module of
many types is considered an implementation detail and can change between non-breaking
versions of a package. For this reason uses of `module_nameof_string` must be explicitly
defined by user of `StableHashTraits`. This function is not used internally for the methods
of `HashVersion{4}` but see [`HashFunctions`](@ref), [`HashTypeValues`](@ref),
[`HashNullTypes`](@ref) and [`HashSingletonTypes`](@ref).
"""
function module_nameof_string(::Type{Union{A, B}}) where {A, B}
    # Main.@infiltrate
    !@isdefined(A) && return ""
    !@isdefined(B) && return module_nameof_string_(A)
    return module_nameof_string(A)*","*module_nameof_string(B)
end
function module_nameof_string(::Type{T}) where {T}
    module_nameof_string_(T)
end
hoist_type(::typeof(module_nameof_string)) = true
function module_nameof_string_(::Type{T}) where {T}
    # special case for function types
    if hasproperty(T, :instance) && isdefined(T, :instance) && T.instance isa Function
        return "typeof($(qualified_name_(T.instance)))"
    else
        module_nameof_(T)
    end
end
function module_nameof_(::Type{T}) where {T}
    return validate_name(cleanup_name(string(parentmodule(T))*"."*string(nameof(T))))
end

"""
    nameof_string(::Type{T})
    nameof_string(T::Module)
    nameof_string(::T) where {T}

Get a stable name of `T`. This is a helpful utility for writing your own methods of
[`transform_type`](@ref) and [`transform_type_value`](@ref). The stable name is computed
from `nameof`. Any uses of `Core` are replaced with `Base` to keep the name stable across
versions of julia. Anonymous names (e.g. `module_nameof_string(x -> x+1)`) throw an error, as
no stable name is possible in this case.
"""
function nameof_string(::Type{Union{A, B}}) where {A, B}
    !@isdefined(A) && return ""
    !@isdefined(B) && return nameof_string_(A)
    return nameof_string(A)*","*nameof_string(B)
end
function nameof_string(::Type{T}) where {T}
    nameof_string_(T)
end
function nameof_string_(::Type{T}) where {T}
    # special case for function types
    if hasproperty(T, :instance) && isdefined(T, :instance)
        return "typeof($(name_(T.instance)))"
    else
        name_(T)
    end
end
function name_(::Type{T}) where {T}
    return validate_name(cleanup_name(string(nameof(T))))
end


"""
   transform_type(::Type{T}, [context])

The value to hash for type `T` when hashing an object's type. Users of `StableHashTraits`
can implement a method that accepts one (`T`) or two arguments (`T` and `context`). If no
method is implemented, the fallback `transform_type` value uses `StructType(T)` to decide
how to hash `T`; this is documented under [What gets hashed? (hash version 3)](@ref).

Any types returned by `transform_type` has `transform_type` applied to it, so make sure that
you only return types when they are are some nested component of your type (do not return
`T`!!)

This method is used to add additional data to the hash of a type. Internally, the data
listed below is always added, outside of the call to `transform_type`:

- `fieldtypes(T)` of any `StructType.DataType` (e.g. StructType.Struct)
- `eltype(T)` of any `StructType.ArrayType` or `StructType.DictType` or `AbstractRange`

These components of the type need not be returned by `transform_type` and you cannot prevent
them from being included in a type's hash, since otherwise the assumptions necessary for
efficient hash computation would be violated.

## Examples

### Singleton Types

You can opt in to hashing novel singleton types by overwriting `transform_type`:

```julia
struct MySingleton end
StructTypes.StructType(::MySingleton) = StructTypes.SingletonType()
function StableHashTraits.transform_type(::Type{<:MySingleton})
    return "MySingleton"
end
```
If you do not own the type you wish to customize, you can use a context:

```julia
using AnotherPackage: PackageSingleton
StableHashTriats.@context HashAnotherSingleton
function StableHashTraits.transform_type(::Type{<:PackageSingleton}, ::HashAnotherSingleton)
    return "AnotherPackage.PackageSingleton"
end
context = HashAnotherSingleton(HashVersion{4}())
stable_hash([PackageSingleton(), 1, 2], context) # will not error
```

### Functions

Overwriting `transform_type` can be used to opt-in to hashing functions.

```julia
f(x) = x+1
StableHashTraits.transform_type(::typeof(fn)) = "Main.fn"
```

### Type Parameters

To include additional type parameters in a type's hash, you can overwrite `transform_type`

```julia
struct MyStruct{T,K}
    wrapped::T
end

function StableHashTraits.transform_type(::Type{<:MyStruct{T,K}})
    return "MyStruct", K
end
```

By adding this method for `type_structure` both `K` and `T` will impact the hash, `T`
because it is included in `fieldtypes(<:MyStruct)` and `K` because it is included in
`type_structure(<:MyStruct)`.

If you do not own the type you want to customize, you can specialize `type_structure` using
a specific hash context.

```julia
using Intervals

StableHashTraits.@context IntervalEndpointsMatter

function HashTraits.type_structure(::Type{<:I}, ::IntervalEndpointsMatter) where {T, L, R, I<:Interval{T, L, R}}
    return (L, R)
end

context = IntervalEndpointsMatter(HashVersion{4}())
stable_hash(Interval{Closed, Open}(1, 2), context) !=
    stable_hash(Interval{Open, Closed}(1, 2), context) # true
```

## See Also

[`transformer`](@ref) [`@context`](@ref)
"""

function transform_type(::Type{T}, context) where {T}
    return transform_type(T, parent_context(context))
end
transform_type(::Type{T}, ::HashVersion{4}) where {T} = transform_type(T)
transform_type(::Type{Union{}}) = "Union{}"
transform_type(::Type{T}) where {T} = transform_type_by_trait(T, StructType(T))
transform_type_by_trait(::Type, ::S) where {S<:StructTypes.StructType} = module_nameof_string(S)

"""
    transform_type_value(::Type{T}, [trait], [context]) where {T}

The value that is hashed for type `T` when hashing a type as a value (e.g.
`stable_hash(Int)`). Hashing types as values is an error by default, but you can use this
method to opt-in to hashing a type as a value. You can return types (e.g. type parameters of
`T`), but do not return `T` or you will get a stack overflow.

## Example

You can define a method of this function to opt in to hashing your type as a value.

```julia
struct MyType end
StableHashTraits.transform_type_value(::Type{T}) where {T<:MyType} = module_nameof_string(T)
stable_hash(MyType) # does not error
```

Likewise, you can opt in to this behavior for a type you don't own by defining a context.

```julia
StableHashTraits.@context HashNumberTypes
function StableHashTraits.type_value_identifier(::Type{T},
                                                ::HashNumberTypes) where {T <: Number}
    return module_nameof_string(T)
end
stable_hash(Int, HashNumberTypes(HashVersion{4}())) # does not error
```

## See Also

[`transformer`](@ref)
[`transform_type`](@ref)

"""
function transform_type_value(::Type{T}, context) where {T}
    return transform_type_value(T, parent_context(context))
end

function transform_type_value(::Type{T}, c::HashVersion{4}) where {T}
    transform_type_value(T)
end
transform_type_value(::Type{Union{}}) = "Union{}"
function transform_type_value(::Type{T}) where {T}
    if !contains(string(nameof(T)), "#")
        @error fallback_error("transform_type_value", T)
    end
    return throw(MethodError(transform_type_value, T))
end

function fallback_error(name, T)
    return """
    There is not a specific method of `$name` for type `$T

    If you wish to avoid this error, you can implement a method:

        StableHashTraits.$(name)(::Type{$(nameof(T))}) = $(module_nameof_string(T))

    You are responsible for ensuring this return value is stable following any non-breaking
    updates to the type.

    If you don't own the type, consider using `StableHashTraits.@context`.
    """
end

function transform_type_value(::Type{T}, c::HashVersion{4}) where {T<:Function}
    return transform_type(T)
end
