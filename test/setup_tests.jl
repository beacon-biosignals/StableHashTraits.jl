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
using TimeZones
using Dates

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

function StableHashTraits.transformer(::Type{<:TestType2})
    return StableHashTraits.Transformer(x -> (x.a, x.b); hoist_type=true)
end

# make TestType3 look exactly like TestType
StableHashTraits.transform_type(::Type{<:TestType3}) = "TestType"
function StableHashTraits.transformer(::Type{<:TestType3})
    return StableHashTraits.Transformer(pick_fields(:a, :b))
end

StableHashTraits.transform_type(::Type{<:TestType2}) = "TestType2"
StructTypes.StructType(::Type{<:TestType4}) = StructTypes.OrderedStruct()

struct NonTableStruct
    x::Vector{Int}
    y::Vector{Int}
end

struct NestedObject{T}
    x::T
    index::Int
end

struct BasicHashObject
    x::AbstractRange
    y::Vector{Float64}
end
struct CustomHashObject
    x::AbstractRange
    y::Vector{Float64}
end
struct CustomContext{P}
    parent_context::P
end
StableHashTraits.parent_context(x::CustomContext) = x.parent_context

struct BadTransform end

struct GoodTransform{T}
    count::T
end

struct MyOldContext end

struct ExtraTypeParams{P,T}
    value::T
end
function StableHashTraits.transform_type(::Type{T}) where {P,U,T<:ExtraTypeParams{P,U}}
    return "ExtraTypeParams", P, U
end

struct BadHashMethod end
StableHashTraits.transformer(::Type{<:BadHashMethod}) = "garbage"

struct BadHashMethod2 end
function StableHashTraits.transformer(::Type{<:BadHashMethod2})
    return StableHashTraits.Transformer(identity, "garbage")
end

struct Singleton1 end
struct Singleton2 end

struct BadRootContext end
StableHashTraits.transformer(::Type{Int}, ::BadRootContext) = StableHashTraits.Transformer()

mutable struct CountedBufferState
    state::StableHashTraits.BufferedHashState
    positions::Vector{Int}
end
CountedBufferState(x::StableHashTraits.BufferedHashState) = CountedBufferState(x, Int[])
StableHashTraits.HashState(x::CountedBufferState, ctx) = x
function StableHashTraits.similar_hash_state(x::CountedBufferState)
    return CountedBufferState(StableHashTraits.similar_hash_state(x.state), Int[])
end

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

struct UnstableStruct1
    a::Any
    b::Any
end
function StableHashTraits.transformer(::Type{<:UnstableStruct1})
    return StableHashTraits.Transformer(pick_fields(:a))
end

struct UnstableStruct2
    a::Any
    b::Any
end
function StableHashTraits.transformer(::Type{<:UnstableStruct2})
    return StableHashTraits.Transformer(omit_fields(:b))
end

struct UnstableStruct3
    a::Any
    b::Any
end
function StableHashTraits.transformer(::Type{<:UnstableStruct3})
    return StableHashTraits.Transformer(x -> (; x.a); hoist_type=true)
end

struct WeirdTypeValue end
StableHashTraits.transform_type_value(::Type{<:WeirdTypeValue}) = Int

struct NumberTypeA
    x::Int
end
struct NumberTypeB
    x::Int
end
