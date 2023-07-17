using StableHashTraits
using ReferenceTests
using Aqua
using Test
using Dates
using UUIDs
using SHA
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

StableHashTraits.hash_method(::TestType) = UseFields()
StableHashTraits.hash_method(::TestType2) = Use(qualified_name, UseFields())
StableHashTraits.hash_method(::TestType3) = UseFields(:ByName, propertynames => getproperty)
StableHashTraits.hash_method(::TestType4) = UseFields(propertynames => getproperty)
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
StableHashTraits.hash_method(::BasicHashObject) = UseFields()
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
StableHashTraits.hash_method(::BadTransform) = Use(identity)

struct GoodTransform{T}
    count::T
end
function StableHashTraits.hash_method(x::GoodTransform)
    !(x.count isa Number) && return UseQualifiedName(Use(x -> x.count))
    x.count > 0 && return Use(x -> GoodTransform(-0.1x.count))
    return Use(x -> GoodTransform(string(x.count)))
end

struct TablesEq end
StableHashTraits.parent_context(::TablesEq) = HashVersion{1}()
function StableHashTraits.hash_method(x::T, ::TablesEq) where {T}
    if Tables.istable(T)
        if Tables.columnaccess(T)
            return UseFields(Tables.columnnames => Tables.getcolumn)
        else
            return Use(Tables.columns)
        end
    end
    return StableHashTraits.hash_method(x, HashVersion{1}())
end

struct ViewsEq end
StableHashTraits.parent_context(::ViewsEq) = HashVersion{1}()
function StableHashTraits.hash_method(::AbstractArray, ::ViewsEq)
    return Use("Base.AbstractArray", Use(size, UseIterate()))
end
function StableHashTraits.hash_method(::AbstractString, ::ViewsEq)
    return UseWrite()
end
StableHashTraits.hash_method(::String, ::ViewsEq) = UseWrite()

struct MyOldContext end
StableHashTraits.hash_method(::AbstractArray, ::MyOldContext) = UseIterate()

struct ExtraTypeParams{P,T}
    value::T
end
