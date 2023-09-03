include("setup_tests.jl")

crc(x, s=0x000000) = crc32c(collect(x), s)
V = 2 # 1
hashfn = sha256 # sha1, crc
ctx = HashVersion{V}()
test_hash(x, c=ctx) = stable_hash(x, c; alg=hashfn)

