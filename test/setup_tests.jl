using StableHashTraits
using ReferenceTests
using Aqua
using Test
using Dates
using UUIDs
using SHA
using CRC32c
using DataFrames
using Tables
using AWSS3
using Pluto
using StructTypes

struct TestType
    a::Any
    b::Any
end

struct TestType2
    a::Any
    b::Any
end

struct TestType3
    b::Any
    a::Any
end

struct TestType4
    b::Any
    a::Any
end

struct TypeType
    atype::Type
end

struct TestType5
    bob::String
end

StableHashTraits.hash_method(::TestType) = StructHash()
StableHashTraits.hash_method(::TestType2) = FnHash(qualified_name), StructHash()
StableHashTraits.hash_method(::TestType3) = StructHash(:ByName)
StableHashTraits.hash_method(::TestType4) = StructHash(propertynames => getproperty)
StableHashTraits.hash_method(::TypeType) = StructHash()
StableHashTraits.write(io, x::TestType5) = write(io, reverse(x.bob))

StableHashTraits.type_hash_name(::Type{<:TestType2}) = "TestType2"
StructTypes.StructType(::Type{<:TestType4}) = StructTypes.OrderedStruct()

struct NonTableStruct
    x::Vector{Int}
    y::Vector{Int}
end
StableHashTraits.hash_method(::NonTableStruct) = StructHash()

struct NestedObject{T}
    x::T
    index::Int
end

struct BasicHashObject
    x::AbstractRange
    y::Vector{Float64}
end
StableHashTraits.hash_method(::BasicHashObject) = StructHash()
struct CustomHashObject
    x::AbstractRange
    y::Vector{Float64}
end
struct CustomContext{P}
    parent_context::P
end
StableHashTraits.parent_context(x::CustomContext) = x.parent_context
function StableHashTraits.hash_method(::CustomHashObject)
    return HashAndContext(StructHash(), CustomContext)
end
StableHashTraits.hash_method(::BasicHashObject) = StructHash()
StableHashTraits.hash_method(::AbstractRange, ::CustomContext) = IterateHash()
function StableHashTraits.hash_method(x::Any, c::CustomContext)
    return StableHashTraits.hash_method(x, c.parent_context)
end

struct BadTransform end
StableHashTraits.hash_method(::BadTransform) = FnHash(identity)

struct GoodTransform{T}
    count::T
end
function StableHashTraits.hash_method(x::GoodTransform)
    !(x.count isa Number) && return FnHash(qualified_name), FnHash(x -> x.count)
    x.count > 0 && return FnHash(x -> GoodTransform(-0.1x.count))
    return FnHash(x -> GoodTransform(string(x.count)))
end

struct MyOldContext end
StableHashTraits.hash_method(::AbstractArray, ::MyOldContext) = IterateHash()

struct ExtraTypeParams{P,T}
    value::T
end
function StableHashTraits.type_structure(::Type{T}, ::StructTypes.DataType,
                        ::HashVersion{3}) where {P,U,T<:ExtraTypeParams{P,U}}
    return (P, U)
end

struct BadHashMethod end
StableHashTraits.hash_method(::BadHashMethod) = "garbage"
StableHashTraits.transformer(::Type{<:BadHashMethod}) = "garbage"

struct Singleton1 end
struct Singleton2 end

struct BadRootContext end
StableHashTraits.parent_context(::BadRootContext) = nothing
StableHashTraits.hash_method(::Int, ::BadRootContext) = WriteHash()
StableHashTraits.transformer(::Type{Int}, ::BadRootContext) = StableHashTraits.Transformer()

mutable struct CountedBufferState
    state::StableHashTraits.BufferedHashState
    positions::Vector{Int}
end
CountedBufferState(x::StableHashTraits.BufferedHashState) = CountedBufferState(x, Int[])
StableHashTraits.HashState(x::CountedBufferState, ctx) = x
StableHashTraits.similar_hash_state(x::CountedBufferState) = CountedBufferState(StableHashTraits.similar_hash_state(x.state), Int[])

function StableHashTraits.update_hash!(x::CountedBufferState, args...)
    x.state = StableHashTraits.update_hash!(x.state, args...)
    push!(x.positions, position(x.state.io))
    return x
end

function StableHashTraits.compute_hash!(x::CountedBufferState)
    return StableHashTraits.compute_hash!(x.state)
end
function StableHashTraits.start_nested_hash!(x::CountedBufferState)
    x.state = StableHashTraits.start_nested_hash!(x.state)
    return x
end
function StableHashTraits.end_nested_hash!(x::CountedBufferState, n)
    x.state = StableHashTraits.end_nested_hash!(x.state, n.state)
    return x
end

struct BadShowSyntax end
Base.show(io::IO, ::Type{<:BadShowSyntax}) = print(io, "{")

struct CachingType
    data::Vector{Int}
end
cache_type_hashed = 0

struct ContainerType{T}
    x::Int
    ref::T
end

function StableHashTraits.transformer(::Type{<:CachingType})
    return StableHashTraits.Transformer(HashShouldCache)
end

function StableHashTraits.stable_hash_helper(x::CachingType, hash_state, context,
                                             st::StructTypes.DataType)
    global cache_type_hashed += 1
    return invoke(StableHashTraits.stable_hash_helper,
                  Tuple{Any,Any,Any,StructTypes.DataType}, x, hash_state,
                  context, st)
end

struct NonCachingType
    data::Vector{Int}
end
non_cache_type_hashed = 0

function StableHashTraits.stable_hash_helper(x::NonCachingType, hash_state, context,
                                             st::StructTypes.DataType)
    global non_cache_type_hashed += 1
    return invoke(StableHashTraits.stable_hash_helper,
                  Tuple{Any,Any,Any,StructTypes.DataType}, x, hash_state,
                  context, st)
end
