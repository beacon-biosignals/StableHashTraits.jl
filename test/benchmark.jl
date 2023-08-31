using BenchmarkTools
using StableHashTraits
using SHA

# Define a parent BenchmarkGroup to contain our suite
const suite = BenchmarkGroup()

# TODO: benchmark to verify various similar timings:
# numbers vs. Base.hash of those numbers
# array of numbers vs. Base.hash of those numbers
# matrix to array of tuples
# 
# numbers vsthat tuples of numbers are as fast as fast
# as structs of those numbers

# https://en.wikipedia.org/wiki/Fowler%E2%80%93Noll%E2%80%93Vo_hash_function
const FNV_BASIS=0xcbf29ce484222325
const FNV_PRIME=0x00000100000001B3
function fnv(bytes, hash::UInt64=FNV_BASIS)
    @inbounds for b in bytes
        hash *= FNV_PRIME
        hash ⊻= b
    end
    return hash
end

# NOTE: this result is supiciously fast, not clear why it would be
# better than `fnv` alone
suite["numbers"] = BenchmarkGroup(["numbers"])
data = rand(Int, 10_000)
suite["numbers"]["base"] = @benchmarkable $(fnv)(data)
suite["numbers"]["trait"] = @benchmarkable stable_hash(data, HashVersion{2}(); alg=$(fnv))

suite["tuples"] = BenchmarkGroup(["tuples"])
data1 = rand(Int, 2, 10_000)
data2 = tuple.(rand(Int, 10_000), rand(Int, 10_000))
suite["tuples"]["base"] = @benchmarkable stable_hash(data1, HashVersion{2}(), alg=$(fnv))
suite["tuples"]["trait"] = @benchmarkable stable_hash(data2, HashVersion{2}(); alg=$(fnv))

suite["sha_tuples"] = BenchmarkGroup(["sha_tuples"])
data1 = rand(Int, 2, 10_000)
data2 = tuple.(rand(Int, 10_000), rand(Int, 10_000))
suite["sha_tuples"]["base"] = @benchmarkable stable_hash(data1, HashVersion{2}(), alg=$(sha256))
suite["sha_tuples"]["trait"] = @benchmarkable stable_hash(data2, HashVersion{2}(); alg=$(sha256))

suite["sha_numbers"] = BenchmarkGroup(["sha_numbers"])
suite["sha_numbers"]["base"] = @benchmarkable sha256(reinterpret(UInt8, data))
suite["sha_numbers"]["trait"] = @benchmarkable stable_hash(data, HashVersion{2}(); alg=$(sha256))

suite["strings"] = BenchmarkGroup(["strings"])
strings = [String(rand('a':'z', 30)) for _ in 1:10_000]
strdata = [c for str in strings for c in str]
suite["strings"]["base"] = @benchmarkable fnv($(reinterpret(UInt8, strdata)))
suite["strings"]["trait"] = @benchmarkable stable_hash(strings, HashVersion{2}(), alg=$(fnv))

struct BenchTest
    a::Int
    b::Int
end
structs = [BenchTest(rand(Int), rand(Int)) for _ in 1:10_000]
struct_data = [x for st in structs for x in (st.a, st.b)]
suite["structs"] = BenchmarkGroup(["structs"])
suite["structs"]["base"] = @benchmarkable fnv($(reinterpret(UInt8, struct_data)))
suite["structs"]["trait"] = @benchmarkable stable_hash(structs, HashVersion{2}(), alg=$(fnv))

suite["sha_structs"] = BenchmarkGroup(["sha_structs"])
suite["sha_structs"]["base"] = @benchmarkable sha256($(reinterpret(UInt8, struct_data)))
suite["sha_structs"]["trait"] = @benchmarkable stable_hash(structs, HashVersion{2}(), alg=$(sha256))

# TODO: create a benchmark for DataFrames

# If a cache of tuned parameters already exists, use it, otherwise, tune and cache
# the benchmark parameters. Reusing cached parameters is faster and more reliable
# than re-tuning `suite` every time the file is included.
paramspath = joinpath(dirname(@__FILE__), "benchparams.json")

if isfile(paramspath)
    loadparams!(suite, BenchmarkTools.load(paramspath)[1], :evals)
else
    tune!(suite)
    BenchmarkTools.save(paramspath, params(suite))
end

result = run(suite)

for case in keys(result)
    m2 = median(result[case]["base"])
    m1 = median(result[case]["trait"])
    println("")
    println("$case: ratio to baseline")
    println("----------------------------------------")
    display(ratio(m1,m2))
end
