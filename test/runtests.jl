using StableHashTraits
using Aqua
using Test
using Dates
using UUIDs
using SHA
using DataFrames

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
struct CustomContext{P}
    parent::P
end
function StableHashTraits.hash_method(::CustomHashObject)
    return UseAndReplaceContext(UseProperties(), CustomContext)
end
StableHashTraits.hash_method(::BasicHashObject) = UseProperties()
StableHashTraits.hash_method(::AbstractRange, ::CustomContext) = UseIterate()
function StableHashTraits.hash_method(x::Any, c::CustomContext)
    return StableHashTraits.hash_method(x, c.parent)
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

# TODO: test recursive uses of UseTransform, and property error handling of `UseTransform(identity)`

@testset "StableHashTraits.jl" begin
    # reference tests to ensure hash consistency
    @test stable_hash(()) == 0x48674bc7
    @test stable_hash([1, 2, 3]) == 0x1a366aea
    @test stable_hash([1 2; 3 4]) == 0x62398575
    @test stable_hash((a=1, b=2)) == 0x4940e1e6
    @test stable_hash(Set(1:3)) == 0x9c6a3a2c
    @test stable_hash(sin) == 0xdee3d889
    @test stable_hash(TestType2(1, 2)) == 0xad6f443b
    @test stable_hash(TypeType(Array)) == 0x18f107ef
    @test stable_hash(TestType5("bobo")) == 0x1ba14dde
    @test stable_hash(Nothing) == 0xb9695255
    @test stable_hash(Missing) == 0xafd1df92
    @test stable_hash(v"0.1.0") == 0x436e272d
    @test stable_hash(UUID("8d70055f-1864-48ff-8a94-2c16d4e1d1cd")) == 0xedbef947
    @test stable_hash(Date("2002-01-01")) == 0xc64f50ae
    @test stable_hash(Time("12:00")) == 0x64a54642
    @test stable_hash(TimePeriod(Nanosecond(0))) == 0x58536b6d
    @test stable_hash(Hour(1) + Minute(2)) == 0x4783c75c
    @test stable_hash(DataFrame(; x=1:10, y=1:10)) == 0xa043bc39

    # get some code coverage (and reference tests) for sha256
    bytes = [0xe2, 0x4c, 0xcd, 0x9d, 0xed, 0xaf, 0x29, 0xa7, 0x70, 0x82, 0x2f, 0x5c, 0x30,
             0x01, 0xd6, 0xa4, 0x45, 0x35, 0x18, 0x1d, 0xdd, 0x0f, 0x5c, 0x45, 0xb1, 0xd2,
             0x67, 0xa9, 0x92, 0x19, 0x52, 0x3f]
    @test stable_hash([1, 2, 3]; alg=sha256) == bytes

    bytes = [0x97, 0x83, 0x44, 0x3a, 0x26, 0xa0, 0xda, 0x85, 0x0b, 0xdf, 0x65, 0x11, 0x89,
             0xdf, 0x31, 0xe9, 0x66, 0x33, 0x4f, 0xd6, 0x3b, 0xbd, 0xc7, 0x32, 0x9a, 0xc2,
             0x51, 0xc4, 0xe3, 0x0f, 0xab, 0x47]
    @test stable_hash(v"0.1.0"; alg=sha256) == bytes

    bytes = [0xc1, 0xbe, 0x5c, 0xad, 0x9a, 0xd1, 0xf8, 0xe9, 0xb2, 0x33, 0x8b, 0x48, 0xa6,
             0x4f, 0x4d, 0xf3, 0x98, 0x15, 0x66, 0x95, 0x53, 0x41, 0x3c, 0xa1, 0xb1, 0x05,
             0xbc, 0x2d, 0x94, 0x3d, 0x63, 0x48]
    @test stable_hash(sin; alg=sha256) == bytes

    bytes = [0x9f, 0x96, 0xf2, 0xac, 0x5e, 0x3a, 0xb9, 0x08, 0x86, 0xfc, 0x0d, 0xff, 0x25,
             0x45, 0xf0, 0xbd, 0x12, 0x2d, 0x35, 0x86, 0xdc, 0xb0, 0x59, 0xbe, 0xc4, 0x4c,
             0xe2, 0x68, 0x0e, 0x34, 0x29, 0x78]
    @test stable_hash(Set(1:3); alg=sha256) == bytes

    bytes = [0x52, 0x8e, 0xc7, 0xb6, 0xe6, 0x73, 0x49, 0x7a, 0x82, 0xe1, 0x71, 0x1e, 0xc0,
             0x61, 0x59, 0xba, 0x97, 0x57, 0x26, 0x84, 0x93, 0x14, 0x64, 0x6c, 0x04, 0x02,
             0x0b, 0xf3, 0xb2, 0xac, 0x97, 0x08]
    @test stable_hash(DataFrame(; x=1:10, y=1:10); alg=sha256) == bytes

    bytes = [0xe1, 0x11, 0x53, 0xb9, 0xa6, 0x3d, 0x36, 0x2b, 0x2c, 0x02, 0x91, 0x1b, 0xfe,
             0x3d, 0xbb, 0xc8, 0xa8, 0x29, 0x44, 0x55, 0x03, 0x70, 0x68, 0xd7, 0x19, 0x6d,
             0x92, 0xa0, 0x92, 0xd4, 0x1e, 0xdb]
    @test stable_hash([1 2; 3 4]; alg=sha256) == bytes

    # get some code coverage (and reference tests) for sha1
    bytes = [0x2e, 0xa6, 0x1b, 0xde, 0xfe, 0x6e, 0x0a, 0x91, 0x07, 0xb0, 0x3d, 0x82, 0xf6,
             0x55, 0xd7, 0x97, 0x7a, 0x8c, 0x8a, 0x60]
    @test stable_hash([1, 2, 3]; alg=sha1) == bytes

    bytes = [0x14, 0x1c, 0xbb, 0xcc, 0x9c, 0x1b, 0x58, 0x89, 0x1b, 0x2f, 0xf0, 0x0d, 0xd3,
             0xe1, 0x92, 0x23, 0x9a, 0xab, 0x1c, 0xcf]
    @test stable_hash(v"0.1.0"; alg=sha1) == bytes

    bytes = [0xd1, 0xd4, 0x55, 0x7f, 0xca, 0x18, 0x1f, 0xc6, 0x83, 0x78, 0x8b, 0xef, 0x8b,
             0xe7, 0x85, 0x3a, 0x50, 0x97, 0xfb, 0x91]
    @test stable_hash(sin; alg=sha1) == bytes

    bytes = [0xa2, 0xcf, 0x3f, 0x1a, 0xc5, 0xd9, 0xbf, 0x62, 0xec, 0x15, 0x27, 0x82, 0xfe,
             0xe2, 0xb3, 0xd9, 0x9a, 0x8c, 0x45, 0xc0]
    @test stable_hash(Set(1:3); alg=sha1) == bytes

    bytes = [0x34, 0x15, 0x94, 0xc3, 0xa4, 0x0a, 0x18, 0xb4, 0x25, 0x90, 0xaf, 0x76, 0xc0,
             0x3b, 0x96, 0x6a, 0x3c, 0x36, 0xdb, 0xab]
    @test stable_hash(DataFrame(; x=1:10, y=1:10); alg=sha1) == bytes

    bytes = [0xc2, 0xea, 0x81, 0x6d, 0x33, 0x07, 0xf2, 0xdf, 0xb7, 0xd2, 0xb1, 0xa6, 0xaa,
             0x1d, 0xc9, 0x6b, 0x37, 0xeb, 0xd8, 0x2b]
    @test stable_hash([1 2; 3 4]; alg=sha1) == bytes

    # various (in)equalities
    @test_throws ArgumentError stable_hash(BadTransform())
    @test stable_hash(GoodTransform(2)) == stable_hash(GoodTransform("-0.2")) # verify that transform can be called recurisvely
    @test stable_hash(GoodTransform(3)) != stable_hash(GoodTransform("-0.2"))
    @test stable_hash((; x=collect(1:10), y=collect(1:10))) ==
          stable_hash([(; x=i, y=i) for i in 1:10])
    @test stable_hash([(; x=i, y=i) for i in 1:10]) ==
          stable_hash(DataFrame(; x=1:10, y=1:10))
    @test stable_hash(CustomHashObject(1:5, 1:10)) !=
          stable_hash(BasicHashObject(1:5, 1:10))
    @test stable_hash(Set(1:20)) == stable_hash(Set(reverse(1:20)))
    @test stable_hash([]) != stable_hash([(), (), ()])
    @test stable_hash([1 2; 3 4]) != stable_hash(vec([1 2; 3 4]))
    @test stable_hash([1 2; 3 4]) == stable_hash([1 3; 2 4]')
    @test stable_hash(reshape(1:10, 2, 5)) != stable_hash(reshape(1:10, 5, 2))
    @test stable_hash([(), ()]) != stable_hash([(), (), ()])
    @test stable_hash(DataFrame(; x=1:10, y=1:10)) ==
          stable_hash(NonTableStruct(1:10, 1:10))
    @test stable_hash(1:10) != stable_hash((; start=1, stop=10))
    @test stable_hash([1, 2, 3]) != stable_hash([3, 2, 1])
    @test stable_hash((1, 2, 3)) == stable_hash([1, 2, 3])
    @test stable_hash(v"0.1.0") != stable_hash(v"0.1.2")
    @test stable_hash((a=1, b=2)) != stable_hash((b=2, a=1))
    @test stable_hash((a=1, b=2)) != stable_hash((a=2, b=1))
    @test stable_hash([:ab]) != stable_hash([:a, :b])
    @test stable_hash("a", "b") != stable_hash("ab")
    @test stable_hash(["ab"]) != stable_hash(["a", "b"])
    @test stable_hash(sin) != stable_hash(cos)
    @test stable_hash(sin) != stable_hash(:sin)
    @test stable_hash(sin) != stable_hash("sin")
    @test stable_hash(sin) != stable_hash("Base.sin")
    @test stable_hash(1:10) != stable_hash(collect(1:10))
    @test stable_hash(view(collect(1:5), 1:2)) == stable_hash([1, 2])
    @test_throws ErrorException stable_hash(x -> x + 1)
    @test stable_hash(TestType(1, 2)) == stable_hash(TestType(1, 2))
    @test stable_hash(TestType(1, 2)) != stable_hash((a=1, b=2))
    @test stable_hash(TestType2(1, 2)) != stable_hash((a=1, b=2))
    @test stable_hash(TestType4(1, 2)) == stable_hash(TestType4(1, 2))
    @test stable_hash(TestType4(1, 2)) != stable_hash(TestType3(1, 2))
    @test stable_hash(TestType(1, 2)) == stable_hash(TestType3(2, 1))
    @test stable_hash(TestType(1, 2)) != stable_hash(TestType4(2, 1))
    @test stable_hash(TestType(1, 2); context=MyContext()) != stable_hash(TestType(1, 2))
    @test stable_hash(TestType2(1, 2); context=MyContext()) ==
          stable_hash(TestType2(1, 2); context=MyContext())
end

@testset "Aqua" begin
    Aqua.test_all(StableHashTraits)
end
