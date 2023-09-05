using BenchmarkTools
using StableHashTraits
using DataFrames
using SHA
using CRC32c

crc(x, s=0x000000) = crc32c(collect(x), s)

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

# Define a parent BenchmarkGroup to contain our suite
const suite = BenchmarkGroup()

for hashfn in (crc, sha256)
    hstr = nameof(hashfn)
    suite["numbers_$hstr"] = BenchmarkGroup(["numbers"])
    suite["numbers_$hstr"]["base"] = @benchmarkable $(hashfn)($(reinterpret(UInt8, data)))
    suite["numbers_$hstr"]["trait"] = @benchmarkable $(stable_hash)(data, HashVersion{1}();
                                                                    alg=$(hashfn))

    suite["tuples_$hstr"] = BenchmarkGroup(["tuples"])
    suite["tuples_$hstr"]["base"] = @benchmarkable $(stable_hash)(data1, HashVersion{1}();
                                                                  alg=$(hashfn))
    suite["tuples_$hstr"]["trait"] = @benchmarkable $(stable_hash)(data2, HashVersion{1}();
                                                                   alg=$(hashfn))

    suite["strings_$hstr"] = BenchmarkGroup(["strings"])
    suite["strings_$hstr"]["base"] = @benchmarkable $(hashfn)($(reinterpret(UInt8, strdata)))
    suite["strings_$hstr"]["trait"] = @benchmarkable $(stable_hash)(strings, Hash;
                                                                    alg=$(hashfn))

    suite["symbols_$hstr"] = BenchmarkGroup(["symbols"])
    suite["symbols_$hstr"]["base"] = @benchmarkable $(hashfn)($(reinterpret(UInt8, symdata)))
    suite["symbols_$hstr"]["trait"] = @benchmarkable $(stable_hash)(symbols,
                                                                    HashVersion{1}();
                                                                    alg=$(hashfn))

    suite["structs_$hstr"] = BenchmarkGroup(["structs"])
    suite["structs_$hstr"]["base"] = @benchmarkable $(hashfn)($(reinterpret(UInt8,
                                                                            struct_data)))
    suite["structs_$hstr"]["trait"] = @benchmarkable $(stable_hash)(structs,
                                                                    HashVersion{1}();
                                                                    alg=$(hashfn))

    suite["dataframes_$hstr"] = BenchmarkGroup(["dataframes"])
    suite["dataframes_$hstr"]["base"] = @benchmarkable $(hashfn)($(reinterpret(UInt8,
                                                                               data1)))
    suite["dataframes_$hstr"]["trait"] = @benchmarkable $(stable_hash)(df, HashVersion{1}();
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

