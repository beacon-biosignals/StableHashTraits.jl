using StableHashTraits
using Aqua
using Test
using Dates
using UUIDs
using SHA
using DataFrames
Aqua.test_all(StableHashTraits)

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

StableHashTraits.hash_method(::TestType) = UseProperties()
StableHashTraits.hash_method(::TestType2) = UseQualifiedName(UseProperties())
StableHashTraits.hash_method(::TestType3) = UseProperties(:ByName)
StableHashTraits.hash_method(::TestType4) = UseProperties()
StableHashTraits.hash_method(::TypeType) = UseProperties()
StableHashTraits.write(io, x::TestType5) = write(io, reverse(x.bob))

struct MyContext end
StableHashTraits.hash_method(::TestType, ::MyContext) = UseQualifiedName(UseProperties())

struct NonTableStruct
    x::Vector{Int}
    y::Vector{Int}
end
StableHashTraits.hash_method(::NonTableStruct) = UseProperties()

struct NestedObject{T}
    x::T
    index::Int
end

struct BasicHashObject
    x::AbstractRange
    y::Vector{Float64}
end
StableHashTraits.hash_method(x::BasicHashObject) = UseProperties()
struct CustomHashObject
    x::AbstractRange
    y::Vector{Float64}
end
struct CustomContext{T}
    old_context::T
end
function StableHashTraits.transform(val::CustomHashObject, context)
    return (val.x, val.y), CustomContext(context)
end
StableHashTraits.hash_method(x::AbstractRange, ::CustomContext) = UseIterate()
StableHashTraits.hash_method(x, context::CustomContext) = StableHashTraits.hash_method(x, context.old_context)

