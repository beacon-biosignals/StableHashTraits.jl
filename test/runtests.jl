using StableHashTraits
using Aqua
using Test
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

@testset "StableHashTraits.jl" begin
    @test stable_hash([1, 2, 3]) == 0x1a366aea
    @test stable_hash((a=1, b=2)) == 0x240bb84c
    @test stable_hash(sin) == 0x7706a39f
    @test stable_hash(TestType2(1, 2)) == 0x1f99ed3b
    @test stable_hash(TypeType(Array)) == 0xae27dba8
    @test stable_hash(TestType5("bobo")) == 0x85c469dd
    @test stable_hash(Nothing) == 0xb9695255
    @test stable_hash(Missing) == 0xafd1df92
    @test stable_hash(v"0.1.0") == 0x50cda5b5

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
end
