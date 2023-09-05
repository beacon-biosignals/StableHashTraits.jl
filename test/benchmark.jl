using BenchmarkTools
using StableHashTraits
using DataFrames
using SHA
using CRC32c

crc(x, s=0x000000) = crc32c(collect(x), s)

# Define a parent BenchmarkGroup to contain our suite
const suite = BenchmarkGroup()

# TODO: benchmark to verify various similar timings:
# numbers vs. Base.hash of those numbers
# array of numbers vs. Base.hash of those numbers
# matrix to array of tuples
# 
# numbers vsthat tuples of numbers are as fast as fast
# as structs of those numbers

struct BenchTest
    a::Int
    b::Int
end

data = rand(Int, 10_000)
data1 = vec(rand(Int, 2, 10_000))
data2 = tuple.(rand(Int, 10_000), rand(Int, 10_000))
strings = [String(rand('a':'z', 30)) for _ in 1:10_000]
strdata = [c for str in strings for c in str]
symbols = [Symbol(String(rand('a':'z', 30))) for _ in 1:10_000]
symdata = [c for sym in symbols for c in String(sym)]
structs = [BenchTest(rand(Int), rand(Int)) for _ in 1:10_000]
struct_data = [x for st in structs for x in (st.a, st.b)]
df = DataFrame(; x=1:10_000, y=1:10_000)

for hashfn in (crc, sha256)
    suite["numbers_$(nameof(hashfn))"] = BenchmarkGroup(["numbers"])
    suite["numbers_$(nameof(hashfn))"]["base"] = @benchmarkable $(hashfn)($(reinterpret(UInt8,
                                                                                        data)))
    suite["numbers_$(nameof(hashfn))"]["trait"] = @benchmarkable $(stable_hash)(data,
                                                                                HashVersion{1}();
                                                                                alg=$(hashfn))

    suite["tuples_$(nameof(hashfn))"] = BenchmarkGroup(["tuples"])
    suite["tuples_$(nameof(hashfn))"]["base"] = @benchmarkable $(stable_hash)(data1,
                                                                              HashVersion{1}(),
                                                                              alg=$(hashfn))
    suite["tuples_$(nameof(hashfn))"]["trait"] = @benchmarkable $(stable_hash)(data2,
                                                                               HashVersion{1}();
                                                                               alg=$(hashfn))

    suite["strings_$(nameof(hashfn))"] = BenchmarkGroup(["strings"])
    suite["strings_$(nameof(hashfn))"]["base"] = @benchmarkable $(hashfn)($(reinterpret(UInt8,
                                                                                        strdata)))
    suite["strings_$(nameof(hashfn))"]["trait"] = @benchmarkable $(stable_hash)(strings,
                                                                                HashVersion{1}(),
                                                                                alg=$(hashfn))

    suite["symbols_$(nameof(hashfn))"] = BenchmarkGroup(["symbols"])
    suite["symbols_$(nameof(hashfn))"]["base"] = @benchmarkable $(hashfn)($(reinterpret(UInt8,
                                                                                        symdata)))
    suite["symbols_$(nameof(hashfn))"]["trait"] = @benchmarkable $(stable_hash)(symbols,
                                                                                HashVersion{1}(),
                                                                                alg=$(hashfn))

    suite["structs_$(nameof(hashfn))"] = BenchmarkGroup(["structs"])
    suite["structs_$(nameof(hashfn))"]["base"] = @benchmarkable $(hashfn)($(reinterpret(UInt8,
                                                                                        struct_data)))
    suite["structs_$(nameof(hashfn))"]["trait"] = @benchmarkable $(stable_hash)(structs,
                                                                                HashVersion{1}(),
                                                                                alg=$(hashfn))

    suite["dataframes_$(nameof(hashfn))"] = BenchmarkGroup(["dataframes"])
    suite["dataframes_$(nameof(hashfn))"]["base"] = @benchmarkable $(hashfn)($(reinterpret(UInt8,
                                                                                           data1)))
    suite["dataframes_$(nameof(hashfn))"]["trait"] = @benchmarkable $(stable_hash)(df,
                                                                                   HashVersion{1}(),
                                                                                   alg=$(hashfn))
end

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

timestr(x) = replace(sprint(show, x), r"TrialEstimate\((.*)\)" => s"\1")
rows = map(collect(keys(result))) do case
    m2 = median(result[case]["base"])
    m1 = median(result[case]["trait"])
    r1 = ratio(m1, m2)
    benchmark, hash = split(case, "_")
    return (; benchmark, hash, base=timestr(m2), trait=timestr(m1), ratio=r1.time)
end
display(sort(DataFrame(rows), [:hash, order(:ratio; rev=true)]))

# TODO: create a markdown table with absolute results and ratios
