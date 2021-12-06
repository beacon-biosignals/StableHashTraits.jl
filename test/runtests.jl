using SimpleHashes
using Aqua
using Test
Aqua.test_all(SimpleHashes)

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

SimpleHashes.hash_method(::TestType) = UseProperties()
SimpleHashes.hash_method(::TestType2) = UseQualifiedName(UseProperties())
SimpleHashes.hash_method(::TestType3) = UseProperties(:ByOrder)
SimpleHashes.hash_method(::TestType4) = UseProperties()

@testset "SimpleHashes.jl" begin
    @test simple_hash([1, 2, 3]) != simple_hash([3, 2, 1])
    @test simple_hash((1, 2, 3)) == simple_hash([1, 2, 3])
    @test simple_hash((a=1, b=2)) == simple_hash((b=2, a=1))
    @test simple_hash((a=1, b=2)) != simple_hash((a=2, b=1))
    @test simple_hash(sin) == simple_hash("Base.sin")
    @test simple_hash([:ab]) != simple_hash([:a, :b])
    @test simple_hash("a", "b") != simple_hash("ab")
    @test simple_hash(["ab"]) != simple_hash(["a", "b"])
    @test simple_hash(sin) != simple_hash(cos)
    @test simple_hash(sin) != simple_hash(:sin)
    @test simple_hash(sin) != simple_hash("sin")
    @test_throws ErrorException simple_hash(x -> x + 1)
    @test simple_hash(TestType(1, 2)) == simple_hash(TestType(1, 2))
    @test simple_hash(TestType(1, 2)) == simple_hash((a=1, b=2))
    @test simple_hash(TestType2(1, 2)) != simple_hash((a=1, b=2))
    @test simple_hash(TestType3(1, 2)) == simple_hash(TestType3(1, 2))
    @test simple_hash(TestType3(1, 2)) != simple_hash(TestType4(1, 2))
    @test simple_hash(TestType(1, 2)) == simple_hash(TestType4(2, 1))
    @test simple_hash(TestType(1, 2)) != simple_hash(TestType3(2, 1))
end
