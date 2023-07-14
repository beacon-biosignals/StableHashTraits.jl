using StableHashTraits
using ReferenceTests
using Aqua
using Test
using Dates
using UUIDs
using SHA
using DataFrames
using Tables

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

StableHashTraits.hash_method(::TestType) = UseFields()
StableHashTraits.hash_method(::TestType2) = UseQualifiedName(UseFields())
StableHashTraits.hash_method(::TestType3) = UseProperties(:ByName)
StableHashTraits.hash_method(::TestType4) = UseProperties()
StableHashTraits.hash_method(::TypeType) = UseFields()
StableHashTraits.write(io, x::TestType5) = write(io, reverse(x.bob))

struct NonTableStruct
    x::Vector{Int}
    y::Vector{Int}
end
StableHashTraits.hash_method(::NonTableStruct) = UseFields()

struct NestedObject{T}
    x::T
    index::Int
end

struct BasicHashObject
    x::AbstractRange
    y::Vector{Float64}
end
StableHashTraits.hash_method(x::BasicHashObject) = UseFields()
struct CustomHashObject
    x::AbstractRange
    y::Vector{Float64}
end
struct CustomContext{P}
    parent_context::P
end
StableHashTraits.parent_context(x::CustomContext) = x.parent_context
function StableHashTraits.hash_method(::CustomHashObject)
    return UseAndReplaceContext(UseFields(), CustomContext)
end
StableHashTraits.hash_method(::BasicHashObject) = UseFields()
StableHashTraits.hash_method(::AbstractRange, ::CustomContext) = UseIterate()
function StableHashTraits.hash_method(x::Any, c::CustomContext)
    return StableHashTraits.hash_method(x, c.parent_context)
end

struct BadTransform end
StableHashTraits.hash_method(::BadTransform) = UseTransform(identity)

struct GoodTransform{T}
    count::T
end
function StableHashTraits.hash_method(x::GoodTransform)
    !(x.count isa Number) && return UseQualifiedName(UseTransform(x -> x.count))
    x.count > 0 && return UseTransform(x -> GoodTransform(-0.1x.count))
    return UseTransform(x -> GoodTransform(string(x.count)))
end

struct TablesEq end
StableHashTraits.parent_context(::TablesEq) = HashVersion{1}()
function StableHashTraits.hash_method(x::T, c::TablesEq) where {T}
    return Tables.istable(T) ? UseTable() :
           StableHashTraits.hash_method(x, HashVersion{1}())
end

struct ViewsEq end
StableHashTraits.parent_context(::ViewsEq) = HashVersion{1}()
function StableHashTraits.hash_method(::AbstractArray, ::ViewsEq)
    return UseHeader("Base.AbstractArray", UseSize(UseIterate()))
end
function StableHashTraits.hash_method(::AbstractString, ::ViewsEq)
    return UseHeader("Base.AbstractString", UseWrite())
end

struct MyOldContext end
StableHashTraits.hash_method(::AbstractArray, ::MyOldContext) = UseIterate()

struct ExtraTypeParams{P,T}
    value::T
end
