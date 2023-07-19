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
StableHashTraits.hash_method(::TestType3) = StructHash(propertynames => getproperty, :ByName)
StableHashTraits.hash_method(::TestType4) = StructHash(propertynames => getproperty)
StableHashTraits.hash_method(::TypeType) = StructHash()
StableHashTraits.write(io, x::TestType5) = write(io, reverse(x.bob))

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
