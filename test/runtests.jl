using StableHashTraits
using Aqua
using Test
using Dates
using UUIDs
using SHA
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

@testset "StableHashTraits.jl" begin
    # reference tests to ensure hash consistency
    @test stable_hash(()) == 0x48674bc7
    @test stable_hash([1, 2, 3]) == 0x1a366aea
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

    # various (in)equalities
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
