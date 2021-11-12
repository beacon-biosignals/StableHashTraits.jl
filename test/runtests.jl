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

SimpleHashes.hashmethod(::TestType) = UseProperties()
SimpleHashes.hashmethod(::TestType2) = UseQualifiedName(UseProperties())

@testset "SimpleHashes.jl" begin
    @test simplehash([1, 2, 3]) != simplehash([3, 2, 1])
    @test simplehash((1, 2, 3)) == simplehash([1, 2, 3])
    @test simplehash((a=1, b=2)) == simplehash((b=2, a=1))
    @test simplehash((a=1, b=2)) != simplehash((a=2, b=1))
    @test simplehash(sin) != simplehash(cos)
    @test_throws ErrorException simplehash(x -> x + 1)
    @test simplehash(TestType(1, 2)) == simplehash(TestType(1, 2))
    @test simplehash(TestType(1, 2)) == simplehash((a=1, b=2))
    @test simplehash(TestType2(1, 2)) != simplehash((a=1, b=2))
end
