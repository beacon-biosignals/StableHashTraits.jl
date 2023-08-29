using BenchmarkTools
using StableHashTraits

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

suite["numbers"] = BenchmarkGroup(["numbers"])
data = rand(Int, 10_000)
suite["numbers"]["base"] = @benchmarkable fnv(data)
suite["numbers"]["trait"] = @benchmarkable stable_hash(data; alg=$(fnv))

suite["tuples"] = BenchmarkGroup(["tuples"])
data1 = rand(Int, 2, 10_000)
data2 = tuple.(rand(Int, 10_000), rand(Int, 10_000))
suite["tuples"]["base"] = @benchmarkable fnv(reinterpret(UInt8, data1))
suite["tuples"]["trait"] = @benchmarkable stable_hash(data2; alg=$(fnv))

# DATAPOINT: the recursive hashing itself, even without slowdowns from SHA
# buffers is substantial; this can be fixed by optimizing how primitive
# types are hashed (when `UseWrite` is set)

# DATAPOINT: hashing arrays of tuples vs. matrices has overhead
# because of the qualified name; if we can cash this string computation
# per type, we should hopefully be much faster (try that next)

# NEXT DATAPOINT: how much does sha's allocations slow things down?

# NEXT DATAPOINT: how does this work when working with many small structs
# (does the type hashing add a lot or is it mostly about the allocations?)

# NOTE: we can also probably further optimize by circumventing the `write`
# operations for primitive types that can be directly hashed

# If a cache of tuned parameters already exists, use it, otherwise, tune and cache
# the benchmark parameters. Reusing cached parameters is faster and more reliable
# than re-tuning `suite` every time the file is included.
paramspath = joinpath(dirname(@__FILE__), "params.json")

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