@testset "StableHashTraits.jl" begin
    # reference tests to ensure hash consistency
    @test stable_hash(()) == 0x48674bc7
    @test stable_hash([1, 2, 3]) == 0x1a366aea
    @test stable_hash([1 2; 3 4]) == 0x62398575
    @test stable_hash((a=1, b=2)) == 0x240bb84c
    @test stable_hash(sin) == 0x7706a39f
    @test stable_hash(TestType2(1, 2)) == 0x1f99ed3b
    @test stable_hash(TypeType(Array)) == 0xae27dba8
    @test stable_hash(TestType5("bobo")) == 0x85c469dd
    @test stable_hash(Nothing) == 0xb9695255
    @test stable_hash(Missing) == 0xafd1df92
    @test stable_hash(v"0.1.0") == 0x50cda5b5
    @test stable_hash(UUID("8d70055f-1864-48ff-8a94-2c16d4e1d1cd")) == 0x81d55a52
    @test stable_hash(Date("2002-01-01")) == 0x1e1a60e2
    @test stable_hash(Time("12:00")) == 0xbe0d1056
    @test stable_hash(TimePeriod(Nanosecond(0))) == 0x4bf33649
    @test stable_hash(Hour(1) + Minute(2)) == 0xffe46034
    @test stable_hash(DataFrame(; x=1:10, y=1:10)) == 0x2281617d

    # get some code coverage (and reference tests) for sha256
    bytes = [0xe2, 0x4c, 0xcd, 0x9d, 0xed, 0xaf, 0x29, 0xa7, 0x70, 0x82, 0x2f, 0x5c, 0x30,
             0x01, 0xd6, 0xa4, 0x45, 0x35, 0x18, 0x1d, 0xdd, 0x0f, 0x5c, 0x45, 0xb1, 0xd2,
             0x67, 0xa9, 0x92, 0x19, 0x52, 0x3f]
    @test stable_hash([1, 2, 3]; alg=sha256) == bytes

    bytes = [0xef, 0xf2, 0x3f, 0x82, 0xb1, 0x2f, 0xf2, 0xb6, 0x92, 0x53, 0xb7, 0x53, 0xca,
             0x06, 0xe6, 0xcf, 0x0b, 0xd5, 0xd7, 0xf1, 0xec, 0x7b, 0xce, 0xdc, 0x84, 0x7d,
             0xbc, 0xf0, 0x5d, 0x70, 0x9b, 0x4e]
    @test stable_hash(v"0.1.0"; alg=sha256) == bytes

    bytes = [0x2e, 0x83, 0x68, 0xcb, 0x4a, 0x04, 0x5b, 0x11, 0xf5, 0x4b, 0x0d, 0xb6, 0x9a,
             0x2d, 0x94, 0x73, 0x73, 0xe7, 0x03, 0xe1, 0x04, 0x7c, 0x49, 0x59, 0xec, 0x5f,
             0xcc, 0x45, 0x62, 0xc0, 0x02, 0x4b]
    @test stable_hash(sin; alg=sha256) == bytes

    bytes = [0x0b, 0x88, 0x79, 0x65, 0xf6, 0x26, 0xa4, 0xcd, 0x71, 0xa1, 0x6c, 0x77, 0xdf,
             0x1e, 0x80, 0xc5, 0x4d, 0x67, 0x6d, 0xa0, 0x5e, 0xa6, 0xe9, 0x07, 0x28, 0xbb,
             0xa4, 0x8d, 0x29, 0x02, 0x1f, 0x6a]
    @test stable_hash(DataFrame(; x=1:10, y=1:10); alg=sha256) == bytes

    bytes = [0xe1, 0x11, 0x53, 0xb9, 0xa6, 0x3d, 0x36, 0x2b, 0x2c, 0x02, 0x91, 0x1b, 0xfe,
             0x3d, 0xbb, 0xc8, 0xa8, 0x29, 0x44, 0x55, 0x03, 0x70, 0x68, 0xd7, 0x19, 0x6d,
             0x92, 0xa0, 0x92, 0xd4, 0x1e, 0xdb]
    @test stable_hash([1 2; 3 4]; alg=sha256) == bytes

    # get some code coverage (and reference tests) for sha1
    bytes = [0x2e, 0xa6, 0x1b, 0xde, 0xfe, 0x6e, 0x0a, 0x91, 0x07, 0xb0, 0x3d, 0x82, 0xf6,
             0x55, 0xd7, 0x97, 0x7a, 0x8c, 0x8a, 0x60]
    @test stable_hash([1, 2, 3]; alg=sha1) == bytes

    bytes = [0xa9, 0x01, 0x2a, 0x6e, 0xc7, 0xf0, 0x85, 0x6b, 0x00, 0xee, 0x05, 0xb5, 0x57,
             0xa5, 0x8d, 0x4e, 0xd5, 0x50, 0x33, 0x0a]
    @test stable_hash(v"0.1.0"; alg=sha1) == bytes

    bytes = [0xa2, 0x5d, 0x76, 0xe5, 0xb6, 0x0c, 0x52, 0xca, 0x9d, 0xcb, 0xec, 0xf2, 0x10,
             0x86, 0x00, 0x1c, 0xf9, 0xc5, 0x24, 0x6c]
    @test stable_hash(sin; alg=sha1) == bytes

    bytes = [0xf0, 0xfd, 0x61, 0x9b, 0x9c, 0x53, 0xff, 0x5b, 0xda, 0x46, 0x9b, 0x83, 0x2a,
             0x28, 0x86, 0xe0, 0x4e, 0x10, 0x69, 0x85]
    @test stable_hash(DataFrame(; x=1:10, y=1:10); alg=sha1) == bytes

    bytes = [0xc2, 0xea, 0x81, 0x6d, 0x33, 0x07, 0xf2, 0xdf, 0xb7, 0xd2, 0xb1, 0xa6, 0xaa,
             0x1d, 0xc9, 0x6b, 0x37, 0xeb, 0xd8, 0x2b]
    @test stable_hash([1 2; 3 4]; alg=sha1) == bytes

    # various (in)equalities
    @test stable_hash(CustomHashObject(1:5, 1:10)) !=
          stable_hash(BasicHashObject(1:5, 1:10))
    @test stable_hash([]) != stable_hash([(), (), ()])
    @test stable_hash([1 2; 3 4]) != stable_hash(vec([1 2; 3 4]))
    @test stable_hash([1 2; 3 4]) == stable_hash([1 3; 2 4]')
    @test stable_hash(reshape(1:10, 2, 5)) != stable_hash(reshape(1:10, 5, 2))
    @test stable_hash([(), ()]) != stable_hash([(), (), ()])
    @test stable_hash(DataFrame(; x=1:10, y=1:10)) ==
          stable_hash(NonTableStruct(1:10, 1:10))
    @test stable_hash(1:10) == stable_hash((; start=1, stop=10))
    @test stable_hash([1, 2, 3]) != stable_hash([3, 2, 1])
    @test stable_hash((1, 2, 3)) == stable_hash([1, 2, 3])
    @test stable_hash(v"0.1.0") != stable_hash(v"0.1.2")
    @test stable_hash((a=1, b=2)) != stable_hash((b=2, a=1))
    @test stable_hash((a=1, b=2)) != stable_hash((a=2, b=1))
    @test stable_hash(sin) == stable_hash("Base.sin")
    @test stable_hash([:ab]) != stable_hash([:a, :b])
    @test stable_hash("a", "b") != stable_hash("ab")
    @test stable_hash(["ab"]) != stable_hash(["a", "b"])
    @test stable_hash(sin) != stable_hash(cos)
    @test stable_hash(sin) != stable_hash(:sin)
    @test stable_hash(sin) != stable_hash("sin")
    @test stable_hash(1:10) != stable_hash(collect(1:10))
    @test stable_hash(view(collect(1:5), 1:2)) == stable_hash([1, 2])
    @test_throws ErrorException stable_hash(x -> x + 1)
    @test stable_hash(TestType(1, 2)) == stable_hash(TestType(1, 2))
    @test stable_hash(TestType(1, 2)) == stable_hash((a=1, b=2))
    @test stable_hash(TestType2(1, 2)) != stable_hash((a=1, b=2))
    @test stable_hash(TestType4(1, 2)) == stable_hash(TestType4(1, 2))
    @test stable_hash(TestType4(1, 2)) != stable_hash(TestType3(1, 2))
    @test stable_hash(TestType(1, 2)) == stable_hash(TestType3(2, 1))
    @test stable_hash(TestType(1, 2)) != stable_hash(TestType4(2, 1))
    @test stable_hash(TestType(1, 2); context=MyContext()) != stable_hash(TestType(1, 2))
    @test stable_hash(TestType2(1, 2); context=MyContext()) ==
          stable_hash(TestType2(1, 2); context=MyContext())
end
