include("setup_tests.jl")

V = 4
hashfn = crc32c
ctx = HashVersion{V}()
test_hash(x, c=ctx) = stable_hash(x, c; alg=hashfn)
