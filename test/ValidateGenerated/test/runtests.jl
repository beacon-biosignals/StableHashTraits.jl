# NOTE: this should be run with julia --compiled-modules=no
using Test
@testset "StableHashTraits `@generated` functions are properly defined" begin
    import StableHashTraits, CRC32c
    @test StableHashTraits.stable_hash("hello"; alg=CRC32c.crc32c, version=2) == 0x9f8db41f
end
