include("setup_tests.jl")

crc(x, s=0x000000) = crc32c(collect(x), s)
crc(x::Union{SubArray{UInt8},Vector{UInt8}}, s=0x000000) = crc32c(x, s)
V = 4
hashfn = crc # sha256 # sha1, crc
ctx = HashVersion{V}()
test_hash(x, c=ctx) = stable_hash(x, c; alg=hashfn)
