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
suite["numbers"]["trait"] = @benchmarkable stable_hash(data; alg=$(fnv))

suite["tuples"] = BenchmarkGroup(["tuples"])
data1 = rand(Int, 2, 10_000)
data2 = tuple.(rand(Int, 10_000), rand(Int, 10_000))
suite["tuples"]["base"] = @benchmarkable stable_hash(data1, alg=$(fnv))
suite["tuples"]["trait"] = @benchmarkable stable_hash(data2; alg=$(fnv))

suite["sha_tuples"] = BenchmarkGroup(["sha_tuples"])
data1 = rand(Int, 2, 10_000)
data2 = tuple.(rand(Int, 10_000), rand(Int, 10_000))
suite["sha_tuples"]["base"] = @benchmarkable stable_hash(data1, alg=$(sha256))
suite["sha_tuples"]["trait"] = @benchmarkable stable_hash(data2; alg=$(sha256))

suite["sha_numbers"] = BenchmarkGroup(["sha_numbers"])
suite["sha_numbers"]["base"] = @benchmarkable sha256(reinterpret(UInt8, data))
suite["sha_numbers"]["trait"] = @benchmarkable stable_hash(data; alg=$(sha256))

suite["strings"] = BenchmarkGroup(["strings"])
strings = [String(rand('a':'z', 30)) for _ in 1:10_000]
strdata = [c for str in strings for c in str]
suite["strings"]["base"] = @benchmarkable fnv($(reinterpret(UInt8, strdata)))
suite["strings"]["trait"] = @benchmarkable stable_hash(strings, alg=$(fnv))

struct BenchTest
    a::Int
    b::Int
end
structs = [BenchTest(rand(Int), rand(Int)) for _ in 1:10_000]
struct_data = [x for st in structs for x in (st.a, st.b)]
suite["structs"] = BenchmarkGroup(["structs"])
suite["structs"]["base"] = @benchmarkable fnv($(reinterpret(UInt8, struct_data)))
suite["structs"]["trait"] = @benchmarkable stable_hash(structs, alg=$(fnv))

suite["sha_structs"] = BenchmarkGroup(["sha_structs"])
suite["sha_structs"]["base"] = @benchmarkable sha256($(reinterpret(UInt8, struct_data)))
suite["sha_structs"]["trait"] = @benchmarkable stable_hash(structs, alg=$(sha256))

# DATAPOINT: the recursive hashing itself, even without slowdowns from SHA
# buffers is substantial; this can be fixed by optimizing how primitive
# types are hashed (when `UseWrite` is set)

# DATAPOINT: hashing arrays of tuples vs. matrices has overhead
# because of the qualified name; if we can cash this string computation
# per type, we should hopefully be much faster (try that next)

# DATAPOINT: how much does sha's allocations slow things down? with the optimization
# to avoid recursive sha, we get decent SHA performance

# DATAPOINT: what about hashing an array of strings? looks reasonable

# DATAPOINT: how does this work when working with many small structs? this seems to break
# down when using SHA algorithsm; I could probably work around this for a lot of cases if
# the data is composed of long arrays of objects (but I don't know if that's a good
# assumption) why is this happening? is it that calls to `update!` with small amounts of
# data are slower than large chunks of data? (if that were the case, why isn't sha_numbers
# worse?); 
# THOUGHT: in looking at where the calls are dominating, this looks to be something about
# bounds checking, and handling the block offsets (i.e. if the update is not
# for a complete block)
# ANSWER: nope, that doesn't seem to do the trick, even if we manually set 
# we still see slow times, though it is no longer completley dominated by `copyto`
# (its' still there but more of the time is in the actual guts of `update!`)
# NOTE: it seems like, for SHA, it is better to write out a bunch of data
# and then compute the sha, rather than make many small updates??? that seems plausible
# if so, we should setup some buffer that stores data and writes it as needed

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
