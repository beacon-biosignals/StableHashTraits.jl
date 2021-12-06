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

SimpleHashes.hash_method(::TestType) = UseProperties()
SimpleHashes.hash_method(::TestType2) = UseQualifiedName(UseProperties())

@testset "SimpleHashes.jl" begin
    @test simple_hash([1, 2, 3]) != simple_hash([3, 2, 1])
    @test simple_hash((1, 2, 3)) == simple_hash([1, 2, 3])
    @test simple_hash((a=1, b=2)) == simple_hash((b=2, a=1))
    @test simple_hash((a=1, b=2)) != simple_hash((a=2, b=1))
    @test simple_hash(sin) != simple_hash(cos)
    @test_throws ErrorException simple_hash(x -> x + 1)
    @test simple_hash(TestType(1, 2)) == simple_hash(TestType(1, 2))
    @test simple_hash(TestType(1, 2)) == simple_hash((a=1, b=2))
    @test simple_hash(TestType2(1, 2)) != simple_hash((a=1, b=2))
end
